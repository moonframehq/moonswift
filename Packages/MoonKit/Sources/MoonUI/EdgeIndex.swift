import MoonKit
import SwiftUI

/// `ui.list { edge = true, ui.section { edge = { letter = "R", dots = { "red", "green" } }, ... } }`:
/// an index on the list's trailing edge, as Sheprd's Home and PR tabs have
/// one. Each section with `edge` shows its letter (its `title`'s first, if
/// none), then a dot per row in the color `dots` gives it, so a list of two
/// sections still has a mark for every row. A touch or a drag along it
/// scrolls there. Dots past what fits are thinned evenly, each section
/// keeping at least one; letters always stay.
///
/// The system's index (`index` on a section) lists sections only.
struct EdgeIndexStrip: View {
    let parts: [EdgePart]
    let jump: (String) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme
    /// The entry under the finger, for the haptic as it changes.
    @State private var touched: String?

    private static let letterHeight: CGFloat = 15
    private static let dotHeight: CGFloat = 8
    private static let width: CGFloat = 18

    var body: some View {
        GeometryReader { space in
            let entries = EdgePart.entries(parts, capacity: capacity(height: space.size.height))
            VStack(spacing: 0) {
                ForEach(entries, id: \.target) { entry in
                    mark(entry)
                }
            }
            .frame(width: Self.width)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { touch($0.location.y, entries) }
                    .onEnded { _ in touched = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: Self.width)
        .sensoryFeedback(.selection, trigger: touched) { _, new in new != nil }
        // VoiceOver moves by the section headers instead, as with the
        // system index.
        .accessibilityHidden(true)
    }

    /// How many entries fit `height`: every letter, then dots in the rest.
    private func capacity(height: CGFloat) -> Int {
        let letters = CGFloat(parts.count)
        let dots = (height - letters * Self.letterHeight) / Self.dotHeight
        return parts.count + max(Int(dots), 0)
    }

    @ViewBuilder
    private func mark(_ entry: EdgePart.Entry) -> some View {
        if let letter = entry.letter {
            Text(verbatim: letter)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(height: Self.letterHeight)
        } else {
            Circle()
                .fill(workspace.stylesheet.paint(entry.color, dark: scheme == .dark) ?? .secondary)
                .frame(width: 5, height: 5)
                .frame(height: Self.dotHeight)
        }
    }

    /// Scrolls to the entry at `y` along the strip.
    private func touch(_ y: CGFloat, _ entries: [EdgePart.Entry]) {
        var top: CGFloat = 0
        for entry in entries {
            let height = entry.letter == nil ? Self.dotHeight : Self.letterHeight
            if y < top + height || entry == entries.last {
                guard touched != entry.target else { return }
                touched = entry.target
                jump(entry.target)
                return
            }
            top += height
        }
    }
}

/// A section as the edge index reads it.
struct EdgePart: Equatable {
    /// What a touch on its letter scrolls to: its header.
    let target: String
    let letter: String
    /// Its rows' anchors and colors, in order.
    let rows: [(id: String, color: String)]

    static func == (lhs: EdgePart, rhs: EdgePart) -> Bool {
        lhs.target == rhs.target && lhs.letter == rhs.letter
            && lhs.rows.map(\.id) == rhs.rows.map(\.id) && lhs.rows.map(\.color) == rhs.rows.map(\.color)
    }

    struct Entry: Hashable {
        let target: String
        /// A section's letter, or nil for a row's dot.
        let letter: String?
        let color: String?
    }

    /// The anchor a section's header scrolls by, and its `i`-th row's.
    static func anchor(_ scope: Scope) -> String { "edge:\(scope.path)" }
    static func anchor(_ scope: Scope, row: Int) -> String { "edge:\(scope.path)/\(row)" }

    /// The sections of `list` that ask for a place on its edge.
    static func parts(of list: Node, scope: Scope) -> [EdgePart] {
        Identified.of(list.children).compactMap { child in
            guard child.node.kind == .section, case .table(_, let edge)? = child.node.props["edge"] else { return nil }
            let section = scope.child(child.id)
            let letter = edge["letter"]?.string ?? child.node.string("title").flatMap { $0.first.map { String($0).uppercased() } } ?? "•"
            let count = child.node.lazyRows?.count ?? 0
            let dots = (edge["dots"]?.array ?? []).prefix(count).enumerated().map { index, color in
                (id: anchor(section, row: index + 1), color: color.string ?? "secondary")
            }
            return EdgePart(target: anchor(section), letter: letter, rows: dots)
        }
    }

    /// The entries for `parts`, at most `capacity` of them when the letters
    /// leave room for any dots at all.
    static func entries(_ parts: [EdgePart], capacity: Int) -> [Entry] {
        let rows = parts.reduce(0) { $0 + $1.rows.count }
        let room = max(capacity - parts.count, 0)
        return parts.flatMap { part -> [Entry] in
            [Entry(target: part.target, letter: part.letter, color: nil)]
                + kept(part.rows, rows: rows, room: room).map { Entry(target: $0.id, letter: nil, color: $0.color) }
        }
    }

    /// `section`'s share of `room`, spread evenly across it from its first.
    private static func kept(_ section: [(id: String, color: String)], rows: Int, room: Int) -> [(id: String, color: String)] {
        guard !section.isEmpty, rows > room else { return section }
        let share = min(section.count, max(1, room * section.count / max(rows, 1)))
        return (0..<share).map { section[$0 * section.count / share] }
    }
}

extension EnvironmentValues {
    /// Set inside a list with an edge index: its section headers and lazy
    /// rows carry ids the index scrolls to, headers through this.
    @Entry var edgeJump: HeaderJump?
}

/// Brings a list's section header to just below its bars, as Sheprd's
/// HeaderJump does.
///
/// A `List` scrolls to a header's id by lining the section's first row up
/// with the top of what the bars leave visible, which leaves the header
/// behind a search field, and SwiftUI can't scroll a list by an amount. So
/// each header carries a `HeaderMark`, an invisible view whose position
/// says where the header is, and the jump moves the list's own scroll view
/// until that header's top meets the bars.
@MainActor
final class HeaderJump {
    #if os(iOS)
    private final class Mark {
        weak var view: MarkView?
    }

    private var marks: [String: Mark] = [:]
    #endif
    /// The latest jump: a drag along the index starts one per entry it
    /// crosses, and only the one it ends on may still move the list.
    private var latest = 0
    /// Room left between the bars and the header's title.
    private static let gap: CGFloat = 8

    #if os(iOS)
    fileprivate func register(_ view: MarkView, for key: String) {
        // A list reuses a header's view for another header, so the view
        // says which header it shows now, and a stale entry is ignored.
        view.key = key
        let mark = marks[key] ?? Mark()
        mark.view = view
        marks[key] = mark
    }
    #endif

    /// Scrolls to `key` with `proxy`; for a header, once it is laid out,
    /// on until it sits just below the bars. A later jump cancels this one.
    func go(to key: String, proxy: ScrollViewProxy) {
        latest += 1
        let jump = latest
        proxy.scrollTo(key, anchor: .top)
        #if os(iOS)
        Task { @MainActor in
            // The header may take a few frames to be laid out where the
            // list scrolled.
            for _ in 0..<10 {
                await Task.yield()
                guard jump == latest else { return }
                if settle(key) { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        #endif
    }

    #if os(iOS)
    /// Scrolls so the header marked `key` sits just below the bars, or
    /// says it is not on screen yet.
    private func settle(_ key: String) -> Bool {
        guard let view = marks[key]?.view, view.key == key, view.window != nil,
              let scroll = sequence(first: view.superview, next: { $0?.superview }).lazy
                  .compactMap({ $0 as? UIScrollView }).first
        else { return false }
        scroll.layoutIfNeeded()
        let top = view.convert(view.bounds, to: scroll).minY
        let lowest = -scroll.adjustedContentInset.top
        let highest = max(lowest, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        let y = min(max(top - scroll.adjustedContentInset.top - Self.gap, lowest), highest)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
        return true
    }
    #endif
}

#if os(iOS)
/// The invisible view a section header carries for `HeaderJump`, as wide
/// and tall as the header itself.
struct HeaderMark: UIViewRepresentable {
    let jump: HeaderJump
    let key: String

    func makeUIView(context: Context) -> MarkView {
        let view = MarkView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: MarkView, context: Context) {
        jump.register(view, for: key)
    }
}

/// A header's mark, knowing which header it shows now.
final class MarkView: UIView {
    var key: String?
}
#endif
