import MoonKit
import SwiftUI

/// `ui.stack { path = state.path, change = "path", screen = function(route) ... end, <root> }`:
/// a navigation stack. Its path is a list of routes, plain values; each
/// pushed route is drawn by `screen(route)`.
/// With `change`, the mod keeps the path and hears every push and pop;
/// without, the stack keeps it.
struct StackNode: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @State private var own: [LuauValue] = []

    var body: some View {
        NavigationStack(path: path) {
            root
                .navigationDestination(for: LuauValue.self) { route in
                    if let screen = node.function("screen") {
                        PartView(function: screen, key: route, scope: scope.child("screen:\(route.summary)"))
                    } else {
                        WarningMark(text: "this stack has no screen function to draw \(route.summary)")
                    }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        if let first = Identified.of(node.children).first {
            NodeView(node: first.node, scope: scope.child(first.id)).equatable()
        }
    }

    private var path: Binding<[LuauValue]> {
        guard let change = node.props["change"] else { return $own }
        return Binding {
            node.props["path"]?.array ?? []
        } set: { routes in
            event(change, value: .table(array: routes, fields: [:])).map(send)
        }
    }
}

/// `ui.link { route = ..., <label> }` pushes a route on the stack it is in;
/// `ui.link { url = "https://..." }` opens a page. Its label is its children,
/// or its `text` and `icon`.
struct LinkNode: View {
    static let schemes: Set<String> = ["https", "http", "mailto"]

    let node: Node
    let scope: Scope
    let identifier: String
    let send: (LuauValue) -> Void

    var body: some View {
        if let route = node.props["route"] {
            NavigationLink(value: route) { label }
                .accessibilityIdentifier(identifier)
        } else if let url = node.string("url").flatMap(URL.init(string:)), Self.schemes.contains(url.scheme?.lowercased() ?? "") {
            // Only on a tap, and to the browser or mail: what it carries is
            // in plain sight.
            Link(destination: url) { label }
                .accessibilityIdentifier(identifier)
        } else {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if node.children.isEmpty {
            if let icon = node.string("icon") {
                Label(node.string("text") ?? "", systemImage: Icons.symbol(or: icon, default: "questionmark"))
            } else {
                Text(verbatim: node.string("text") ?? "")
            }
        } else {
            // One view, not a list of them: inside a list row, a ForEach
            // would be read as rows of its own.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Identified.of(node.children)) { child in
                    NodeView(node: child.node, scope: scope.child(child.id)).equatable()
                }
            }
        }
    }
}

/// `ui.tabs { selection = state.tab, change = "tab", ui.tab { "Sessions", icon = ..., key = ... } }`.
/// Each tab's first child is its content; `badge` counts on it, and
/// `role = "search"` makes it the system's search tab.
struct TabsNode: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @State private var own = ""

    var body: some View {
        let tabs = Identified.of(node.children.filter { $0.kind == .tab })
        let view = TabView(selection: selection(default: tabs.first?.id ?? "")) {
            ForEach(tabs) { tab in
                Tab(value: tab.id, role: tab.node.string("role") == "search" ? .search : nil) {
                    TabContent(node: tab.node, scope: scope.child(tab.id))
                } label: {
                    Label(tab.node.string("text") ?? tab.id, systemImage: Icons.symbol(or: tab.node.string("icon"), default: "circle"))
                }
                .badge(tab.node.number("badge").map(Int.init) ?? 0)
            }
        }
        switch node.string("variant") {
        case "sidebar": view.tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        // A pager, as an image gallery: swipe between tabs, no bar.
        case "page": view.tabViewStyle(.page(indexDisplayMode: node.flag("dots") ? .always : .never))
        #endif
        default: view
        }
    }

    private func selection(default first: String) -> Binding<String> {
        guard let change = node.props["change"] else {
            return Binding { own.isEmpty ? first : own } set: { own = $0 }
        }
        return Binding {
            node.string("selection") ?? first
        } set: { key in
            event(change, value: .string(key)).map(send)
        }
    }
}

/// A tab's content: its first child, with the tab's own decorations.
private struct TabContent: View {
    let node: Node
    let scope: Scope

    var body: some View {
        if let first = Identified.of(node.children).first {
            NodeView(node: first.node, scope: scope.child(first.id)).equatable()
        }
    }
}

/// `ui.split { <sidebar>, <detail> }`, or three for a middle column.
struct SplitNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        let columns = Identified.of(node.children)
        if columns.count >= 3 {
            NavigationSplitView {
                column(columns[0])
            } content: {
                column(columns[1])
            } detail: {
                column(columns[2])
            }
        } else {
            NavigationSplitView {
                if let first = columns.first { column(first) }
            } detail: {
                if columns.count > 1 { column(columns[1]) }
            }
        }
    }

    private func column(_ child: Identified) -> some View {
        NodeView(node: child.node, scope: scope.child(child.id)).equatable()
    }
}
