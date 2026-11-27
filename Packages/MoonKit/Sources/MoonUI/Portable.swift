import MoonKit
import SwiftUI

// Moonframe's elements that MoonSwift had no element for, drawn the way a
// Mac or a phone would: plans/moonframe-compat.md, section 4, says how each
// degrades.

/// `ui.item { "Inbox", detail = "12", badge = "new", selected = ... }`: a
/// sidebar row. Its look on hover and when selected is the stylesheet's
/// `item:hover` and `item:selected`.
struct ItemNode: View {
    let node: Node

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: node.string("label") ?? "")
                .lineLimit(1)
            Spacer(minLength: 0)
            if let detail = node.string("detail") {
                Text(verbatim: detail).foregroundStyle(.secondary)
            }
            if let badge = node.string("badge") {
                Text(verbatim: badge)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(.tint.opacity(0.15)))
            }
        }
        .contentShape(Rectangle())
    }
}

/// `ui.hsplit` and `ui.vsplit` of `ui.pane`s. On a Mac the panes sit side by
/// side (or stacked) and the user resizes them. On iOS an `hsplit` is a
/// navigation split view, its first pane the sidebar and its last the
/// detail, which an iPhone collapses to a stack.
struct SplitPanesNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        let panes = Identified.of(node.children.filter { $0.flag("visible") || $0.props["visible"] == nil })
        #if os(iOS)
        if node.kind == .hsplit, panes.count >= 2 {
            NavigationSplitView {
                pane(panes[0])
            } detail: {
                if panes.count > 2 {
                    HStack(spacing: 0) { ForEach(panes.dropFirst()) { pane($0) } }
                } else {
                    pane(panes[1])
                }
            }
        } else {
            stacked(panes)
        }
        #else
        if node.kind == .hsplit {
            HSplitView { ForEach(panes) { pane($0) } }
        } else {
            VSplitView { ForEach(panes) { pane($0) } }
        }
        #endif
    }

    @ViewBuilder
    private func stacked(_ panes: [Identified]) -> some View {
        if node.kind == .hsplit {
            HStack(spacing: 0) { ForEach(panes) { pane($0) } }
        } else {
            VStack(spacing: 0) { ForEach(panes) { pane($0) } }
        }
    }

    private func pane(_ pane: Identified) -> some View {
        let size = pane.node.number("size").map { CGFloat($0) }
        let low = pane.node.number("min").map { CGFloat($0) }
        let high = pane.node.number("max").map { CGFloat($0) }
        let wide = node.kind == .hsplit
        return NodeView(node: pane.node, scope: scope.child(pane.id)).equatable()
            .frame(
                minWidth: wide ? low : nil, idealWidth: wide ? size : nil, maxWidth: wide ? high ?? .infinity : .infinity,
                minHeight: wide ? nil : low, idealHeight: wide ? nil : size, maxHeight: wide ? .infinity : high ?? .infinity
            )
    }
}

/// `ui.popover { open = ..., dismiss = ..., content = el, <anchor> }`: the
/// system's popover on its anchor, a sheet on an iPhone.
struct PopoverNode: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { Children(node: node, scope: scope) }
            .popover(isPresented: presented(node, send: send), arrowEdge: edge) {
                if let content = node.elements("content").first {
                    NodeView(node: content, scope: scope.child("content")).equatable()
                        .padding()
                        .frame(width: node.number("width").map { CGFloat($0) })
                }
            }
    }

    private var edge: Edge? {
        switch node.string("side") {
        case "top": .top
        case "left": .leading
        case "right": .trailing
        case "bottom": .bottom
        default: nil
        }
    }
}

/// `ui.overlay { open = ..., dismiss = ..., content = el }`: a dialog,
/// palette or sheet over the window, as the system's sheet.
struct OverlayNode: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: presented(node, send: send)) {
                if let content = node.elements("content").first {
                    NodeView(node: content, scope: scope.child("content")).equatable()
                        .frame(
                            width: node.number("width").map { CGFloat($0) },
                            height: node.number("height").map { CGFloat($0) }
                        )
                }
            }
    }
}

/// `open`, and `dismiss` sent when the system closes it.
@MainActor
private func presented(_ node: Node, send: @escaping (LuauValue) -> Void) -> Binding<Bool> {
    Binding {
        node.flag("open")
    } set: { open in
        if !open, node.flag("open"), let dismiss = node.props["dismiss"] { send(dismiss) }
    }
}

/// `ui.browser { url = ... }`: a link that opens the page in the browser,
/// as long as it is a web address.
struct BrowserNode: View {
    let node: Node

    var body: some View {
        if let text = node.string("url"), let url = URL(string: text), LinkNode.schemes.contains(url.scheme ?? "") {
            Link(destination: url) {
                Label(url.host() ?? text, systemImage: "safari")
            }
        } else {
            PlaceholderNode(node: node)
        }
    }
}

/// What a Moonframe element MoonSwift can't draw yet shows in its place.
struct PlaceholderNode: View {
    let node: Node

    var body: some View {
        Label("ui.\(node.kind.rawValue)", systemImage: "square.dashed")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(
                width: node.number("width").map { CGFloat($0) },
                height: node.number("height").map { CGFloat($0) }
            )
            .help("ui.\(node.kind.rawValue) draws on Moonframe only")
    }
}
