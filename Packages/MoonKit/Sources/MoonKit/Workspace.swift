import Foundation
import Observation

/// What went wrong in a file. The window keeps the last good view meanwhile.
public struct Problem: Equatable, Sendable, Identifiable {
    public let file: String
    public let message: String
    public var id: String { file }
}

/// What one mod drew. Each mod has its own, so a change redraws only the
/// views that show that mod, not the whole window.
@Observable
public final class Drawing {
    public internal(set) var tree: Node?
    /// Goes up whenever the mod's state or data may have changed: what its
    /// lazy views (rows, screens) drew before is stale then.
    public internal(set) var generation = 0

    init() {}
}

/// The whole app: every module, the trees they drew and the stylesheet.
/// `reload` swaps in what changed on disk with each mod's state kept, and a
/// module that fails to load leaves the running one, and its view, in place.
@Observable
public final class Workspace {
    public static let shell = "shell"
    private static let styleFile = "style.luau"
    /// Messages one send may set off, which stops two mods ping-ponging.
    private static let maxMessages = 1000

    /// Every mod's tree. Reading this follows all of them: a view should
    /// read `drawing(of:)` instead.
    public var trees: [String: Node] { drawings.compactMapValues(\.tree) }
    /// The mods running, which regions follow.
    public private(set) var names: Set<String> = []
    /// Goes up with every redraw, for animations.
    public private(set) var revision = 0
    public private(set) var stylesheet = Stylesheet()
    public internal(set) var problems: [String: Problem] = [:]
    /// Reloads that changed something, and how long the last one took.
    public private(set) var reloads = 0
    public private(set) var lastReload: Duration = .zero
    public private(set) var logs: [String] = []

    public let folders: Folders
    public var context = AppContext() {
        didSet { if context != oldValue { renderAll() } }
    }

    @ObservationIgnored private let limits: Limits
    @ObservationIgnored private var modules: [String: Module] = [:] {
        didSet {
            let running = Set(modules.keys)
            if running != names { names = running }
        }
    }
    @ObservationIgnored private var drawings: [String: Drawing] = [:]
    /// Lazy views drawn this generation, per mod.
    @ObservationIgnored private var parts: [String: (generation: Int, nodes: [PartKey: Node])] = [:]
    @ObservationIgnored var providers: [String: ProviderSlot] = [:]
    /// Each topic's last value, which a mod hears as it loads.
    @ObservationIgnored private(set) var topics: [String: LuauValue] = [:]
    /// The providers each mod's view read last, which redraw it.
    @ObservationIgnored private var reads: [String: Set<String>] = [:]
    @ObservationIgnored private var modSheets: [String: ModSheet] = [:]
    /// What was last tried per file, so a broken file is not retried until
    /// it changes.
    @ObservationIgnored private var attempted: [String: String] = [:]
    @ObservationIgnored private var queue: [Queued] = []
    @ObservationIgnored private var draining = false

    public init(folders: Folders, limits: Limits = Limits()) {
        self.folders = folders
        self.limits = limits
    }

    // MARK: Reading

    /// Mods placed in `region`, in order.
    public func mods(in region: String) -> [String] {
        _ = names
        return modules.values.filter { $0.region == region }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            .map(\.name)
    }

    /// The file a mod runs from, relative to the app folder.
    public func file(of mod: String) -> String {
        mod == Self.shell ? "main.luau" : "mods/\(mod)/main.luau"
    }

    public func problem(of mod: String) -> Problem? {
        problems[file(of: mod)]
    }

    /// Bytes `mod`'s VM holds, state and code.
    public func memory(of mod: String) -> Int? {
        modules[mod]?.memory
    }

    /// What `mod` drew, to observe it alone.
    public func drawing(of mod: String) -> Drawing {
        if let drawing = drawings[mod] { return drawing }
        let drawing = Drawing()
        drawings[mod] = drawing
        return drawing
    }

    /// What the `function`-th function of the mod's tree draws for `key`,
    /// such as a list's `row(i)`: drawn on first ask in each generation,
    /// then kept. One that fails draws as a warning mark.
    public func part(_ function: Int, key: LuauValue, of mod: String) -> Node {
        let generation = drawing(of: mod).generation
        let id = PartKey(function: function, key: key)
        if let cached = parts[mod], cached.generation == generation, let node = cached.nodes[id] {
            return node
        }
        guard let module = modules[mod] else { return .invalid("no mod named \(mod)") }
        var node: Node
        do throws(LuauError) {
            sync(module)
            node = try module.call(function, with: key)
            reads[mod, default: []].formUnion(try module.read())
        } catch {
            node = .invalid(error.message)
        }
        if parts[mod]?.generation != generation { parts[mod] = (generation, [:]) }
        parts[mod]?.nodes[id] = node
        return node
    }

    // MARK: Reloading

    /// Brings the app in line with the folders. Cheap when nothing changed.
    public func reload() {
        let clock = ContinuousClock()
        let start = clock.now
        let components = folders.names(in: "components").compactMap(component)
        let componentsChanged = components != lastComponents
        lastComponents = components

        var changed = false
        var loaded: [String] = []
        let names = [Self.shell] + folders.names(in: "mods").filter { $0 != Self.shell }
        for name in names {
            let file = file(of: name)
            guard let source = folders.read(file) else { continue }
            let stale = attempted[file] != source || componentsChanged
            guard stale else { continue }
            attempted[file] = source
            changed = true
            if load(name: name, file: file, source: source, components: components) { loaded.append(name) }
        }
        // Files tried before that are gone, including ones that never loaded.
        for file in attempted.keys where file != Self.styleFile && folders.read(file) == nil {
            let name = file == "main.luau" ? Self.shell : file.split(separator: "/")[1].description
            modules[name] = nil
            reads[name] = nil
            drawings[name]?.tree = nil
            parts[name] = nil
            problems[file] = nil
            attempted[file] = nil
            changed = true
        }
        changed = reloadStyle(components: components, force: componentsChanged) || changed
        started(loaded)
        if changed {
            reloads += 1
            lastReload = clock.now - start
        }
    }

    @ObservationIgnored private var lastComponents: [Component] = []

    private func component(_ entry: String) -> Component? {
        guard entry.hasSuffix(".luau") else { return nil }
        let file = "components/\(entry)"
        return folders.read(file).map { Component(name: String(entry.dropLast(5)), file: file, source: $0) }
    }

    /// True if it loaded, and replaced what ran before.
    private func load(name: String, file: String, source: String, components: [Component]) -> Bool {
        do throws(LuauError) {
            let running = modules[name]
            let module = try Module(
                name: name, file: file, source: source, previous: try running?.snapshot(),
                components: components, limits: limits, log: logger(for: name)
            )
            sync(module)
            let tree = try module.view(context.value)
            reads[name] = try module.read()
            modules[name] = module
            show(tree, of: name)
            problems[file] = nil
            return true
        } catch {
            problems[file] = Problem(file: file, message: error.message)
            return false
        }
    }

    /// Mods that just loaded hear their topics' current values, then what
    /// each `init` sent goes out.
    private func started(_ names: [String]) {
        var first: [Queued] = []
        for name in names {
            guard let module = modules[name] else { continue }
            for topic in topics.keys.sorted() where module.subscribes(to: topic) {
                first.append(Queued(send: Send(to: name, message: Self.event(topic, topics[topic])), from: nil))
            }
        }
        for name in names {
            first += modules[name]?.takePending().map { Queued(send: $0, from: name) } ?? []
        }
        guard !first.isEmpty else { return }
        queue += first
        drain()
    }

    static func event(_ topic: String, _ value: LuauValue?) -> LuauValue {
        var fields: [String: LuauValue] = ["topic": .string(topic)]
        fields["value"] = value
        return .fields(fields)
    }

    /// True if the stylesheet was looked at again.
    private func reloadStyle(components: [Component], force: Bool) -> Bool {
        let file = Self.styleFile
        let source = folders.read(file) ?? ""
        guard attempted[file] != source || force else { return false }
        attempted[file] = source
        guard !source.isEmpty else {
            stylesheet = Stylesheet()
            problems[file] = nil
            return true
        }
        do throws(LuauError) {
            let sheet = try Module.evaluate(
                file: file, source: source, components: components, limits: limits, log: logger(for: "style")
            )
            stylesheet = Stylesheet(sheet)
            problems[file] = nil
        } catch {
            problems[file] = Problem(file: file, message: error.message)
        }
        return true
    }

    private func logger(for name: String) -> (String) -> Void {
        { [weak self] line in
            self?.logs.append("[\(name)] \(line)")
            if let logs = self?.logs, logs.count > 200 { self?.logs.removeFirst(logs.count - 200) }
        }
    }

    // MARK: Messages

    /// Delivers `message` to the mod `to`, or to whoever subscribes to
    /// `topic:<name>`, and everything that sets off, then redraws.
    public func send(_ message: LuauValue, to: String) {
        send(message, to: to, from: nil)
    }

    func send(_ message: LuauValue, to: String, from: String?) {
        queue.append(Queued(send: Send(to: to, message: message), from: from))
        drain()
    }

    private func drain() {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        var delivered = 0
        var touched: Set<String> = []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            delivered += 1
            if delivered > Self.maxMessages {
                problems["messages"] = Problem(file: "messages", message: "too many messages at once; do two mods answer each other?")
                queue.removeAll()
                break
            }
            if next.send.to.hasPrefix("provider:") {
                deliverToProvider(next)
                continue
            }
            if next.send.to.hasPrefix("app:") {
                let file = next.from.map(file(of:)) ?? "messages"
                problems[file] = Problem(file: file, message: "this app answers no \(next.send.to)")
                continue
            }
            for (name, message) in recipients(of: next) {
                deliver(message, to: name)
                touched.insert(name)
            }
        }
        for name in touched { render(name) }
    }

    private func recipients(of queued: Queued) -> [(String, LuauValue)] {
        let send = queued.send
        // `provider/` is the providers' and `app/` the app's: no mod's to
        // publish, nor to forge as a topic event sent straight to a mod.
        let topic = send.to.hasPrefix("topic:") ? String(send.to.dropFirst("topic:".count)) : send.message["topic"]?.string
        if queued.from != nil, let topic, Self.reserved(topic) {
            let file = queued.from.map(file(of:)) ?? "messages"
            problems[file] = Problem(file: file, message: "topic \(topic) is not a mod's to publish")
            return []
        }
        guard send.to.hasPrefix("topic:"), let topic else { return [(send.to, send.message)] }
        topics[topic] = send.message
        return subscribers(of: topic, value: send.message)
    }

    private static func reserved(_ topic: String) -> Bool {
        topic.hasPrefix("provider/") || topic.hasPrefix("app/")
    }

    private func subscribers(of topic: String, value: LuauValue) -> [(String, LuauValue)] {
        let event = Self.event(topic, value)
        return modules.values.filter { $0.subscribes(to: topic) }.sorted { $0.name < $1.name }.map { ($0.name, event) }
    }

    private func deliver(_ message: LuauValue, to name: String) {
        guard let module = modules[name] else { return }
        do throws(LuauError) {
            queue += try module.update(message).map { Queued(send: $0, from: name) }
            problems[module.file] = nil
        } catch {
            problems[module.file] = Problem(file: module.file, message: error.message)
        }
    }

    func render(_ name: String) {
        guard let module = modules[name] else { return }
        do throws(LuauError) {
            sync(module)
            let tree = try module.view(context.value)
            reads[name] = try module.read()
            show(tree, of: name)
        } catch {
            problems[module.file] = Problem(file: module.file, message: error.message)
        }
    }

    /// Puts up a mod's new tree, and marks its lazy views stale.
    private func show(_ tree: Node, of name: String) {
        let drawing = drawing(of: name)
        drawing.generation += 1
        if drawing.tree != tree { drawing.tree = tree }
        revision += 1
    }

    private func renderAll() {
        modules.keys.forEach(render)
    }

    /// Brings the provider data a module's VM holds up to date, copying
    /// only what was published since it last looked.
    private func sync(_ module: Module) {
        for (name, slot) in providers where module.versions[name] != slot.version {
            module.setData(name, slot.value, version: slot.version)
        }
    }

    /// A provider published: the mods whose views read it draw again, and
    /// those subscribed to `provider/<name>` hear it.
    func providerChanged(_ name: String) {
        let topic = "provider/\(name)"
        if let value = providers[name]?.value {
            queue += subscribers(of: topic, value: value).map { Queued(send: Send(to: $0.0, message: $0.1), from: nil) }
            drain()
        }
        for module in modules.values where reads[module.name]?.contains(name) == true {
            render(module.name)
        }
    }

    // MARK: Conformance

    /// The tree `mod`'s view returns now, as data, its functions kept as
    /// `{ __function = n }`.
    func rawView(of mod: String) throws(LuauError) -> LuauValue? {
        guard let module = modules[mod] else { throw LuauError("no mod named \(mod)") }
        sync(module)
        return try module.rawView(context.value)
    }

    /// What the `function`-th function of `mod`'s last raw view returns.
    func rawCall(_ function: Int, with argument: LuauValue, of mod: String) throws(LuauError) -> LuauValue? {
        guard let module = modules[mod] else { throw LuauError("no mod named \(mod)") }
        return try module.rawCall(function, with: argument)
    }

    /// The stylesheet for what `mod` draws: `style.luau` with the mod's own
    /// `styles` under it.
    public func stylesheet(for mod: String) -> Stylesheet {
        let sheet = stylesheet
        guard let styles = modules[mod]?.styles else { return sheet }
        if let kept = modSheets[mod], kept.base == sheet, kept.styles == styles { return kept.sheet }
        let merged = sheet.with(styles: styles)
        modSheets[mod] = ModSheet(base: sheet, styles: styles, sheet: merged)
        return merged
    }
}

/// A lazy view of a mod: the function in its tree, and the key.
struct PartKey: Hashable {
    let function: Int
    let key: LuauValue
}

/// A mod's stylesheet, and what it was made from.
struct ModSheet {
    let base: Stylesheet
    let styles: LuauValue
    let sheet: Stylesheet
}

/// A send waiting to go, and the mod that sent it, if any.
struct Queued {
    let send: Send
    let from: String?
}
