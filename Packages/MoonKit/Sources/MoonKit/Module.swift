/// A message a mod sends: to another mod, `topic:<name>` or `provider:<name>`.
public struct Send: Equatable, Sendable {
    public let to: String
    public let message: LuauValue

    public init(to: String, message: LuauValue) {
        self.to = to
        self.message = message
    }
}

/// The limits every module runs under.
public struct Limits: Sendable {
    public var memory = 64 * 1024 * 1024
    /// Interrupts per call: roughly one per loop iteration and function call.
    public var budget: UInt64 = 10_000_000

    public init() {}
}

/// A source file a module can `use`, by name.
public struct Component: Equatable, Sendable {
    public let name: String
    public let file: String
    public let source: String
}

/// One loaded `main.luau` or mod: its own sealed VM, and the state inside it.
/// Elm-shaped, as in Moonframe: `init` makes the state, `update` changes it,
/// `view` draws it, and the first two may send messages on.
final class Module {
    /// The keys `mod { }` takes: Moonframe's, so a mod that loads here loads
    /// there. Some only mean something on the desktop and are not used here.
    static let keys: Set<String> = [
        "init", "update", "view", "region", "order", "title", "styles", "window", "subscribe", "tab",
        "menus", "about", "keys", "paste",
    ]

    let name: String
    let file: String
    let source: String
    let region: String?
    let order: Double
    /// Topic names, or prefixes ending in `*`.
    let subscriptions: [String]
    /// The mod's own style rules, for what it draws.
    let styles: LuauValue?
    /// What `init` sent, for the workspace to deliver once everything loaded.
    private(set) var pending: [Send]

    private let vm: LuauVM
    private let definition: Int32
    private var state: Int32
    /// `lens(fields, data, reads)` from the prelude, which makes `app`.
    private let lens: Int32
    /// Each provider's data as this VM holds it, and the names the last
    /// view read from `app`.
    private let data: Int32
    private var reads: Int32
    /// The functions the last view's tree holds, such as a list's `row`.
    private var functions: [Int32] = []
    /// The provider data versions this VM holds.
    var versions: [String: Int] = [:]

    /// Runs `source` and its `init`, which gets the `previous` state back.
    init(
        name: String, file: String, source: String, previous: LuauValue?,
        components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) throws(LuauError) {
        let (vm, lens) = try Self.sealedVM(chunk: file, components: components, limits: limits, log: log)
        let definition: Int32 = try vm.balanced { () throws(LuauError) in
            try vm.load(source, name: file)
            try vm.call(results: 1)
            // A script can return anything, whatever `mod` would have said.
            guard vm.topIsTable else { throw LuauError("\(file) must return mod { ... }") }
            let unknown = vm.keys().filter { !Self.keys.contains($0) }.sorted()
            if let key = unknown.first {
                throw LuauError("\(file): mod has no key `\(key)`; it takes \(Self.keys.sorted().joined(separator: ", "))")
            }
            vm.pushRawField("view")
            guard vm.topIsFunction else { throw LuauError("\(file): mod needs a `view` function") }
            vm.pop()
            return vm.reference()
        }
        func setting(_ key: String) throws(LuauError) -> LuauValue? {
            try vm.balanced { () throws(LuauError) in
                vm.pushReference(definition)
                vm.pushRawField(key)
                return try vm.read()
            }
        }
        let region = try setting("region")?.string
        let order = try setting("order")?.number ?? 0
        let subscriptions = try setting("subscribe")?.array?.compactMap(\.string) ?? []
        let styles = try setting("styles")

        let (state, pending): (Int32, [Send]) = try vm.balanced { () throws(LuauError) in
            vm.pushReference(definition)
            vm.pushRawField("init")
            var sends: LuauValue?
            if vm.topIsFunction {
                vm.push(previous)
                vm.pushNil()
                vm.push(.bool(false))
                try vm.call(arguments: 3, results: 2)
                sends = try vm.read()
                vm.pop()
            } else {
                vm.pop()
                vm.push(previous)
            }
            if vm.topIsNil {
                vm.pop()
                vm.newTable()
            }
            return (vm.reference(), Self.sends(sends))
        }
        vm.newTable()
        let data = vm.reference()
        vm.newTable()
        let reads = vm.reference()

        self.name = name
        self.file = file
        self.source = source
        self.vm = vm
        self.definition = definition
        self.state = state
        self.lens = lens
        self.data = data
        self.reads = reads
        self.region = region
        self.order = order
        self.subscriptions = subscriptions
        self.styles = styles
        self.pending = pending
    }

    var memory: Int { vm.memory }

    /// Hands over what `init` sent, once.
    func takePending() -> [Send] {
        defer { pending = [] }
        return pending
    }

    /// Whether it hears `topic`: by name, or by a prefix ending in `*`.
    func subscribes(to topic: String) -> Bool {
        subscriptions.contains { pattern in
            pattern.hasSuffix("*") ? topic.hasPrefix(pattern.dropLast()) : pattern == topic
        }
    }

    /// The state as plain data, to hand to the next version of this module.
    func snapshot() throws(LuauError) -> LuauValue? {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(state)
            return try vm.read()
        }
    }

    /// `update(state, msg, props)`. It may change the state in place or
    /// return a new one, and a list of `{ to = ..., msg = ... }` to send on.
    func update(_ message: LuauValue) throws(LuauError) -> [Send] {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(definition)
            vm.pushRawField("update")
            guard vm.topIsFunction else { return [] }
            vm.pushReference(state)
            vm.push(message)
            vm.pushNil()
            try vm.call(arguments: 3, results: 2)
            let sends = try vm.read()
            vm.pop()
            if !vm.topIsNil {
                vm.release(state)
                state = vm.reference()
            }
            return Self.sends(sends)
        }
    }

    private static func sends(_ value: LuauValue?) -> [Send] {
        (value?.array ?? []).compactMap { send in
            guard let to = send["to"]?.string else { return nil }
            return Send(to: to, message: send["msg"] ?? .bool(false))
        }
    }

    // MARK: Drawing

    /// Puts a provider's data where `app.<name>` finds it.
    func setData(_ name: String, _ value: LuauValue?, version: Int) {
        vm.setRaw(name, value, in: data)
        versions[name] = version
    }

    /// The `app` keys the last view, and the rows it built since, read
    /// through the lens: the providers it depends on.
    func read() throws(LuauError) -> Set<String> {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(reads)
            return Set(vm.keys())
        }
    }

    /// `view(state, app, props)`, checked into a tree. Functions in the tree
    /// stay callable through `call` until the next view.
    func view(_ fields: LuauValue) throws(LuauError) -> Node {
        guard let tree = try rawView(fields) else { throw LuauError("\(file): view returned nothing") }
        return Node(tree)
    }

    /// The tree as the view returned it, its functions kept as
    /// `{ __function = n }`.
    func rawView(_ fields: LuauValue) throws(LuauError) -> LuauValue? {
        try vm.balanced { () throws(LuauError) in
            vm.release(reads)
            vm.newTable()
            reads = vm.reference()
            vm.pushReference(definition)
            vm.pushRawField("view")
            vm.pushReference(state)
            vm.pushReference(lens)
            vm.push(fields)
            vm.pushReference(data)
            vm.pushReference(reads)
            try vm.call(arguments: 3, results: 1)
            vm.pushNil()
            try vm.call(arguments: 3, results: 1)
            let (tree, kept) = try vm.readKeepingFunctions()
            functions.forEach(vm.release)
            functions = kept
            return tree
        }
    }

    /// Calls the `number`-th function of the last view's tree with
    /// `argument`, such as a list's `row(i)`, and checks what it returns.
    func call(_ number: Int, with argument: LuauValue) throws(LuauError) -> Node {
        Node(try rawCall(number, with: argument) ?? .fields(["type": .string("column")]))
    }

    /// What the `number`-th function returns for `argument`, unchecked.
    func rawCall(_ number: Int, with argument: LuauValue) throws(LuauError) -> LuauValue? {
        guard functions.indices.contains(number - 1) else { throw LuauError("\(file): that view is gone") }
        return try vm.balanced { () throws(LuauError) in
            vm.pushReference(functions[number - 1])
            vm.push(argument)
            try vm.call(arguments: 1, results: 1)
            return try vm.read()
        }
    }

    // MARK: Loading

    /// Evaluates a `style { ... }` file to plain data.
    static func evaluate(
        file: String, source: String, components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) throws(LuauError) -> LuauValue? {
        let (vm, _) = try sealedVM(chunk: file, components: components, limits: limits, log: log)
        return try vm.balanced { () throws(LuauError) in
            try vm.load(source, name: file)
            try vm.call(results: 1)
            return try vm.read()
        }
    }

    /// Each component's `styles`, run in one VM; one that fails to load
    /// is left out, as `use` reports it where it is used.
    static func styles(
        of components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) -> [(String, LuauValue)] {
        guard !components.isEmpty, let (vm, _) = try? sealedVM(chunk: "components", components: [], limits: limits, log: log)
        else { return [] }
        let sorted = components.sorted { $0.name < $1.name }
        return sorted.compactMap { component in
            try? vm.balanced { () throws(LuauError) -> (String, LuauValue)? in
                try vm.load(component.source, name: component.file)
                try vm.call(results: 1)
                guard vm.topIsTable else { return nil }
                vm.pushRawField("styles")
                return try vm.read().map { (component.name, $0) }
            } ?? nil
        }
    }

    private static func sealedVM(
        chunk: String, components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) throws(LuauError) -> (LuauVM, lens: Int32) {
        let vm = try LuauVM(chunk: chunk, memory: limits.memory, budget: limits.budget, log: log)
        let lens: Int32 = try vm.balanced { () throws(LuauError) in
            vm.newTable()
            for component in components {
                try vm.load(component.source, name: component.file)
                vm.setField(component.name)
            }
            vm.setGlobal("__components")
            try vm.load(prelude, name: "prelude")
            try vm.call(results: 7)
            let lens = vm.reference()
            vm.setGlobal("component")
            vm.setGlobal("send")
            vm.setGlobal("use")
            vm.setGlobal("style")
            vm.setGlobal("mod")
            vm.setGlobal("ui")
            vm.pushNil()
            vm.setGlobal("__components")
            vm.pushNil()
            vm.setGlobal("__caller_line")
            return lens
        }
        vm.seal()
        return (vm, lens)
    }
}
