import MoonKit
import SwiftUI

extension Stylesheet {
    /// A color from a stylesheet value: a name, `#rrggbb`, or either with an
    /// opacity percentage, as `accent/15`.
    func paint(_ value: String?, dark: Bool) -> Color? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard let name = parts.first, let color = Color(hex: color(name, dark: dark)) else { return nil }
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

extension Font.Weight {
    init?(name: String?) {
        switch name {
        case "light": self = .light
        case "regular": self = .regular
        case "medium": self = .medium
        case "semibold": self = .semibold
        case "bold": self = .bold
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
