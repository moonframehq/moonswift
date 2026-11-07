import CLuau

public struct LuauError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Receives `log` lines from the VM through a C callback.
private final class LogSink {
    let write: (String) -> Void

    init(write: @escaping (String) -> Void) {
        self.write = write
    }
}

/// One sandboxed Luau state and a thin, typed stack API over it. Only
/// `call` runs Luau code, and it catches everything that code can raise.
final class LuauVM {
    /// Deepest table `read` follows, which also stops cycles.
    private static let maxDepth = 48
    /// Most table entries `read` copies out of the VM in one go.
    private static let maxEntries = 200_000

    private let state: OpaquePointer
    private let sink: Unmanaged<LogSink>

    init(chunk: String, memory: Int, budget: UInt64, log: @escaping (String) -> Void) throws(LuauError) {
        let sink = Unmanaged.passRetained(LogSink(write: log))
        let opened = moon_open(chunk, memory, budget, { line, length, context in
            guard let line, let context else { return }
            let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(line).assumingMemoryBound(to: UInt8.self), count: length)
            Unmanaged<LogSink>.fromOpaque(context).takeUnretainedValue().write(String(decoding: bytes, as: UTF8.self))
        }, sink.toOpaque())
        guard let opened else {
            sink.release()
            throw LuauError("could not open a Luau state")
        }
        state = opened
        self.sink = sink
    }

    isolated deinit {
        moon_close(state)
        sink.release()
    }

    /// Bytes this state holds.
    var memory: Int { moon_memory(state) }

    /// Compiles `source` and leaves the function on the stack.
    func load(_ source: String, name: String) throws(LuauError) {
        let status = source.withCString { text in
            moon_load(state, name, text, source.utf8.count)
        }
        if status != 0 { throw popError() }
    }

    /// Calls the function under its `arguments`, leaving `results` values.
    func call(arguments: Int32 = 0, results: Int32 = 0) throws(LuauError) {
        if moon_call(state, arguments, results) != 0 { throw popError() }
    }

    /// Runs `body` and puts the stack back as it was, whatever happens.
    func balanced<T>(_ body: () throws(LuauError) -> T) throws(LuauError) -> T {
        let top = lua_gettop(state)
        defer { lua_settop(state, top) }
        return try body()
    }

    func pop(_ count: Int32 = 1) {
        lua_settop(state, -count - 1)
    }

    // MARK: Globals and references

    func setGlobal(_ name: String) {
        lua_setfield(state, Int32(MOON_GLOBALS), name)
    }

    func seal() {
        moon_seal(state)
    }

    func newTable() {
        lua_createtable(state, 0, 0)
    }

    /// `table[name] = value`, with the table under the value on the stack.
    func setField(_ name: String) {
        lua_setfield(state, -2, name)
    }

    /// Pushes `name` from the table at `index`, without running metamethods.
    func pushRawField(_ name: String, at index: Int32 = -1) {
        let table = lua_absindex(state, index)
        pushString(name)
        lua_rawget(state, table)
    }

    /// Pops the top of the stack into the registry, for later.
    func reference() -> Int32 {
        let reference = lua_ref(state, -1)
        pop()
        return reference
    }

    func pushReference(_ reference: Int32) {
        lua_rawgeti(state, Int32(MOON_REGISTRY), reference)
    }

    func release(_ reference: Int32) {
        lua_unref(state, reference)
    }

    var topIsTable: Bool { lua_type(state, -1) == Int32(LUA_TTABLE.rawValue) }
    var topIsFunction: Bool { lua_type(state, -1) == Int32(LUA_TFUNCTION.rawValue) }
    var topIsNil: Bool { lua_type(state, -1) == Int32(LUA_TNIL.rawValue) }

    // MARK: Values

    func pushNil() {
        lua_pushnil(state)
    }

    func push(_ value: LuauValue?) {
        lua_checkstack(state, 4)
        switch value {
        case nil: lua_pushnil(state)
        case .bool(let value): lua_pushboolean(state, value ? 1 : 0)
        case .number(let value): lua_pushnumber(state, value)
        case .string(let value): pushString(value)
        case .table(let array, let fields):
            lua_createtable(state, Int32(array.count), Int32(fields.count))
            for (index, item) in array.enumerated() {
                push(item)
                lua_rawseti(state, -2, Int32(index + 1))
            }
            for (key, item) in fields {
                pushString(key)
                push(item)
                lua_rawset(state, -3)
            }
        }
    }

    /// Copies the value at `index` out, nil for nil, functions and userdata.
    /// Reads raw, so no metamethod (no Luau code) runs. A throw leaves the
    /// stack dirty: call it inside `balanced`.
    func read(at index: Int32 = -1) throws(LuauError) -> LuauValue? {
        var entries = 0
        return try read(at: lua_absindex(state, index), depth: 0, entries: &entries)
    }

    private func read(at index: Int32, depth: Int, entries: inout Int) throws(LuauError) -> LuauValue? {
        switch UInt32(lua_type(state, index)) {
        case LUA_TBOOLEAN.rawValue: return .bool(lua_toboolean(state, index) != 0)
        case LUA_TNUMBER.rawValue: return .number(lua_tonumberx(state, index, nil))
        case LUA_TSTRING.rawValue: return .string(string(at: index))
        case LUA_TTABLE.rawValue: break
        default: return nil
        }
        guard depth < Self.maxDepth else { throw LuauError("a table is nested too deep, or holds itself") }

        var items: [(position: Int, value: LuauValue)] = []
        var fields: [String: LuauValue] = [:]
        lua_checkstack(state, 4)
        lua_pushnil(state)
        while lua_next(state, index) != 0 {
            defer { pop() }
            entries += 1
            guard entries <= Self.maxEntries else { throw LuauError("a table has too many entries") }
            guard let value = try read(at: lua_gettop(state), depth: depth + 1, entries: &entries) else { continue }
            switch UInt32(lua_type(state, -2)) {
            case LUA_TSTRING.rawValue: fields[string(at: -2)] = value
            case LUA_TNUMBER.rawValue: items.append((Int(lua_tonumberx(state, -2, nil)), value))
            default: break
            }
        }
        items.sort { $0.position < $1.position }
        return .table(array: items.map(\.value), fields: fields)
    }

    private func pushString(_ value: String) {
        var value = value
        value.withUTF8 { bytes in
            lua_pushlstring(state, UnsafeRawPointer(bytes.baseAddress)?.assumingMemoryBound(to: CChar.self), bytes.count)
        }
    }

    /// The string at `index`, which must be one: a number would convert in
    /// place and break `lua_next`.
    private func string(at index: Int32) -> String {
        var length = 0
        guard let text = lua_tolstring(state, index, &length) else { return "" }
        let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(text).assumingMemoryBound(to: UInt8.self), count: length)
        return String(decoding: bytes, as: UTF8.self)
    }

    private func popError() -> LuauError {
        defer { pop() }
        return LuauError(lua_type(state, -1) == Int32(LUA_TSTRING.rawValue) ? string(at: -1) : "unknown Luau error")
    }
}
