/// What the host tells every `view`, as `app`.
public struct AppContext: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var dark: Bool

    public init(width: Double = 960, height: Double = 640, dark: Bool = false) {
        self.width = width
        self.height = height
        self.dark = dark
    }

    var value: LuauValue {
        .fields([
            "window": .fields(["width": .number(width), "height": .number(height)]),
            "appearance": .string(dark ? "dark" : "light"),
        ])
    }
}

/// An element of a checked tree. Anything a script gets wrong becomes an
/// `.invalid` node, drawn as a small warning mark, never a blank window.
public struct Node: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case row, column, panel, spacer, divider, text, badge, icon, button, input, toggle, slider, region, mount
        case invalid
    }

    public let kind: Kind
    public let props: [String: LuauValue]
    public let children: [Node]
    /// The line of the mod's file that built this element.
    public let line: Int?
    /// Why this is `.invalid`.
    public let problem: String?

    init(_ value: LuauValue) {
        guard case .table(let array, var fields) = value else {
            self = .invalid("expected an element, got \(value.summary)")
            return
        }
        guard let name = fields.removeValue(forKey: "type")?.string else {
            self = .invalid("this table is not an element: use ui.row, ui.text, ...")
            return
        }
        line = fields.removeValue(forKey: "__line")?.number.map(Int.init)
        guard let kind = Kind(rawValue: name), kind != .invalid else {
            self.kind = .invalid
            props = [:]
            children = []
            problem = "no element named \(name)"
            return
        }
        self.kind = kind
        props = fields
        // `flag and ui.text { ... }` leaves false in the list: that's nothing.
        children = array.filter { $0 != .bool(false) }.map(Node.init)
        problem = nil
    }

    private init(invalid problem: String) {
        kind = .invalid
        props = [:]
        children = []
        line = nil
        self.problem = problem
    }

    static func invalid(_ problem: String) -> Node {
        Node(invalid: problem)
    }

    public func string(_ key: String) -> String? { props[key]?.string }
    public func number(_ key: String) -> Double? { props[key]?.number }
    public func flag(_ key: String) -> Bool { props[key]?.bool ?? false }

    /// The text this element shows, if any.
    public var text: String? {
        switch kind {
        case .text, .badge: string("text")
        case .button, .toggle: string("label")
        case .icon: string("name")
        case .input: string("placeholder")
        case .region: string("name")
        case .mount: string("mod")
        default: string("title")
        }
    }

    /// `button "Add"`, as the inspector names it.
    public var label: String {
        guard let text else { return kind.rawValue }
        let quote = text.count > 40 ? text.prefix(40) + "…" : Substring(text)
        return "\(kind.rawValue) \"\(quote)\""
    }

    /// What identifies this element among its siblings across updates.
    public func identity(at index: Int) -> String {
        string("key") ?? string("id") ?? String(index)
    }

    /// The element at `path`, as the renderer builds them: identities joined
    /// with `/`, starting under this node.
    public func node(at path: String) -> Node? {
        var current = self
        for part in path.split(separator: "/") {
            let found = current.children.enumerated().first { $0.element.identity(at: $0.offset) == part }
            guard let found else { return nil }
            current = found.element
        }
        return current
    }

    /// Every `.invalid` element in this tree.
    public var problems: [String] {
        (kind == .invalid ? [problem ?? "bad element"] : []) + children.flatMap(\.problems)
    }
}
