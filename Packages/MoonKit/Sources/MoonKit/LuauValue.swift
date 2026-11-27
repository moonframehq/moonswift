/// Plain data that crosses between Luau and Swift: messages, a mod's state
/// across reloads, and trees. Functions and userdata stay in the VM.
nonisolated public enum LuauValue: Equatable, Hashable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case table(array: [LuauValue], fields: [String: LuauValue])

    public static let emptyTable = LuauValue.table(array: [], fields: [:])

    public static func fields(_ fields: [String: LuauValue]) -> LuauValue {
        .table(array: [], fields: fields)
    }

    public subscript(key: String) -> LuauValue? {
        guard case .table(_, let fields) = self else { return nil }
        return fields[key]
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The number as an `Int`, nil for one that isn't finite, held to
    /// ±1e9: `Int(math.huge)` from a script would trap the host.
    public var integer: Int? {
        number.flatMap(Self.integer)
    }

    public static func integer(_ number: Double) -> Int? {
        guard number.isFinite else { return nil }
        return Int(min(max(number, -1e9), 1e9))
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [LuauValue]? {
        if case .table(let array, _) = self { return array }
        return nil
    }

    /// One line, as the inspector shows it.
    public var summary: String {
        switch self {
        case .bool(let value): String(value)
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 { String(Int(value)) } else { String(value) }
        case .string(let value): "\"\(value)\""
        case .table(let array, let fields):
            "{ " + (array.map(\.summary) + fields.keys.sorted().map { "\($0) = \(fields[$0]!.summary)" })
                .joined(separator: ", ") + " }"
        }
    }
}
