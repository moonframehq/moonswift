import MoonKit
import SwiftUI

extension Stylesheet {
    /// A color from a stylesheet value: a name, `#rrggbb`, or either with an
    /// opacity percentage, as `accent/15`.
    func paint(_ value: String?, dark: Bool) -> Color? {
        guard let value else { return nil }
        guard let slash = value.firstIndex(of: "/") else {
            return Paints.color(color(value, dark: dark), name: value[...], percent: nil)
        }
        let name = value[..<slash]
        return Paints.color(color(String(name), dark: dark), name: name, percent: value[value.index(after: slash)...])
    }
}

extension Color {
    /// `#rgb`, `#rrggbb` or `#rrggbbaa`.
    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        var digits = String(hex.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 6 { digits += "ff" }
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double(value >> 24 & 0xFF) / 255,
            green: Double(value >> 16 & 0xFF) / 255,
            blue: Double(value >> 8 & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    /// The system's own colors by name, which follow light and dark.
    init?(system name: String) {
        switch name {
        case "primary", "foreground": self = .primary
        case "secondary", "muted-foreground": self = .secondary
        case "tint", "accent": self = .accentColor
        case "accent-foreground": self = .white
        case "red", "danger": self = .red
        case "orange", "warning": self = .orange
        case "success": self = .green
        case "yellow": self = .yellow
        case "green": self = .green
        case "mint": self = .mint
        case "teal": self = .teal
        case "cyan": self = .cyan
        case "blue": self = .blue
        case "indigo": self = .indigo
        case "purple": self = .purple
        case "pink": self = .pink
        case "brown": self = .brown
        case "gray": self = .gray
        case "white": self = .white
        case "black": self = .black
        case "clear": self = .clear
        // Moonframe's theme colors are the system's semantic ones here.
        case "list-hover": self = Color.accentColor.opacity(0.08)
        case "list-active": self = Color.accentColor.opacity(0.15)
        #if os(iOS)
        case "tertiary": self = Color(uiColor: .tertiaryLabel)
        case "background": self = Color(uiColor: .systemBackground)
        case "grouped", "sidebar": self = Color(uiColor: .systemGroupedBackground)
        case "fill", "muted": self = Color(uiColor: .secondarySystemFill)
        case "separator", "border": self = Color(uiColor: .separator)
        case "secondaryGrouped", "card": self = Color(uiColor: .secondarySystemGroupedBackground)
        #else
        case "tertiary": self = Color(nsColor: .tertiaryLabelColor)
        case "background", "grouped", "sidebar": self = Color(nsColor: .windowBackgroundColor)
        case "fill", "muted": self = Color(nsColor: .quaternaryLabelColor)
        case "separator", "border": self = Color(nsColor: .separatorColor)
        case "secondaryGrouped", "card": self = Color(nsColor: .controlBackgroundColor)
        #endif
        default: return nil
        }
    }
}

extension Font {
    /// A font from a rule: a text style that follows Dynamic Type, or a size.
    /// Nil leaves the font the element inherits.
    init?(_ style: StyleRule) {
        let weight = Font.Weight(name: style.weight)
        let design = Font.Design(name: style.design)
        if let size = style.size {
            self = .system(size: size, weight: weight ?? .regular, design: design ?? .default)
        } else if let textStyle = Font.TextStyle(name: style.font) {
            var font = Font.system(textStyle, design: design)
            if let weight { font = font.weight(weight) }
            self = font
        } else if weight != nil || design != nil {
            var font = Font.body
            if let design { font = .system(.body, design: design) }
            if let weight { font = font.weight(weight) }
            self = font
        } else {
            return nil
        }
    }
}

extension Font.TextStyle {
    init?(name: String?) {
        switch name {
        case "largeTitle": self = .largeTitle
        case "title": self = .title
        case "title2": self = .title2
        case "title3": self = .title3
        case "headline": self = .headline
        case "subheadline": self = .subheadline
        case "body": self = .body
        case "callout": self = .callout
        case "footnote": self = .footnote
        case "caption": self = .caption
        case "caption2": self = .caption2
        default: return nil
        }
    }
}

extension Font.Design {
    init?(name: String?) {
        switch name {
        case "monospaced", "mono": self = .monospaced
        case "rounded": self = .rounded
        case "serif": self = .serif
        default: return nil
        }
    }
}

extension Font.Weight {
    init?(name: String?) {
        switch name {
        case "ultralight": self = .ultraLight
        case "thin": self = .thin
        case "light": self = .light
        case "regular": self = .regular
        case "medium": self = .medium
        case "semibold": self = .semibold
        case "bold": self = .bold
        case "heavy": self = .heavy
        case "black": self = .black
        default: return nil
        }
    }
}

extension EdgeInsets {
    init(_ edges: Edges?) {
        self.init(
            top: edges?.top ?? 0, leading: edges?.leading ?? 0,
            bottom: edges?.bottom ?? 0, trailing: edges?.trailing ?? 0
        )
    }
}

extension Node {
    /// `gap`: one of Moonframe's space tokens, or points. `normal` by default.
    var spacing: CGFloat {
        if let points = number("gap") { return points }
        return CGFloat(string("gap").flatMap(Edges.space) ?? 8)
    }

    /// `grow = true` takes the free space along the parent's axis, as in
    /// Moonframe, and across it too where a growing parent stretches it, or
    /// both ways at a root; `"x"` or `"y"` pick one here.
    var growsWide: Bool { (flag("grow") && (axis != .vertical || stretched)) || string("grow") == "x" }
    var growsTall: Bool { (flag("grow") && (axis != .horizontal || stretched)) || string("grow") == "y" }

    var horizontalAlignment: HorizontalAlignment {
        switch string("align") {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    var verticalAlignment: VerticalAlignment {
        switch string("align") {
        case "start": .top
        case "end": .bottom
        case "baseline": .firstTextBaseline
        default: .center
        }
    }
}
