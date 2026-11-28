import MoonKit
import SwiftUI

/// A row or column of up to five children as fixed views, not a `ForEach`:
/// what hand-written SwiftUI is. A `ForEach`, a branch, or a stack made
/// through `Layout` makes each child an item SwiftUI tracks on its own,
/// with its own graph and transition, built while the row is measured, on
/// every row that scrolls in. Spacers are part of the type, as a stack
/// sees a spacer only when nothing decides between it and another view:
/// the pattern of spacers picks the case, outside the stack. Each case is
/// erased on its own: as one `@ViewBuilder` switch, the first row drawn
/// would make SwiftUI set up all 31 stack types, not the one it shows.
///
/// The children's identity is their place, as in a `ForEach` of unkeyed
/// children, but a change of count or of where the spacers are draws the
/// stack anew. So only stacks whose children keep no state of their own
/// (`Fixed.fits`) take this way.
protocol FixedStack: View {
    var children: [Node] { get }
    var scope: Scope { get }
}

extension FixedStack {
    /// Bit `i` set when child `i` is a spacer.
    var spacers: Int {
        children.indices.reduce(0) { $0 | (children[$1].kind == .spacer ? 1 << $1 : 0) }
    }

    func n(_ index: Int) -> _UnaryViewAdaptor<EquatableView<NodeView>> {
        _UnaryViewAdaptor(NodeView(node: children[index], scope: scope.child(String(index))).equatable())
    }

    func s(_ index: Int) -> Spacer {
        Spacer(minLength: children[index].number("min").map { CGFloat($0) } ?? 0)
    }
}

struct FixedRow: FixedStack {
    let alignment: VerticalAlignment
    let spacing: CGFloat
    let children: [Node]
    let scope: Scope

    var body: AnyView {
        let spacers = spacers
        switch children.count {
        case 1: return one(spacers)
        case 2: return two(spacers)
        case 3: return three(spacers)
        case 4: return four(spacers)
        default: return five(spacers)
        }
    }

    private func one(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0) })
        default: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0) })
        }
    }

    private func two(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1) })
        case 1: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1) })
        case 2: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1) })
        default: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1) })
        }
    }

    private func three(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2) })
        case 1: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2) })
        case 2: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2) })
        case 3: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2) })
        case 4: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2) })
        case 5: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2) })
        case 6: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2) })
        default: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2) })
        }
    }

    private func four(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); n(3) })
        case 1: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); n(3) })
        case 2: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); n(3) })
        case 3: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); n(3) })
        case 4: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); n(3) })
        case 5: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); n(3) })
        case 6: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); n(3) })
        case 7: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); n(3) })
        case 8: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); s(3) })
        case 9: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); s(3) })
        case 10: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); s(3) })
        case 11: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); s(3) })
        case 12: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); s(3) })
        case 13: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); s(3) })
        case 14: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); s(3) })
        default: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); s(3) })
        }
    }

    private func five(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); n(3); n(4) })
        case 1: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); n(3); n(4) })
        case 2: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); n(3); n(4) })
        case 3: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); n(3); n(4) })
        case 4: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); n(3); n(4) })
        case 5: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); n(3); n(4) })
        case 6: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); n(3); n(4) })
        case 7: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); n(3); n(4) })
        case 8: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); s(3); n(4) })
        case 9: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); s(3); n(4) })
        case 10: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); s(3); n(4) })
        case 11: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); s(3); n(4) })
        case 12: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); s(3); n(4) })
        case 13: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); s(3); n(4) })
        case 14: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); s(3); n(4) })
        case 15: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); s(3); n(4) })
        case 16: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); n(3); s(4) })
        case 17: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); n(3); s(4) })
        case 18: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); n(3); s(4) })
        case 19: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); n(3); s(4) })
        case 20: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); n(3); s(4) })
        case 21: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); n(3); s(4) })
        case 22: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); n(3); s(4) })
        case 23: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); n(3); s(4) })
        case 24: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); s(3); s(4) })
        case 25: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); s(3); s(4) })
        case 26: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); s(3); s(4) })
        case 27: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); s(3); s(4) })
        case 28: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); s(3); s(4) })
        case 29: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); s(3); s(4) })
        case 30: AnyView(HStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); s(3); s(4) })
        default: AnyView(HStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); s(3); s(4) })
        }
    }
}

struct FixedColumn: FixedStack {
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let children: [Node]
    let scope: Scope

    var body: AnyView {
        let spacers = spacers
        switch children.count {
        case 1: return one(spacers)
        case 2: return two(spacers)
        case 3: return three(spacers)
        case 4: return four(spacers)
        default: return five(spacers)
        }
    }

    private func one(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0) })
        default: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0) })
        }
    }

    private func two(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1) })
        case 1: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1) })
        case 2: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1) })
        default: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1) })
        }
    }

    private func three(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2) })
        case 1: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2) })
        case 2: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2) })
        case 3: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2) })
        case 4: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2) })
        case 5: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2) })
        case 6: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2) })
        default: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2) })
        }
    }

    private func four(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); n(3) })
        case 1: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); n(3) })
        case 2: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); n(3) })
        case 3: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); n(3) })
        case 4: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); n(3) })
        case 5: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); n(3) })
        case 6: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); n(3) })
        case 7: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); n(3) })
        case 8: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); s(3) })
        case 9: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); s(3) })
        case 10: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); s(3) })
        case 11: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); s(3) })
        case 12: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); s(3) })
        case 13: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); s(3) })
        case 14: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); s(3) })
        default: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); s(3) })
        }
    }

    private func five(_ spacers: Int) -> AnyView {
        switch spacers {
        case 0: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); n(3); n(4) })
        case 1: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); n(3); n(4) })
        case 2: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); n(3); n(4) })
        case 3: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); n(3); n(4) })
        case 4: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); n(3); n(4) })
        case 5: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); n(3); n(4) })
        case 6: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); n(3); n(4) })
        case 7: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); n(3); n(4) })
        case 8: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); s(3); n(4) })
        case 9: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); s(3); n(4) })
        case 10: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); s(3); n(4) })
        case 11: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); s(3); n(4) })
        case 12: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); s(3); n(4) })
        case 13: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); s(3); n(4) })
        case 14: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); s(3); n(4) })
        case 15: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); s(3); n(4) })
        case 16: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); n(3); s(4) })
        case 17: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); n(3); s(4) })
        case 18: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); n(3); s(4) })
        case 19: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); n(3); s(4) })
        case 20: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); n(3); s(4) })
        case 21: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); n(3); s(4) })
        case 22: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); n(3); s(4) })
        case 23: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); n(3); s(4) })
        case 24: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); n(2); s(3); s(4) })
        case 25: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); n(2); s(3); s(4) })
        case 26: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); n(2); s(3); s(4) })
        case 27: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); n(2); s(3); s(4) })
        case 28: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); n(1); s(2); s(3); s(4) })
        case 29: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); n(1); s(2); s(3); s(4) })
        case 30: AnyView(VStack(alignment: alignment, spacing: spacing) { n(0); s(1); s(2); s(3); s(4) })
        default: AnyView(VStack(alignment: alignment, spacing: spacing) { s(0); s(1); s(2); s(3); s(4) })
        }
    }
}

/// Which stacks `FixedRow` and `FixedColumn` can draw.
enum Fixed {
    /// Whether `node`'s children can be fixed: five or fewer, placed by
    /// position, with nothing under them that a fresh draw would lose.
    static func fits(_ node: Node) -> Bool {
        let children = node.children
        // `justify` shares the space out with spacers of its own.
        // A flow wraps, and a floated child sits over the stack, not in it.
        guard (1...5).contains(children.count), node.lazyRows == nil, node.props["justify"] == nil,
              node.props["wrap"] != .bool(true), !node.hasFloats else { return false }
        return children.allSatisfy { $0.props["key"] == nil && $0.props["id"] == nil && isStateless($0) }
    }

    /// What a fresh draw loses nothing of: no control's focus or text, no
    /// scroll position, fold, loaded image, native view or open sheet.
    /// Kinds not listed, new ones too, keep the `ForEach`.
    private static let stateless: Set<Node.Kind> = [
        .row, .column, .panel, .pane, .text, .markdown, .label, .labeled, .badge, .icon, .divider, .spacer, .link,
        .button, .progress, .unavailable, .item,
    ]
    private static let keepingProps = Decorations.screenKeys.union(Decorations.presentedKeys).union(["transition"])

    @MainActor private static var known: [Int: Bool] = [:]

    static func isStateless(_ node: Node) -> Bool {
        if let result = known[node.digest] { return result }
        let result = stateless.contains(node.kind) && !node.props.keys.contains(where: keepingProps.contains)
            && node.children.allSatisfy(isStateless)
        if known.count > 50_000 { known.removeAll() }
        known[node.digest] = result
        return result
    }
}
