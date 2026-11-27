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
        "popover", "alert", "confirm", "badge", "tint", "appear", "disappear", "hidesBar", "titleMode", "overlay", "rowInsets", "rowBackground",
        "separator", "hidesTabBar",
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
        if node.kind != .panel, node.kind != .section, node.string("title") != nil || node.string("titleMode") != nil {
            content
                .modifier(NavigationTitle(text: node.string("title")))
                .modifier(Subtitle(text: node.string("subtitle")))
                #if os(iOS)
                .navigationBarTitleDisplayMode(mode)
                .toolbar(node.flag("hidesBar") ? .hidden : .automatic, for: .navigationBar)
                .toolbar(node.flag("hidesTabBar") ? .hidden : .automatic, for: .tabBar)
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

private struct NavigationTitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.navigationTitle(text) } else { content }
    }
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
                .searchable(text: $text, placement: placement(search), prompt: search["prompt"]?.string ?? "Search")
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

extension Search {
    /// `placement = "always"` keeps the field in the bar while scrolling.
    func placement(_ search: LuauValue) -> SearchFieldPlacement {
        #if os(iOS)
        switch search["placement"]?.string {
        case "always": return .navigationBarDrawer(displayMode: .always)
        case "toolbar": return .toolbar
        default: return .automatic
        }
        #else
        return search["placement"]?.string == "toolbar" ? .toolbar : .automatic
        #endif
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
            .modifier(Over(node: node, scope: scope))
    }
}

/// `rowInsets` (edges), `rowBackground` (a color) and `separator = false`:
/// how a list draws the row around the element.
struct RowChrome: ViewModifier {
    let node: Node

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if node.props["rowInsets"] == nil && node.props["rowBackground"] == nil && node.props["separator"] == nil {
            content
        } else {
            let background = workspace.stylesheet.paint(node.string("rowBackground"), dark: scheme == .dark)
            let insets = node.props["rowInsets"].flatMap { Edges($0) }.map { EdgeInsets($0) }
            content
                .listRowInsets(insets)
                .listRowBackground(background)
                .listRowSeparator(node.props["separator"]?.bool == false ? .hidden : .automatic)
        }
    }
}

/// `overlay = { place = "bottomTrailing", x = 6, y = 6, <element> }`: an
/// element drawn over this one, such as a status badge on an icon. A list of
/// them puts several.
private struct Over: ViewModifier {
    let node: Node
    let scope: Scope

    func body(content: Content) -> some View {
        let overlays = overlays
        if overlays.isEmpty {
            content
        } else {
            content.overlay {
                ForEach(overlays.indices, id: \.self) { index in
                    let overlay = overlays[index]
                    ZStack(alignment: Self.alignment(overlay.string("place"))) {
                        Color.clear
                        if let first = overlay.content.first {
                            NodeView(node: first, scope: scope.child("overlay\(index)")).equatable()
                                .offset(x: overlay.fields["x"]?.number ?? 0, y: overlay.fields["y"]?.number ?? 0)
                        }
                    }
                }
            }
        }
    }

    private var overlays: [Overlay] {
        guard let value = node.props["overlay"] else { return [] }
        if case .table(let array, let fields) = value, fields.isEmpty, array.allSatisfy({ $0["type"] == nil }) {
            return array.compactMap { item in
                guard case .table(let inner, let fields) = item else { return nil }
                return Overlay(fields: fields, content: inner.map(Node.init))
            }
        }
        return node.overlay("overlay").map { [$0] } ?? []
    }

    static func alignment(_ name: String?) -> Alignment {
        switch name {
        case "top": .top
        case "bottom": .bottom
        case "leading": .leading
        case "trailing": .trailing
        case "topLeading": .topLeading
        case "topTrailing": .topTrailing
        case "bottomLeading": .bottomLeading
        case "bottomTrailing": .bottomTrailing
        default: .center
        }
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
