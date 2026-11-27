/// What the host tells every `view`, as `app`.
public struct AppContext: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var dark: Bool
    /// `active`, `inactive` or `background`, as the scene is.
    public var phase = "active"

    public init(width: Double = 960, height: Double = 640, dark: Bool = false) {
        self.width = width
        self.height = height
        self.dark = dark
    }

    public var value: LuauValue {
        .fields([
            "window": .fields(["width": .number(width), "height": .number(height)]),
            "appearance": .string(dark ? "dark" : "light"),
            "platform": .string(Self.platform),
            "phase": .string(phase),
        ])
    }

    #if os(iOS)
    static let platform = "ios"
    #else
    static let platform = "macos"
    #endif
}

/// An element of a checked tree. Anything a script gets wrong becomes an
/// `.invalid` node, drawn as a small warning mark, never a blank window.
nonisolated public struct Node: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        // Layout.
        case row, column, panel, spacer, divider, scroll, grid, fits
        // Navigation and lists.
        case stack, tabs, tab, split, list, section, form, link, disclosure
        // Content.
        case text, label, labeled, badge, icon, image, progress, unavailable
        // Controls.
        case button, input, secure, editor, toggle, slider, stepper, picker, menu, share, edit
        // The host's: other mods, and views the app registers natively.
        case region, mount, native
        case invalid
    }

    public let kind: Kind
    public let props: [String: LuauValue]
    public let children: [Node]
    /// The line of the mod's file that built this element.
    public let line: Int?
    /// Why this is `.invalid`.
    public let problem: String?
    /// A hash of this whole subtree, made once as it is checked. Two trees
    /// with the same digest are taken as equal, so comparing a tree with the
    /// last one costs one integer however big it is, and a view can skip a
    /// subtree that didn't change without walking it.
    public let digest: Int

    public static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.digest == rhs.digest
    }

    public init(_ value: LuauValue) {
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
            digest = Self.digest(kind: .invalid, props: [:], children: [], extra: name)
            return
        }
        self.kind = kind
        props = fields
        // `flag and ui.text { ... }` leaves false in the list: that's nothing.
        children = array.filter { $0 != .bool(false) }.map(Node.init)
        problem = nil
        digest = Self.digest(kind: kind, props: fields, children: children, extra: line.map(String.init))
    }

    private init(invalid problem: String) {
        kind = .invalid
        props = [:]
        children = []
        line = nil
        self.problem = problem
        digest = Self.digest(kind: .invalid, props: [:], children: [], extra: problem)
    }

    private static func digest(kind: Kind, props: [String: LuauValue], children: [Node], extra: String?) -> Int {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(props)
        hasher.combine(extra)
        hasher.combine(children.count)
        for child in children { hasher.combine(child.digest) }
        return hasher.finalize()
    }

    public static func invalid(_ problem: String) -> Node {
        Node(invalid: problem)
    }

    public func string(_ key: String) -> String? { props[key]?.string }
    public func number(_ key: String) -> Double? { props[key]?.number }
    public func flag(_ key: String) -> Bool { props[key]?.bool ?? false }

    /// The text this element shows, if any.
    public var text: String? {
        switch kind {
        case .text, .badge, .label, .link, .labeled: string("text")
        case .share: string("label")
        case .button, .toggle, .menu, .picker, .stepper, .disclosure: string("label")
        case .icon, .native: string("name")
        case .input, .secure, .editor: string("placeholder")
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

nonisolated extension Node {
    /// Elements held in a prop rather than as children, such as a row's
    /// `swipe` buttons or a view's `toolbar`: a list of them, or just one.
    public func elements(_ key: String) -> [Node] {
        guard let value = props[key] else { return [] }
        if value["type"] != nil { return [Node(value)] }
        return (value.array ?? []).filter { $0 != .bool(false) }.map(Node.init)
    }

    /// A prop that is an overlay: `{ open = ..., dismiss = ..., <element> }`,
    /// as `sheet` and `alert`. Its elements are its list part.
    public func overlay(_ key: String) -> Overlay? {
        guard case .table(let array, let fields)? = props[key] else { return nil }
        return Overlay(fields: fields, content: array.filter { $0 != .bool(false) }.map(Node.init))
    }

    /// Lazy rows: `rows` lists their keys, `row` names the mod's view that
    /// draws one.
    public var lazyRows: (keys: [LuauValue], view: String)? {
        guard let view = string("row"), let keys = props["rows"]?.array else { return nil }
        return (keys, view)
    }
}

/// A sheet, alert or dialog a view asks for, open or not.
nonisolated public struct Overlay: Equatable, Sendable {
    public let fields: [String: LuauValue]
    public let content: [Node]

    public init(fields: [String: LuauValue], content: [Node]) {
        self.fields = fields
        self.content = content
    }

    public var open: Bool { fields["open"]?.bool ?? false }
    public func string(_ key: String) -> String? { fields[key]?.string }
}
