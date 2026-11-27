import MoonKit
import SwiftUI

// Moonframe's layout keys that SwiftUI's stacks have no word for: a row that
// wraps, children floated over their parent, and the drawn elements its
// charts are made of.

/// `ui.row { wrap = true }`: children left to right, onto a new line when
/// the next doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if next > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].items.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].items.append(index)
        }
        return rows
    }
}

/// Its one child at the width offered, however wide the child would be: a
/// scrolled column stays as wide as the screen, and a desktop row wider
/// than a phone runs off its right edge instead of moving the whole page.
struct Clamped: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

extension Node {
    /// Whether any child floats over this one rather than taking a place.
    var hasFloats: Bool { children.contains { $0.props["float"] != nil } }
}

/// The children of `node` with `float`, each placed over it: at an edge or
/// corner (`"top-right"`, `"fill"`), `{ at = ..., inset = n }`, or by pixel
/// offsets from its edges (`{ top = -4, right = -4 }`, negative overhangs).
struct Floats: View {
    let node: Node
    let scope: Scope

    var body: some View {
        ZStack {
            ForEach(Identified.of(node.children).filter { $0.node.props["float"] != nil }) { child in
                let place = Place(child.node.props["float"])
                NodeView(node: child.node, scope: scope.child(child.id)).equatable()
                    .padding(place.insets)
                    .offset(x: place.offset.width, y: place.offset.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: place.alignment)
            }
        }
    }

    private struct Place {
        var alignment = Alignment.topLeading
        var insets = EdgeInsets()
        var offset = CGSize.zero

        init(_ value: LuauValue?) {
            switch value {
            case .string(let at)?: alignment = Self.alignment(at)
            case .table(_, let fields)? where fields["at"] != nil:
                alignment = Self.alignment(fields["at"]?.string ?? "top-left")
                let inset = fields["inset"]?.number ?? 0
                insets = EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
            case .table(_, let fields)?:
                let top = fields["top"]?.number, bottom = fields["bottom"]?.number
                let left = fields["left"]?.number, right = fields["right"]?.number
                let vertical: VerticalAlignment = top != nil ? .top : bottom != nil ? .bottom : .center
                let horizontal: HorizontalAlignment = left != nil ? .leading : right != nil ? .trailing : .center
                alignment = Alignment(horizontal: horizontal, vertical: vertical)
                offset = CGSize(width: left ?? -(right ?? 0), height: top ?? -(bottom ?? 0))
            default: break
            }
        }

        private static func alignment(_ at: String) -> Alignment {
            switch at {
            case "top-right": .topTrailing
            case "bottom-left": .bottomLeading
            case "bottom-right": .bottomTrailing
            case "top": .top
            case "bottom": .bottom
            case "left": .leading
            case "right": .trailing
            case "fill": .center
            default: .topLeading
            }
        }
    }
}

/// `ui.line { points = { 3, 5, 2, 8 } }`: a line through values spread
/// evenly across its box, in the text's color; `area` fills under it.
struct LineNode: View {
    let node: Node

    var body: some View {
        let values = (node.props["points"]?.array ?? []).compactMap(\.number)
        let low = node.number("min") ?? values.min() ?? 0
        let high = node.number("max") ?? values.max() ?? 1
        let span = high - low == 0 ? 1 : high - low
        GeometryReader { box in
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: values.count < 2 ? 0 : box.size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: box.size.height * (1 - CGFloat((value - low) / span))
                )
            }
            ZStack {
                if node.flag("area"), let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: box.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: box.size.height))
                    }
                    .fill(.foreground.opacity(0.15))
                }
                Path { path in path.addLines(points) }
                    .stroke(.foreground, style: StrokeStyle(
                        lineWidth: node.number("stroke").map { CGFloat($0) } ?? 1.5, lineCap: .round, lineJoin: .round,
                        dash: node.flag("dashed") ? [4, 3] : []
                    ))
                if node.string("dots") != nil {
                    ForEach(Array((node.string("dots") == "all" ? points : points.suffix(1)).enumerated()), id: \.offset) { _, point in
                        Circle().fill(.foreground).frame(width: 5, height: 5).position(point)
                    }
                }
            }
        }
    }
}

/// `ui.hatch { width = 40, height = 12 }`: diagonal stripes in the text's
/// color, for what is held back or still missing.
struct HatchNode: View {
    let node: Node

    var body: some View {
        let gap = node.number("gap").map { CGFloat($0) } ?? 6
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += gap
            }
            context.stroke(path, with: .foreground, lineWidth: 1)
        }
        .opacity(0.5)
    }
}
