import MoonKit
import SwiftUI

/// `ui.list`: the system's list, lazy all the way down. As in Moonframe,
/// `count` and `row = function(i)` add rows the mod draws only as they
/// scroll into view; `row_height` is left to the rows, which size
/// themselves. Here its children may also be rows and `ui.section`s.
struct ListNode: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @State private var headerJump = HeaderJump()

    var body: some View {
        if node.flag("edge") {
            // `edge = true`: an index down the trailing edge (EdgeIndex.swift).
            let parts = EdgePart.parts(of: node, scope: scope)
            ScrollViewReader { proxy in
                styled(list)
                    .environment(\.edgeJump, headerJump)
                    .overlay(alignment: .trailing) {
                        if !parts.isEmpty {
                            EdgeIndexStrip(parts: parts) { target in headerJump.go(to: target, proxy: proxy) }
                                .padding(.vertical, 24)
                                .padding(.trailing, 2)
                        }
                    }
            }
        } else {
            styled(list)
        }
    }

    @ViewBuilder
    private var list: some View {
        if let change = node.props["change"] {
            List(selection: Binding<LuauValue?> {
                node.props["selection"]
            } set: { value in
                event(change, value: value ?? .bool(false)).map(send)
            }) {
                ListContent(node: node, scope: scope)
            }
        } else {
            List { ListContent(node: node, scope: scope) }
        }
    }

    @ViewBuilder
    private func styled(_ list: some View) -> some View {
        switch node.string("variant") {
        case "plain": list.listStyle(.plain)
        case "sidebar": list.listStyle(.sidebar)
        #if os(iOS)
        case "grouped": list.listStyle(.grouped)
        case "inset": list.listStyle(.insetGrouped)
        #else
        case "inset": list.listStyle(.inset)
        #endif
        default: list
        }
    }
}

/// `ui.form`: grouped settings, laid out by the platform.
struct FormNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        Form { ListContent(node: node, scope: scope) }
            .formStyle(.grouped)
    }
}

/// A list's or form's rows: sections as the system's, everything else a row.
struct ListContent: View {
    let node: Node
    let scope: Scope

    var body: some View {
        ForEach(Identified.of(node.children)) { child in
            if child.node.kind == .section {
                SectionNode(node: child.node, scope: scope.child(child.id))
            } else {
                RowView(node: child.node, scope: scope.child(child.id))
                    .modifier(RowTraits(node: child.node, scope: scope.child(child.id)))
                    .tag(child.node.props["key"] ?? .string(child.id))
            }
        }
        if let rows = node.lazyRows {
            LazyRows(count: rows.count, function: rows.function, scope: scope, owner: node)
        }
    }
}

/// `ui.section { title = "Pinned", footer = "...", ... }`. `header` may be
/// an element instead of a title. `collapsed` with `change` folds it.
struct SectionNode: View {
    let node: Node
    let scope: Scope

    @Environment(Workspace.self) private var workspace
    @Environment(\.edgeJump) private var jump

    var body: some View {
        if let change = node.props["change"] {
            Section(isExpanded: Binding {
                !node.flag("collapsed")
            } set: { open in
                event(change, value: .bool(!open)).map { workspace.send($0, to: node.string("to") ?? scope.mod) }
            }) {
                rows
            } header: {
                header
            }
        } else {
            Section {
                rows
            } header: {
                header
            } footer: {
                if let footer = node.string("footer") { Text(verbatim: footer) }
            }
        }
    }

    private var rows: some View {
        Children(node: node, scope: scope, rows: true)
    }

    @ViewBuilder
    private var header: some View {
        if let jump {
            title
                .id(EdgePart.anchor(scope))
                #if os(iOS)
                .background(HeaderMark(jump: jump, key: EdgePart.anchor(scope)))
                #endif
        } else {
            title
        }
    }

    @ViewBuilder
    private var title: some View {
        if let header = node.elements("header").first {
            NodeView(node: header, scope: scope.child("header")).equatable()
        } else if let title = node.string("title") {
            Text(verbatim: title)
        }
    }
}

/// `ui.scroll`: a scrolling stack, lazy unless `lazy = false`, along `axis`.
struct ScrollNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        let horizontal = node.string("axis") == "x"
        let lazy = node.props["lazy"]?.bool ?? true
        ScrollView(horizontal ? .horizontal : .vertical) {
            if horizontal {
                if lazy {
                    LazyHStack(alignment: node.verticalAlignment, spacing: node.spacing) { Children(node: node, scope: scope) }
                } else {
                    HStack(alignment: node.verticalAlignment, spacing: node.spacing) { Children(node: node, scope: scope) }
                }
            } else {
                Group {
                    if lazy {
                        LazyVStack(alignment: node.horizontalAlignment, spacing: node.spacing) {
                            Children(node: node, scope: scope)
                        }
                    } else {
                        VStack(alignment: node.horizontalAlignment, spacing: node.spacing) { Children(node: node, scope: scope) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .defaultScrollAnchor(node.string("anchor") == "bottom" ? .bottom : nil)
    }
}

/// `ui.grid { columns = 3 }` or `{ min = 120 }` for as many as fit.
struct GridNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        LazyVGrid(columns: columns, alignment: node.horizontalAlignment, spacing: node.spacing) {
            Children(node: node, scope: scope)
        }
    }

    private var columns: [GridItem] {
        if let minimum = node.number("min") {
            return [GridItem(.adaptive(minimum: minimum), spacing: node.spacing)]
        }
        let count = node.integer("columns", in: 1...64) ?? 2
        return Array(repeating: GridItem(.flexible(), spacing: node.spacing), count: count)
    }
}

/// `ui.disclosure { "Advanced", ... }`: folds its children. Kept by the mod
/// with `expanded` and `change`, or by itself without.
struct DisclosureNode: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: binding) {
            Children(node: node, scope: scope)
        } label: {
            if let icon = node.string("icon") {
                Label(node.string("label") ?? "", systemImage: Icons.symbol(or: icon, default: "questionmark"))
            } else {
                Text(verbatim: node.string("label") ?? "")
            }
        }
    }

    private var binding: Binding<Bool> {
        guard let change = node.props["change"] else { return $expanded }
        return Binding { node.flag("expanded") } set: { value in
            event(change, value: .bool(value)).map(send)
        }
    }
}
