/// Edge sizes, from a space token, `4`, `{ y, x }`, `{ top, right, bottom,
/// left }` or named edges such as `{ x = 14, top = 10 }`.
public struct Edges: Equatable, Sendable {
    public var top = 0.0, leading = 0.0, bottom = 0.0, trailing = 0.0

    public init?(_ value: LuauValue?) {
        switch value {
        case .number(let all): (top, leading, bottom, trailing) = (all, all, all, all)
        case .string(let token):
            guard let all = Self.space(token) else { return nil }
            (top, leading, bottom, trailing) = (all, all, all, all)
        case .table(let array, let fields):
            let list = array.compactMap(Self.points)
            if list.count == 2 {
                (top, trailing, bottom, leading) = (list[0], list[1], list[0], list[1])
            } else if list.count == 4 {
                (top, trailing, bottom, leading) = (list[0], list[1], list[2], list[3])
            }
            let x = fields["x"].flatMap(Self.points), y = fields["y"].flatMap(Self.points)
            top = fields["top"].flatMap(Self.points) ?? y ?? top
            bottom = fields["bottom"].flatMap(Self.points) ?? y ?? bottom
            leading = fields["left"].flatMap(Self.points) ?? x ?? leading
            trailing = fields["right"].flatMap(Self.points) ?? x ?? trailing
        default: return nil
        }
    }

    /// Moonframe's space tokens, in points.
    public static func space(_ token: String) -> Double? {
        switch token {
        case "none": 0
        case "small": 4
        case "normal": 8
        case "large": 16
        default: nil
        }
    }

    static func points(_ value: LuauValue) -> Double? {
        value.number ?? value.string.flatMap(space)
    }
}

/// What a rule sets. Unset stays nil, so rules merge property by property.
public struct StyleRule: Equatable, Sendable {
    public var background: String?
    public var color: String?
    /// The color of the edges `edges` draws.
    public var border: String?
    /// `all`, `top`, `bottom`, `left`, `right` or `none`.
    public var edges: String?
    public var borderWidth: Double?
    public var radius: Double?
    public var size: Double?
    public var weight: String?
    /// A text style, as `headline` or `caption`, which follows Dynamic Type.
    public var font: String?
    /// `monospaced`, `rounded` or `serif`.
    public var design: String?
    public var opacity: Double?
    public var shadow: Double?
    public var padding: Edges?
    public var margin: Edges?
    /// Space between a stack's children: a token or points.
    public var gap: Double?
    /// Liquid Glass behind the element.
    public var glass: Bool?

    public init() {}

    /// `sized` is false for an element's own keys where `size` means
    /// something else, as a button's control size.
    init(_ value: LuauValue?, sized: Bool = true) {
        guard case .table(_, let fields)? = value else { return }
        background = fields["background"]?.string ?? fields["surface"]?.string.map(Self.surface)
        color = fields["color"]?.string ?? fields["tone"]?.string.flatMap(Self.tone)
        switch fields["border"] {
        case .bool(let on)?: edges = on ? "all" : "none"
        case .string(let text)? where ["all", "top", "bottom", "left", "right", "none"].contains(text): edges = text
        // A color, as MoonSwift's stylesheets wrote it before.
        case .string(let text)?: (border, edges) = (text, "all")
        default: break
        }
        border = fields["border_color"]?.string ?? fields["borderColor"]?.string ?? border
        borderWidth = fields["borderWidth"]?.number ?? fields["border_width"]?.number
        radius = fields["radius"]?.number ?? fields["radius"]?.array?.first?.number
        switch sized ? fields["size"] : nil {
        case .number(let points)?: size = points
        case .string(let token)?: font = Self.textStyle(token)
        default: break
        }
        weight = fields["weight"]?.string.map { $0 == "normal" ? "regular" : $0 }
        switch fields["font"]?.string {
        case "mono"?: design = "monospaced"
        case "sans"?: break
        case let style?: font = style
        default: break
        }
        design = fields["design"]?.string ?? design
        opacity = fields["opacity"]?.number
        switch fields["shadow"] {
        case .number(let radius)?: shadow = radius
        case .string("none")?: shadow = 0
        case .string("small")?: shadow = 2
        case .string("large")?: shadow = 14
        case .string?, .table?: shadow = 6
        default: break
        }
        padding = Edges(fields["padding"])
        margin = Edges(fields["margin"])
        gap = fields["gap"].flatMap(Edges.points)
        glass = fields["glass"]?.bool
    }

    /// Moonframe's tones as colors.
    static func tone(_ tone: String) -> String? {
        switch tone {
        case "muted": "muted-foreground"
        case "accent": "accent"
        case "success": "success"
        case "warning": "warning"
        case "danger": "danger"
        default: nil
        }
    }

    /// Moonframe's surfaces as colors.
    static func surface(_ surface: String) -> String {
        surface == "secondary" ? "card" : surface
    }

    /// Moonframe's text sizes (0.85, 1, 1.15, 1.5, 1.75, 2.25 and 3 times
    /// a 14 px base) as the Dynamic Type styles nearest them, so a desktop
    /// component's fixed widths still hold its text.
    static func textStyle(_ token: String) -> String? {
        switch token {
        case "small": "caption"
        case "normal": "subheadline"
        case "large": "body"
        case "title": "title3"
        case "headline": "title2"
        case "display": "title"
        case "hero": "largeTitle"
        default: nil
        }
    }

    mutating func merge(_ other: StyleRule) {
        background = other.background ?? background
        color = other.color ?? color
        border = other.border ?? border
        edges = other.edges ?? edges
        borderWidth = other.borderWidth ?? borderWidth
        radius = other.radius ?? radius
        // A size in points and a text style replace each other.
        if other.size != nil || other.font != nil {
            size = other.size
            font = other.font
        }
        weight = other.weight ?? weight
        design = other.design ?? design
        opacity = other.opacity ?? opacity
        shadow = other.shadow ?? shadow
        padding = other.padding ?? padding
        margin = other.margin ?? margin
        gap = other.gap ?? gap
        glass = other.glass ?? glass
    }
}

/// `style.luau`, as in Moonframe: named colors, and rules for an element
/// type (`row`) or a class (`.hero`), each with a state after a colon:
/// `:hover`, `:selected`, `:disabled`, or one the view names with `state`.
public struct Stylesheet: Equatable, Sendable {
    private var light: [String: String] = [:]
    private var dark: [String: String] = [:]
    /// What `resolve` reads: the components' rules with the app's over them.
    private var rules: [String: StyleRule] = [:]
    /// The components' rules and the app's own, kept apart so a mod's
    /// `styles` can go between them.
    private var components: [String: StyleRule] = [:]
    private var own: [String: StyleRule] = [:]

    public init() {}

    /// `value` is `style.luau`'s table; `components` the rules the
    /// components a mod uses bring, under it.
    init(_ value: LuauValue?, components: [String: LuauValue] = [:]) {
        self.components = components.mapValues { StyleRule($0) }
        if case .table(_, let colors)? = value?["colors"] {
            for (name, color) in colors {
                light[name] = color.string ?? color["light"]?.string
                dark[name] = color.string ?? color["dark"]?.string
            }
        }
        if case .table(_, let rules)? = value?["rules"] {
            own = rules.mapValues { StyleRule($0) }
        }
        rules = self.components
        for (selector, rule) in own { rules[selector, default: StyleRule()].merge(rule) }
    }

    /// This sheet with a mod's own `styles` under it: for each selector, the
    /// mod's rule and then the sheet's over it, so the app can restyle any
    /// mod.
    public func with(styles: LuauValue?) -> Stylesheet {
        guard case .table(_, let own)? = styles, !own.isEmpty else { return self }
        var sheet = self
        for (selector, value) in own {
            var rule = components[selector] ?? StyleRule()
            rule.merge(StyleRule(value))
            if let app = self.own[selector] { rule.merge(app) }
            sheet.rules[selector] = rule
        }
        return sheet
    }

    /// The hex a color name stands for, or the text itself.
    public func color(_ name: String, dark isDark: Bool) -> String {
        (isDark ? dark : light)[name] ?? name
    }

    /// Whether any rule of these selectors reacts to the pointer.
    public func hovers(_ selectors: [String]) -> Bool {
        selectors.contains { rules["\($0):hover"] != nil }
    }

    /// The element's look: its type, then each class, each in its resting
    /// state then its states, then its `style`, then its own keys.
    public func resolve(_ node: Node, hovered: Bool = false) -> StyleRule {
        var resolved = StyleRule()
        let disabled = node.flag("disabled")
        let states = [
            hovered && !disabled ? "hover" : nil,
            node.flag("selected") ? "selected" : nil,
            disabled ? "disabled" : nil,
            node.string("state"),
        ].compactMap { $0 }
        for selector in Self.selectors(of: node) {
            if let rule = rules[selector] { resolved.merge(rule) }
            for state in states {
                if let rule = rules["\(selector):\(state)"] { resolved.merge(rule) }
            }
        }
        if let inline = node.props["style"] { resolved.merge(StyleRule(inline)) }
        resolved.merge(StyleRule(.fields(node.props), sized: Self.sized.contains(node.kind)))
        return resolved
    }

    /// Elements whose own `size` is their text's.
    private static let sized: Set<Node.Kind> = [.text, .badge, .icon, .label, .markdown, .link, .item]

    /// The look of a piece the host draws itself, such as a panel's header.
    public func resolve(selector: String) -> StyleRule {
        rules[selector] ?? StyleRule()
    }

    /// `row`, then `.a` and `.b` for `class = "a b"` or `{ "a", "b" }`.
    public static func selectors(of node: Node) -> [String] {
        let classes: [String] = switch node.props["class"] {
        case .string(let text)?: text.split(separator: " ").map(String.init)
        case .table(let list, _)?: list.compactMap(\.string)
        default: []
        }
        return [node.kind.rawValue] + classes.map { ".\($0)" }
    }
}
