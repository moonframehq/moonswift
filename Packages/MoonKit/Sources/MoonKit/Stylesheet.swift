/// Edge sizes, from `4`, `{ y, x }`, `{ top, right, bottom, left }` or named
/// edges such as `{ x = 14, top = 10 }`.
public struct Edges: Equatable, Sendable {
    public var top = 0.0, leading = 0.0, bottom = 0.0, trailing = 0.0

    public init?(_ value: LuauValue?) {
        switch value {
        case .number(let all): (top, leading, bottom, trailing) = (all, all, all, all)
        case .table(let array, let fields):
            let list = array.compactMap(\.number)
            if list.count == 2 {
                (top, trailing, bottom, leading) = (list[0], list[1], list[0], list[1])
            } else if list.count == 4 {
                (top, trailing, bottom, leading) = (list[0], list[1], list[2], list[3])
            }
            let x = fields["x"]?.number, y = fields["y"]?.number
            top = fields["top"]?.number ?? y ?? top
            bottom = fields["bottom"]?.number ?? y ?? bottom
            leading = fields["left"]?.number ?? x ?? leading
            trailing = fields["right"]?.number ?? x ?? trailing
        default: return nil
        }
    }
}

/// What a rule sets. Unset stays nil, so rules merge property by property.
public struct StyleRule: Equatable, Sendable {
    public var background: String?
    public var color: String?
    public var border: String?
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
    /// Liquid Glass behind the element.
    public var glass: Bool?

    public init() {}

    init(_ value: LuauValue?) {
        background = value?["background"]?.string
        color = value?["color"]?.string
        border = value?["border"]?.string
        borderWidth = value?["borderWidth"]?.number
        radius = value?["radius"]?.number
        size = value?["size"]?.number
        weight = value?["weight"]?.string
        font = value?["font"]?.string
        design = value?["design"]?.string
        opacity = value?["opacity"]?.number
        shadow = value?["shadow"]?.number
        padding = Edges(value?["padding"])
        margin = Edges(value?["margin"])
        glass = value?["glass"]?.bool
    }

    mutating func merge(_ other: StyleRule) {
        background = other.background ?? background
        color = other.color ?? color
        border = other.border ?? border
        borderWidth = other.borderWidth ?? borderWidth
        radius = other.radius ?? radius
        size = other.size ?? size
        weight = other.weight ?? weight
        font = other.font ?? font
        design = other.design ?? design
        opacity = other.opacity ?? opacity
        shadow = other.shadow ?? shadow
        padding = other.padding ?? padding
        margin = other.margin ?? margin
        glass = other.glass ?? glass
    }
}

/// `style.luau`: named colors and rules by element type or class, with
/// `:hover` and `:selected` states.
public struct Stylesheet: Equatable, Sendable {
    private var light: [String: String] = [:]
    private var dark: [String: String] = [:]
    private var rules: [String: StyleRule] = [:]

    public init() {}

    init(_ value: LuauValue?) {
        if case .table(_, let colors)? = value?["colors"] {
            for (name, color) in colors {
                light[name] = color.string ?? color["light"]?.string
                dark[name] = color.string ?? color["dark"]?.string
            }
        }
        if case .table(_, let rules)? = value?["rules"] {
            self.rules = rules.mapValues { StyleRule($0) }
        }
    }

    /// The hex a color name stands for, or the text itself.
    public func color(_ name: String, dark isDark: Bool) -> String {
        (isDark ? dark : light)[name] ?? name
    }

    /// Whether any rule of these selectors reacts to the pointer.
    public func hovers(_ selectors: [String]) -> Bool {
        selectors.contains { rules["\($0):hover"] != nil }
    }

    /// The element's look: its type, then each class, then its own `style`.
    public func resolve(_ node: Node, hovered: Bool = false) -> StyleRule {
        var resolved = StyleRule()
        let selected = node.flag("selected")
        for selector in Self.selectors(of: node) {
            if let rule = rules[selector] { resolved.merge(rule) }
            if hovered, let rule = rules["\(selector):hover"] { resolved.merge(rule) }
            if selected, let rule = rules["\(selector):selected"] { resolved.merge(rule) }
        }
        // Style props on the element itself, then its `style` table.
        resolved.merge(StyleRule(.fields(node.props)))
        if let inline = node.props["style"] { resolved.merge(StyleRule(inline)) }
        return resolved
    }

    /// The look of a piece the host draws itself, such as a panel's title.
    public func resolve(selector: String) -> StyleRule {
        rules[selector] ?? StyleRule()
    }

    public static func selectors(of node: Node) -> [String] {
        [node.kind.rawValue] + (node.string("class")?.split(separator: " ").map(String.init) ?? [])
    }
}
