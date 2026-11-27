import MoonKit
import SwiftUI

/// What any element can ask of the system around it, as props: a title and
/// toolbar for the screen it is, search, pull to refresh, swipe actions and
/// a context menu for the row it is, and the sheets, alerts and dialogs it
/// presents. Each costs nothing unless set.
struct Decorations: ViewModifier {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    static let keys: Set<String> = [
        "title", "subtitle", "toolbar", "search", "refresh", "swipe", "context", "sheet", "cover",
        "popover", "alert", "confirm", "badge", "tint", "appear", "disappear", "hidesBar",
    ]

    func body(content: Content) -> some View {
        if node.props.keys.contains(where: Self.keys.contains) {
            content
                .modifier(Screen(node: node, scope: scope, send: send))
                .modifier(Row(node: node, scope: scope, send: send))
                .modifier(Presented(node: node, scope: scope, send: send))
        } else {
            content
        }
    }
}

/// `title`, `subtitle`, `toolbar`, `search` and `refresh`.
private struct Screen: ViewModifier {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @Environment(Workspace.self) private var workspace

    func body(content: Content) -> some View {
        content
            .modifier(Title(node: node))
            .modifier(Toolbar(node: node, scope: scope, send: send))
            .modifier(Search(node: node, send: send))
            .modifier(Refresh(node: node, scope: scope, send: send, workspace: workspace))
            .modifier(Lifecycle(node: node, send: send))
    }
}

private struct Title: ViewModifier {
    let node: Node

    func body(content: Content) -> some View {
        if let title = node.string("title"), node.kind != .panel, node.kind != .section {
            content
                .navigationTitle(title)
                .modifier(Subtitle(text: node.string("subtitle")))
                #if os(iOS)
                .navigationBarTitleDisplayMode(mode)
                .toolbar(node.flag("hidesBar") ? .hidden : .automatic, for: .navigationBar)
                #endif
        } else {
            content
        }
    }

    #if os(iOS)
    private var mode: NavigationBarItem.TitleDisplayMode {
        switch node.string("titleMode") {
        case "inline": .inline
        case "large": .large
        default: .automatic
        }
    }
    #endif
}

private struct Subtitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.navigationSubtitle(text) } else { content }
    }
}

/// `toolbar = { ui.button { icon = "plus", place = "primary", msg = "new" }, ui.menu { ... } }`.
/// `place`: `primary` (the default), `leading`, `trailing`, `principal`,
/// `bottom`, `cancel`, `confirm`, `status`, `keyboard`.
private struct Toolbar: ViewModifier {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        let items = node.elements("toolbar")
        if items.isEmpty {
            content
        } else {
            content.toolbar {
                ForEach(Identified.of(items)) { item in
                    if item.node.kind == .spacer {
                        ToolbarSpacer(item.node.string("variant") == "fixed" ? .fixed : .flexible, placement: placement(item.node))
                    } else {
                        ToolbarItem(placement: placement(item.node)) {
                            ToolbarEntry(node: item.node, scope: scope.child("toolbar/\(item.id)"), send: send)
                        }
                    }
                }
            }
        }
    }

    private func placement(_ item: Node) -> ToolbarItemPlacement {
        switch item.string("place") {
        case "cancel": .cancellationAction
        case "confirm": .confirmationAction
        case "principal": .principal
        case "status": .status
        case "navigation": .navigation
        #if os(iOS)
        case "leading": .topBarLeading
        case "trailing": .topBarTrailing
        case "bottom": .bottomBar
        case "keyboard": .keyboard
        #else
        case "leading": .navigation
        #endif
        default: .primaryAction
        }
    }
}

/// A toolbar item: the system draws buttons and menus its own way.
private struct ToolbarEntry: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    var body: some View {
        switch node.kind {
        case .button:
            Button(role: node.role) {
                if let message = node.props["msg"] { send(message) }
            } label: {
                ButtonLabel(node: node)
            }
            .disabled(node.flag("disabled"))
            .accessibilityIdentifier(node.string("id") ?? scope.key)
            .modifier(Prominent(on: node.string("variant") == "primary"))
        case .menu:
            MenuNode(node: node, scope: scope, identifier: node.string("id") ?? scope.key, send: send)
        default:
            NodeView(node: node, scope: scope).equatable()
        }
    }
}

private struct Prominent: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.buttonStyle(.borderedProminent) } else { content }
    }
}

/// `search = { value = state.query, change = "query", prompt = "Search" }`.
private struct Search: ViewModifier {
    let node: Node
    let send: (LuauValue) -> Void

    @State private var text = ""

    func body(content: Content) -> some View {
        if let search = node.props["search"] {
            content
                .searchable(text: $text, prompt: search["prompt"]?.string ?? "Search")
                .onChange(of: search["value"]?.string ?? "", initial: true) { _, value in
                    if value != text { text = value }
                }
                .onChange(of: text) { _, value in
                    if value != search["value"]?.string ?? "" {
                        event(search["change"], value: .string(value)).map(send)
                    }
                }
                .onSubmit(of: .search) {
                    event(search["submit"], value: .string(text)).map(send)
                }
        } else {
            content
        }
    }
}

/// `refresh = "reload"`: pull to refresh sends it, and the spinner stays
/// while the view says `refreshing = true`, up to half a minute.
private struct Refresh: ViewModifier {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void
    let workspace: Workspace

    func body(content: Content) -> some View {
        if let message = node.props["refresh"] {
            content.refreshable {
                send(message)
                let mod = scope.mod, path = scope.path
                for _ in 0..<600 {
                    let busy = workspace.drawing(of: mod).tree?.node(at: path)?.flag("refreshing") ?? false
                    if !busy { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } else {
            content
        }
    }
}

/// `appear` and `disappear` messages, as a row scrolls in or a screen opens.
private struct Lifecycle: ViewModifier {
    let node: Node
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        let appear = node.props["appear"], disappear = node.props["disappear"]
        if appear == nil && disappear == nil {
            content
        } else {
            content
                .onAppear { appear.map(send) }
                .onDisappear { disappear.map(send) }
        }
    }
}

/// `swipe`, `context`, `badge` and `tint`: what a row offers.
private struct Row: ViewModifier {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .modifier(Swipe(node: node, scope: scope, send: send))
            .modifier(ContextMenu(items: node.elements("context"), scope: scope, send: send))
            .modifier(RowBadge(node: node))
            .modifier(Tint(color: workspace.stylesheet.paint(node.string("tint"), dark: scheme == .dark)))
    }
}

/// `swipe = { <buttons> }` for the trailing edge, or
/// `{ leading = { ... }, trailing = { ... } }`. A button's `tint` colors it.
private struct Swipe: ViewModifier {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let swipe = node.props["swipe"] {
            let trailing = swipe["trailing"].map(Self.buttons) ?? (swipe["leading"] == nil ? Self.buttons(swipe) : [])
            let leading = swipe["leading"].map(Self.buttons) ?? []
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: !trailing.isEmpty) { buttons(trailing) }
                .swipeActions(edge: .leading, allowsFullSwipe: !leading.isEmpty) { buttons(leading) }
        } else {
            content
        }
    }

    private static func buttons(_ value: LuauValue) -> [Node] {
        if value["type"] != nil { return [Node(value)] }
        return (value.array ?? []).filter { $0 != .bool(false) }.map(Node.init)
    }

    private func buttons(_ nodes: [Node]) -> some View {
        ForEach(Identified.of(nodes)) { item in
            SwipeButton(node: item.node, send: send)
        }
    }
}

private struct SwipeButton: View {
    let node: Node
    let send: (LuauValue) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(role: node.role) {
            if let message = node.props["msg"] { send(message) }
        } label: {
            ButtonLabel(node: node)
        }
        .tint(workspace.stylesheet.paint(node.string("tint"), dark: scheme == .dark))
    }
}

private struct ContextMenu: ViewModifier {
    let items: [Node]
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if items.isEmpty {
            content
        } else {
            content.contextMenu {
                MenuItems(nodes: items, scope: scope.child("context"), send: send)
            }
        }
    }
}

private struct RowBadge: ViewModifier {
    let node: Node

    func body(content: Content) -> some View {
        if let count = node.number("badge") {
            content.badge(Int(count))
        } else if let text = node.string("badge") {
            content.badge(Text(verbatim: text))
        } else {
            content
        }
    }
}

private struct Tint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color { content.tint(color) } else { content }
    }
}
