import MoonKit
import SwiftUI

/// An element's style, resolved once into what SwiftUI draws: fonts and
/// colors made, edges as insets, and which parts of a box it can ever use.
///
/// `uses` comes from every rule that could apply to the element, its
/// `:hover` and `:selected` ones too, so the views around it keep one
/// structure as the pointer comes and goes; only values change.
struct Look {
    struct Uses: OptionSet {
        let rawValue: Int
        static let padding = Uses(rawValue: 1 << 0)
        static let size = Uses(rawValue: 1 << 1)
        static let stretch = Uses(rawValue: 1 << 2)
        static let fill = Uses(rawValue: 1 << 3)
        static let glass = Uses(rawValue: 1 << 4)
        static let shadow = Uses(rawValue: 1 << 5)
        static let opacity = Uses(rawValue: 1 << 6)
        static let rotate = Uses(rawValue: 1 << 7)
        static let fixed = Uses(rawValue: 1 << 8)
        static let margin = Uses(rawValue: 1 << 9)
        static let floats = Uses(rawValue: 1 << 10)
    }

    var uses: Uses = []
    var style = StyleRule()
    var font: Font?
    var color: Color?
    var background: Color?
    var border: Color?
    /// `all`, `top`, `bottom`, `left` or `right` when a border is drawn.
    var edges: String?
    var borderWidth: CGFloat = 1
    var radius: CGFloat = 0
    var padding = EdgeInsets()
    var margin = EdgeInsets()
    var width: CGFloat?
    var height: CGFloat?
    var wide = false
    var tall = false
    /// The stretch frame's limits: infinite to grow, a `max_width` or
    /// `max_height` to cap, nil to keep its own size.
    var maxWidth: CGFloat?
    var maxHeight: CGFloat?
    /// Its children with `float`, drawn over its box (`Floats`).
    var floats: AnyView?
    var alignment = Alignment.topLeading
    var shadow: CGFloat = 0
    var opacity: Double = 1
    var rotate: Double = 0
    var fixed: (horizontal: Bool, vertical: Bool) = (false, false)
    /// Whether a `:hover` rule could change it.
    var hovers = false

    init(node: Node, sheet: Stylesheet, dark: Bool, hovered: Bool) {
        let style = sheet.resolve(node, hovered: hovered)
        self.style = style
        font = Fonts.font(style)
        color = sheet.paint(style.color, dark: dark)
        background = sheet.paint(style.background, dark: dark)
        if let edges = style.edges, edges != "none" {
            self.edges = edges
            border = sheet.paint(style.border ?? "border", dark: dark)
        }
        borderWidth = style.borderWidth ?? 1
        radius = style.radius ?? 0
        padding = EdgeInsets(style.padding)
        margin = EdgeInsets(style.margin)
        width = node.number("width").map { CGFloat($0) }
        height = node.number("height").map { CGFloat($0) }
        let selfAlign = Self.selfAlign(of: node)
        wide = node.growsWide || node.kind == .panel || selfAlign != nil
        tall = node.growsTall
        let capWidth = node.number("max_width").map { CGFloat($0) }, capHeight = node.number("max_height").map { CGFloat($0) }
        maxWidth = wide ? capWidth ?? .infinity : capWidth
        maxHeight = tall ? capHeight ?? .infinity : capHeight
        alignment = selfAlign ?? Self.alignment(of: node)
        shadow = style.shadow ?? 0
        opacity = style.opacity ?? 1
        rotate = node.number("rotate") ?? 0
        switch node.props["fixed"] {
        case .string("y")?: fixed = (false, true)
        case .string("x")?: fixed = (true, false)
        case .bool(true)?: fixed = (true, true)
        default:
            // Moonframe's `shrink = false`: its own size along its parent's axis.
            if node.props["shrink"] == .bool(false) {
                fixed = (node.axis != .vertical, node.axis != .horizontal)
            }
        }

        let selectors = Stylesheet.selectors(of: node)
        hovers = sheet.hovers(selectors)
        // Everything any state could set, for the structure.
        var states = [style]
        if hovers { states.append(sheet.resolve(node, hovered: true)) }
        for selector in selectors {
            let selected = sheet.resolve(selector: "\(selector):selected")
            if selected != StyleRule() { states.append(selected) }
        }
        if states.contains(where: { $0.padding != nil }) { uses.insert(.padding) }
        if width != nil || height != nil { uses.insert(.size) }
        if maxWidth != nil || maxHeight != nil { uses.insert(.stretch) }
        if states.contains(where: { $0.background != nil || ($0.edges != nil && $0.edges != "none") }) { uses.insert(.fill) }
        // A Moonframe column stretches its containers across its width.
        // Only one that draws a box, or places its content in it, shows
        // the difference; the rest keep their own width, as a frame on
        // every row of a list costs SwiftUI a layout pass each.
        if !wide, Self.stretched(node), uses.contains(.fill) || node.props["justify"] != nil {
            wide = true
            maxWidth = capWidth ?? .infinity
            uses.insert(.stretch)
        }
        if states.contains(where: { $0.glass == true }) { uses.insert(.glass) }
        if states.contains(where: { $0.shadow != nil }) { uses.insert(.shadow) }
        if states.contains(where: { $0.opacity != nil }) { uses.insert(.opacity) }
        if node.props["rotate"] != nil { uses.insert(.rotate) }
        if fixed != (false, false) { uses.insert(.fixed) }
        if states.contains(where: { $0.margin != nil }) { uses.insert(.margin) }
    }

    /// Where the content sits in a box bigger than it: by the column's or
    /// row's `align` and `justify`, from the top leading corner otherwise.
    private static func alignment(of node: Node) -> Alignment {
        let justify = node.string("justify")
        switch node.kind {
        case .column:
            return Alignment(horizontal: node.horizontalAlignment, vertical: justify == "end" ? .bottom : justify == "center" ? .center : .top)
        case .row:
            return Alignment(horizontal: justify == "end" ? .trailing : justify == "center" ? .center : .leading, vertical: node.verticalAlignment)
        default: return .topLeading
        }
    }

    /// Moonframe's `self_align` in a column: where it sits across the
    /// width, in a box as wide as the column.
    private static func selfAlign(of node: Node) -> Alignment? {
        guard node.axis == .vertical, let align = node.string("self_align"), align != "stretch" else { return nil }
        return align == "end" ? .trailing : align == "center" ? .center : .leading
    }

    /// Whether a Moonframe column stretches it across its width: its
    /// containers do, unless they `hug`; a text or a button keeps its own.
    private static func stretched(_ node: Node) -> Bool {
        node.across && stretchable.contains(node.kind) && !node.flag("hug") && node.props["self_align"] == nil
    }

    private static let stretchable: Set<Node.Kind> = [.row, .column, .panel, .pane, .item, .input, .markdown, .list]
}

/// Fonts by what makes them, so equal styles share one font: SwiftUI then
/// compares them by identity and reuses what it resolved for text.
enum Fonts {
    private struct Key: Hashable {
        let size: Double?, weight: String?, font: String?, design: String?
    }

    @MainActor private static var made: [Key: Font?] = [:]

    @MainActor static func font(_ style: StyleRule) -> Font? {
        let key = Key(size: style.size, weight: style.weight, font: style.font, design: style.design)
        if let font = made[key] { return font }
        let font = Font(style)
        // Sizes a mod computes could grow it without end.
        if made.count > 500 { made.removeAll() }
        made[key] = font
        return font
    }
}

/// Colors by what makes them, made once: a hex parsed and boxed on each
/// draw is a new color to SwiftUI every time.
@MainActor
enum Paints {
    private struct Key: Hashable {
        /// What the stylesheet made of the name: a hex, or the name again.
        let color: String
        let name: Substring
        let percent: Substring?
    }

    private static var made: [Key: Color?] = [:]

    static func color(_ color: String, name: Substring, percent: Substring?) -> Color? {
        let key = Key(color: color, name: name, percent: percent)
        if let made = made[key] { return made }
        var made = Color(hex: color) ?? Color(system: String(name))
        if let percent, let value = Double(percent) { made = made?.opacity(value / 100) }
        // Colors a mod computes could grow it without end.
        if Self.made.count > 2000 { Self.made.removeAll() }
        Self.made[key] = made
        return made
    }
}

/// The box rules draw: padding, size, colors, corners, glass and shadow.
/// Each wrapper is there only if the element can use it, so a plain text
/// costs SwiftUI no layout of its own.
struct Box: ViewModifier {
    let look: Look

    func body(content: Content) -> some View {
        if look.uses.isEmpty {
            if let color = look.color { content.foregroundStyle(color) } else { content }
        } else {
            box(content)
        }
    }

    private func box(_ content: Content) -> some View {
        let uses = look.uses
        return content
            .modifier(Pad(on: uses.contains(.padding), insets: look.padding))
            .modifier(Size(on: uses.contains(.size), width: look.width, height: look.height, alignment: look.alignment))
            .modifier(Stretch(
                on: uses.contains(.stretch), maxWidth: look.maxWidth, maxHeight: look.maxHeight, alignment: look.alignment
            ))
            .modifier(Ink(color: look.color))
            .modifier(Fill(on: uses.contains(.fill), look: look))
            .modifier(Effects(look: look))
            .modifier(Floating(view: uses.contains(.floats) ? look.floats : nil))
            .modifier(Pad(on: uses.contains(.margin), insets: look.margin))
    }
}

/// Children with `float`, over the box rather than in it.
private struct Floating: ViewModifier {
    let view: AnyView?

    func body(content: Content) -> some View {
        if let view { content.overlay { view } } else { content }
    }
}

private struct Pad: ViewModifier {
    let on: Bool
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        if on { content.padding(insets) } else { content }
    }
}

private struct Size: ViewModifier {
    let on: Bool
    let width: CGFloat?
    let height: CGFloat?
    let alignment: Alignment

    func body(content: Content) -> some View {
        if on { content.frame(width: width, height: height, alignment: alignment) } else { content }
    }
}

private struct Stretch: ViewModifier {
    let on: Bool
    let maxWidth: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    func body(content: Content) -> some View {
        if on {
            content.frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
        } else {
            content
        }
    }
}

/// A color only when one is set: otherwise the system's own styling stays,
/// as a labeled row's secondary value.
struct Ink: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

private struct Fill: ViewModifier {
    let on: Bool
    let look: Look

    func body(content: Content) -> some View {
        if on {
            let shape = RoundedRectangle(cornerRadius: look.radius, style: .continuous)
            content
                .background {
                    if let background = look.background { shape.fill(background) }
                }
                .overlay(alignment: edgeAlignment) {
                    if let border = look.border {
                        switch look.edges {
                        case "top", "bottom": border.frame(height: look.borderWidth)
                        case "left", "right": border.frame(width: look.borderWidth)
                        default: shape.strokeBorder(border, lineWidth: look.borderWidth)
                        }
                    }
                }
        } else {
            content
        }
    }
}

extension Fill {
    /// Where a one-edge border goes.
    fileprivate var edgeAlignment: Alignment {
        switch look.edges {
        case "top": .top
        case "bottom": .bottom
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }
}

/// Glass, shadow, opacity, rotation and fixed size: rare, so behind one test.
private struct Effects: ViewModifier {
    let look: Look

    private static let rare: Look.Uses = [.glass, .shadow, .opacity, .rotate, .fixed]

    func body(content: Content) -> some View {
        if look.uses.isDisjoint(with: Self.rare) {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: look.radius, style: .continuous)
            content
                .modifier(Glass(on: look.style.glass ?? false, shape: shape))
                .shadow(color: .black.opacity(look.uses.contains(.shadow) ? 0.18 : 0), radius: look.shadow, y: look.shadow / 3)
                .opacity(look.opacity)
                .rotationEffect(.degrees(look.rotate))
                .fixedSize(horizontal: look.fixed.horizontal, vertical: look.fixed.vertical)
        }
    }
}

private struct Glass<S: Shape>: ViewModifier {
    let on: Bool
    let shape: S

    func body(content: Content) -> some View {
        if on {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}
