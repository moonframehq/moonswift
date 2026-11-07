import Foundation
import Observation

/// What went wrong in a file. The window keeps the last good view meanwhile.
public struct Problem: Equatable, Sendable, Identifiable {
    public let file: String
    public let message: String
    public var id: String { file }
}

/// The whole app: every module, the trees they drew and the stylesheet.
/// `reload` swaps in what changed on disk with each mod's state kept, and a
/// module that fails to load leaves the running one, and its view, in place.
@Observable
public final class Workspace {
    public static let shell = "main"
    private static let styleFile = "style.luau"
    /// Messages one send may set off, which stops two mods ping-ponging.
    private static let maxMessages = 1000

    public private(set) var trees: [String: Node] = [:]
    public private(set) var stylesheet = Stylesheet()
    public private(set) var problems: [String: Problem] = [:]
    /// Reloads that changed something, and how long the last one took.
    public private(set) var reloads = 0
    public private(set) var lastReload: Duration = .zero
    public private(set) var logs: [String] = []

    public let folders: Folders
    public var context = AppContext() {
        didSet { if context != oldValue { renderAll() } }
    }

    @ObservationIgnored private let limits: Limits
    @ObservationIgnored private var modules: [String: Module] = [:]
    /// What was last tried per file, so a broken file is not retried until
    /// it changes.
    @ObservationIgnored private var attempted: [String: String] = [:]
    @ObservationIgnored private var queue: [Send] = []
    @ObservationIgnored private var draining = false

    public init(folders: Folders, limits: Limits = Limits()) {
        self.folders = folders
        self.limits = limits
    }

    // MARK: Reading

    /// Mods placed in `region`, in order.
    public func mods(in region: String) -> [String] {
        modules.values.filter { $0.region == region }
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

    // MARK: Reloading

    /// Brings the app in line with the folders. Cheap when nothing changed.
    public func reload() {
        let clock = ContinuousClock()
        let start = clock.now
        let components = folders.names(in: "components").compactMap(component)
        let componentsChanged = components != lastComponents
        lastComponents = components

        var changed = false
        let names = [Self.shell] + folders.names(in: "mods")
        for name in names {
            let file = file(of: name)
            guard let source = folders.read(file) else { continue }
            let stale = attempted[file] != source || componentsChanged
            guard stale else { continue }
            attempted[file] = source
            changed = true
            load(name: name, file: file, source: source, components: components)
        }
        // Files tried before that are gone, including ones that never loaded.
        for file in attempted.keys where file != Self.styleFile && folders.read(file) == nil {
            let name = file == "main.luau" ? Self.shell : file.split(separator: "/")[1].description
            modules[name] = nil
            trees[name] = nil
            problems[file] = nil
            attempted[file] = nil
            changed = true
        }
        changed = reloadStyle(components: components, force: componentsChanged) || changed
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

    private func load(name: String, file: String, source: String, components: [Component]) {
        do throws(LuauError) {
            let running = modules[name]
            let module = try Module(
                name: name, file: file, source: source, previous: try running?.snapshot(),
                components: components, limits: limits, log: logger(for: name)
            )
            let tree = try module.view(context)
            modules[name] = module
            trees[name] = tree
            problems[file] = nil
        } catch {
            problems[file] = Problem(file: file, message: error.message)
        }
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
        queue.append(Send(to: to, message: message))
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
            for (name, message) in recipients(of: next) {
                deliver(message, to: name)
                touched.insert(name)
            }
        }
        for name in touched { render(name) }
    }

    private func recipients(of send: Send) -> [(String, LuauValue)] {
        guard send.to.hasPrefix("topic:") else { return [(send.to, send.message)] }
        let topic = String(send.to.dropFirst("topic:".count))
        let event = LuauValue.fields(["topic": .string(topic), "value": send.message])
        return modules.values.filter { $0.subscriptions.contains(topic) }.map { ($0.name, event) }
    }

    private func deliver(_ message: LuauValue, to name: String) {
        guard let module = modules[name] else { return }
        do throws(LuauError) {
            queue += try module.update(message)
            problems[module.file] = nil
        } catch {
            problems[module.file] = Problem(file: module.file, message: error.message)
        }
    }

    private func render(_ name: String) {
        guard let module = modules[name] else { return }
        do throws(LuauError) {
            let tree = try module.view(context)
            if trees[name] != tree { trees[name] = tree }
        } catch {
            problems[module.file] = Problem(file: module.file, message: error.message)
        }
    }

    private func renderAll() {
        modules.keys.forEach(render)
    }
}
