import MoonKit
import SwiftUI

/// The elements a row is mostly made of, drawn in one step: a plain text,
/// a plain icon, and a fixed row or column with at most a gap, padding,
/// growth and a color. Each is one concrete view, chosen in Swift and
/// erased, with its font and color inside, as hand-written SwiftUI would
/// have it. A `@ViewBuilder` branch per element instead is one more thing
/// SwiftUI builds and tracks: a row of 25 elements pays for each as it
/// scrolls in.
extension NodeView {
    enum Fast {
        case text, icon, row, column
    }

    func fast(_ look: Look) -> Fast? {
        switch node.kind {
        case .text where look.uses.isEmpty && TextNode.isPlain(node): .text
        case .icon where look.uses.isEmpty && IconNode.isPlain(node): .icon
        case .row where Fixed.fits(node): .row
        case .column where Fixed.fits(node) && !node.flag("scroll"): .column
        default: nil
        }
    }

    func erased(_ kind: Fast, _ look: Look) -> AnyView {
        switch kind {
        case .text:
            let text = TextNode.plain(node).digits(node.flag("digits"))
            return AnyView(
                (look.color.map { text.foregroundStyle($0) } ?? text)
                    .font(look.font)
                    .lineLimit(TextNode.lines(node))
                    .accessibilityIdentifier(identifier)
            )
        case .icon:
            let image = IconNode.image(node).font(look.font)
            if let color = look.color { return AnyView(image.foregroundStyle(color)) }
            return AnyView(image)
        case .row:
            return boxed(FixedRow(alignment: node.verticalAlignment, spacing: node.spacing, children: node.children, scope: scope), look)
        case .column:
            let column = FixedColumn(alignment: node.horizontalAlignment, spacing: node.spacing, children: node.children, scope: scope)
            return boxed(column, look)
        }
    }

    /// Padding, growth and color, only those set.
    private func boxed(_ stack: some View, _ look: Look) -> AnyView {
        let padded = look.uses.contains(.padding), stretched = look.uses.contains(.stretch)
        let maxWidth: CGFloat? = look.wide ? .infinity : nil, maxHeight: CGFloat? = look.tall ? .infinity : nil
        switch (padded, stretched, look.color) {
        case (false, false, nil):
            return AnyView(stack)
        case (false, false, let color?):
            return AnyView(stack.foregroundStyle(color))
        case (true, false, nil):
            return AnyView(stack.padding(look.padding))
        case (true, false, let color?):
            return AnyView(stack.padding(look.padding).foregroundStyle(color))
        case (false, true, nil):
            return AnyView(stack.frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: look.alignment))
        case (false, true, let color?):
            return AnyView(stack.frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: look.alignment).foregroundStyle(color))
        case (true, true, nil):
            return AnyView(stack.padding(look.padding).frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: look.alignment))
        case (true, true, let color?):
            return AnyView(
                stack.padding(look.padding).frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: look.alignment)
                    .foregroundStyle(color)
            )
        }
    }
}
