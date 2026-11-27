import MoonKit
import SwiftUI

extension Stylesheet {
    /// A color from a stylesheet value: a name, `#rrggbb`, or either with an
    /// opacity percentage, as `accent/15`.
    func paint(_ value: String?, dark: Bool) -> Color? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard let name = parts.first, let color = Color(hex: color(name, dark: dark)) ?? Color(system: name) else {
            return nil
        }
        guard parts.count == 2, let percent = Double(parts[1]) else { return color }
        return color.opacity(percent / 100)
    }
}

extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double(value >> 16 & 0xFF) / 255,
            green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    /// The system's own colors by name, which follow light and dark.
    init?(system name: String) {
        switch name {
        case "primary": self = .primary
        case "secondary": self = .secondary
        case "tint", "accent": self = .accentColor
        case "red": self = .red
        case "orange": self = .orange
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
        #if os(iOS)
        case "tertiary": self = Color(uiColor: .tertiaryLabel)
        case "background": self = Color(uiColor: .systemBackground)
        case "grouped": self = Color(uiColor: .systemGroupedBackground)
        case "fill": self = Color(uiColor: .secondarySystemFill)
        case "separator": self = Color(uiColor: .separator)
        #else
        case "tertiary": self = Color(nsColor: .tertiaryLabelColor)
        case "background", "grouped": self = Color(nsColor: .windowBackgroundColor)
        case "fill": self = Color(nsColor: .quaternaryLabelColor)
        case "separator": self = Color(nsColor: .separatorColor)
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
    /// `gap`: a name or points.
    var spacing: CGFloat {
        if let points = number("gap") { return points }
        switch string("gap") {
        case "none": return 0
        case "small": return 6
        case "large": return 20
        default: return 12
        }
    }

    /// `grow`: true for both ways, or "x" or "y" for one.
    var growsWide: Bool { flag("grow") || string("grow") == "x" }
    var growsTall: Bool { flag("grow") || string("grow") == "y" }

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
        default: .center
        }
    }
}
