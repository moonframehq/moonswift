/// What the host tells every `view`, as `app`, besides providers' data.
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

    /// As Moonframe's `app`: `dark`, `appearance`, `window` with the
    /// platform and size, and `renderer`, which is `swiftui` here. `phase`
    /// is MoonSwift's own.
    public var value: LuauValue {
        .fields([
            "dark": .bool(dark),
            "appearance": .fields(["mode": .string("system"), "dark": .bool(dark)]),
            "window": .fields([
                "platform": .string(Self.platform),
                "width": .number(width),
                "height": .number(height),
            ]),
            "renderer": .string("swiftui"),
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
        case row, column, panel, spacer, divider, scroll, grid, fits, hsplit, vsplit, pane
        // Navigation and lists.
        case stack, tabs, tab, split, list, section, form, link, disclosure, item
        // Content.
        case text, markdown, label, labeled, badge, icon, image, progress, unavailable
        // Controls.
        case button, input, secure, editor, toggle, slider, stepper, picker, menu, share, edit
        // Floating over the rest.
        case popover, overlay
        // The host's: other mods, and views the app registers natively.
        case region, mount, native, view, terminal
        // Moonframe's, which draw here as a placeholder naming them.
        case browser, map, video, line, paths, hatch
        case revisionTimeline = "revision_timeline"
        // What `use` gives for a component that isn't here, or that keeps
        // state of its own: placeholders the workspace warns about.
        case missing, instance
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
    /// The axis its parent lays children along: `grow = true` grows that
    /// way only, as in Moonframe. Nil at a root, which grows both ways.
    public let axis: Axis?
    /// Whether its parent grows and stretches what it holds across its
    /// axis, as a Moonframe stack does unless its `align` says otherwise:
    /// `grow = true` then fills that way too.
    public let stretched: Bool
    /// Whether its parent is a column that stretches what it holds across
    /// its width, as Moonframe's do unless `align` says otherwise.
    public let across: Bool

    public enum Axis: Sendable { case horizontal, vertical }

    public static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.digest == rhs.digest
    }

    public init(_ value: LuauValue) {
        self.init(value, axis: nil, stretched: false, across: false)
    }

    private init(_ value: LuauValue, axis: Axis?, stretched: Bool, across: Bool) {
        guard case .table(let array, var fields) = value else {
            self = .invalid("expected an element, got \(value.summary)")
            return
        }
        guard let name = fields.removeValue(forKey: "type")?.string else {
            self = .invalid("this table is not an element: use ui.row, ui.text, ...")
            return
        }
        self.axis = axis
        self.stretched = stretched
        self.across = across
        line = fields.removeValue(forKey: "__line")?.integer
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
        let along: Axis? = switch kind {
        case .row: .horizontal
        case .column, .panel, .pane, .scroll, .list, .section, .form: .vertical
        default: nil
        }
        let aligned = fields["align"] == nil || fields["align"] == .string("stretch")
        let stretches = fields["grow"] == .bool(true) && aligned
        let fillsAcross = along == .vertical && aligned && kind != .list && kind != .section && kind != .form
        children = array.filter { $0 != .bool(false) }.map {
            Node($0, axis: along, stretched: stretches, across: fillsAcross)
        }
        problem = nil
        digest = Self.digest(kind: kind, props: fields, children: children, extra: "\(line ?? 0) \(String(describing: axis)) \(stretched) \(across)")
    }

    private init(invalid problem: String) {
        axis = nil
        stretched = false
        across = false
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
        case .text, .markdown, .badge, .label, .link, .labeled: string("text")
        case .share: string("label")
        case .button, .item, .toggle, .menu, .picker, .stepper, .disclosure: string("label")
        case .icon, .native, .view: string("name")
        case .terminal: string("id")
        case .missing: string("name")
        case .instance: string("component")
        case .browser: string("url")
        case .image: string("src")
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

    /// What in this tree draws as a placeholder here: a Moonframe element
    /// MoonSwift has no view for yet, a missing component, an instance.
    public var gaps: [String] {
        var found: [String] = []
        func walk(_ node: Node) {
            switch node.kind {
            case .missing: found.append("no component named \(node.text ?? "")")
            case .instance: found.append("component \(node.text ?? "") keeps state of its own, which MoonSwift can't run yet")
            case .map, .video, .paths, .revisionTimeline: found.append("ui.\(node.kind.rawValue) draws as a placeholder here")
            default: break
            }
            node.children.forEach(walk)
            for case .table(_, let fields) in node.props.values where fields["type"] != nil {
                walk(Node(.table(array: [], fields: fields)))
            }
        }
        walk(self)
        return Array(Set(found)).sorted()
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

    /// A function the view put in a prop, such as a list's `row`: its
    /// number, for `Workspace.part`.
    public func function(_ key: String) -> Int? {
        props[key]?["__function"]?.integer
    }

    /// Lazy rows, as Moonframe's lists have them: `count` rows, each drawn
    /// by `row(i)` only as it shows. At most 100,000, as in Moonframe.
    public static let maxRows = 100_000

    public var lazyRows: (count: Int, function: Int)? {
        guard let function = function("row") else { return nil }
        return (min(max(0, props["count"]?.integer ?? 0), Self.maxRows), function)
    }

    /// A whole number prop, held to `range`.
    public func integer(_ key: String, in range: ClosedRange<Int>) -> Int? {
        props[key]?.integer.map { min(max($0, range.lowerBound), range.upperBound) }
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
