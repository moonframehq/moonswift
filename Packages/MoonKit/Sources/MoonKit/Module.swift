/// A message a mod sends: to another mod, or to `topic:<name>`.
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
/// Elm-shaped: `init` makes the state, `update` changes it, `view` draws it.
final class Module {
    let name: String
    let file: String
    let source: String
    let region: String?
    let order: Double
    let subscriptions: [String]
    /// The providers whose data this mod reads as `app.<name>`; only these
    /// redraw it when they change.
    let providers: [String]

    private let vm: LuauVM
    private let definition: Int32
    private var state: Int32

    /// Runs `source` and its `init`, which gets the `previous` state back.
    init(
        name: String, file: String, source: String, previous: LuauValue?,
        components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) throws(LuauError) {
        let vm = try Self.sealedVM(chunk: file, components: components, limits: limits, log: log)
        let definition: Int32 = try vm.balanced { () throws(LuauError) in
            try vm.load(source, name: file)
            try vm.call(results: 1)
            // A script can return anything, whatever `mod` would have said.
            guard vm.topIsTable else { throw LuauError("\(file) must return mod { ... }") }
            vm.pushRawField("view")
            guard vm.topIsFunction else { throw LuauError("\(file): a mod needs a view function") }
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
        let providers = try setting("providers")?.array?.compactMap(\.string) ?? []

        let state: Int32 = try vm.balanced { () throws(LuauError) in
            vm.pushReference(definition)
            vm.pushRawField("init")
            if vm.topIsFunction {
                vm.push(previous)
                try vm.call(arguments: 1, results: 1)
            } else {
                vm.pop()
                vm.push(previous)
            }
            if vm.topIsNil {
                vm.pop()
                vm.newTable()
            }
            return vm.reference()
        }

        self.name = name
        self.file = file
        self.source = source
        self.vm = vm
        self.definition = definition
        self.state = state
        self.region = region
        self.order = order
        self.subscriptions = subscriptions
        self.providers = providers
    }

    var memory: Int { vm.memory }

    /// The state as plain data, to hand to the next version of this module.
    func snapshot() throws(LuauError) -> LuauValue? {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(state)
            return try vm.read()
        }
    }

    /// `update(state, msg)`. It may change the state in place or return a new
    /// one, and a list of `{ to = ..., msg = ... }` to send on.
    func update(_ message: LuauValue) throws(LuauError) -> [Send] {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(definition)
            vm.pushRawField("update")
            guard vm.topIsFunction else { return [] }
            vm.pushReference(state)
            vm.push(message)
            try vm.call(arguments: 2, results: 2)
            let sends = try vm.read()
            vm.pop()
            if !vm.topIsNil {
                vm.release(state)
                state = vm.reference()
            }
            return (sends?.array ?? []).compactMap { send in
                guard let to = send["to"]?.string, let message = send["msg"] else { return nil }
                return Send(to: to, message: message)
            }
        }
    }

    /// `view(state, app)`, checked into a tree.
    func view(_ context: LuauValue) throws(LuauError) -> Node {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(definition)
            vm.pushRawField("view")
            vm.pushReference(state)
            vm.push(context)
            try vm.call(arguments: 2, results: 1)
            guard let tree = try vm.read() else { throw LuauError("\(file): view returned nothing") }
            return Node(tree)
        }
    }

    /// `views[name](state, key, app)`: one of the mod's named views, which
    /// the host draws lazily, such as a list's rows or a stack's screens.
    func part(_ name: String, key: LuauValue, context: LuauValue) throws(LuauError) -> Node {
        try vm.balanced { () throws(LuauError) in
            vm.pushReference(definition)
            vm.pushRawField("views")
            guard vm.topIsTable else { throw LuauError("\(file): no views table for \(name)") }
            vm.pushRawField(name)
            guard vm.topIsFunction else { throw LuauError("\(file): no view named \(name) in views") }
            vm.pushReference(state)
            vm.push(key)
            vm.push(context)
            try vm.call(arguments: 3, results: 1)
            guard let tree = try vm.read() else { throw LuauError("\(file): views.\(name) returned nothing") }
            return Node(tree)
        }
    }

    /// Evaluates a `style { ... }` file to plain data.
    static func evaluate(
        file: String, source: String, components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) throws(LuauError) -> LuauValue? {
        let vm = try sealedVM(chunk: file, components: components, limits: limits, log: log)
        return try vm.balanced { () throws(LuauError) in
            try vm.load(source, name: file)
            try vm.call(results: 1)
            return try vm.read()
        }
    }

    private static func sealedVM(
        chunk: String, components: [Component], limits: Limits, log: @escaping (String) -> Void
    ) throws(LuauError) -> LuauVM {
        let vm = try LuauVM(chunk: chunk, memory: limits.memory, budget: limits.budget, log: log)
        try vm.balanced { () throws(LuauError) in
            vm.newTable()
            for component in components {
                try vm.load(component.source, name: component.file)
                vm.setField(component.name)
            }
            vm.setGlobal("__components")
            try vm.load(prelude, name: "prelude")
            try vm.call(results: 4)
            vm.setGlobal("use")
            vm.setGlobal("style")
            vm.setGlobal("mod")
            vm.setGlobal("ui")
            vm.pushNil()
            vm.setGlobal("__components")
            vm.pushNil()
            vm.setGlobal("__caller_line")
        }
        vm.seal()
        return vm
    }
}
