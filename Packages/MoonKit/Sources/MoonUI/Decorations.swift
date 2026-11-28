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

    /// What each group reads. A row with a context menu pays for the
    /// row's group alone, not for a screen's title, search and insets.
    static let screenKeys: Set<String> = [
        "title", "titleMode", "subtitle", "hidesBar", "hidesTabBar", "toolbar", "search", "refresh", "appear",
        "disappear", "inset", "scrollTo", "index", "indexed",
    ]
    static let rowKeys: Set<String> = ["context", "tint", "overlay", "transition", "scheme"]
    static let presentedKeys: Set<String> = ["sheet", "cover", "popover", "alert", "confirm"]

    /// A context menu and no other decoration.
    static func menuOnly(_ node: Node) -> Bool {
        node.props["context"] != nil && !node.props.keys.contains {
            $0 != "context" && (screenKeys.contains($0) || rowKeys.contains($0) || presentedKeys.contains($0))
        }
    }

    static func used(by node: Node) -> Bool {
        node.props.keys.contains { screenKeys.contains($0) || rowKeys.contains($0) || presentedKeys.contains($0) }
    }

    func body(content: Content) -> AnyView {
        let keys = node.props.keys
        let screen = keys.contains(where: Self.screenKeys.contains)
        let row = keys.contains(where: Self.rowKeys.contains)
        let presented = keys.contains(where: Self.presentedKeys.contains)
        // Erased each way, so a row's menu doesn't set up a screen's
        // search, toolbar and sheets before the first frame.
        if !screen, !row, !presented {
            return AnyView(content)
        } else if Self.menuOnly(node) {
            // A row's menu alone, the common case, the short way.
            return AnyView(content.contextMenu {
                MenuItems(nodes: node.elements("context"), scope: scope.child("context"), send: send)
            })
        }
        return AnyView(
            content
                .modifier(Screen(on: screen, node: node, scope: scope, send: send))
                .modifier(Row(on: row, node: node, scope: scope, send: send))
                .modifier(Presented(on: presented, node: node, scope: scope, send: send))
        )
    }
}

/// `title`, `subtitle`, `toolbar`, `search` and `refresh`.
private struct Screen: ViewModifier {
    let on: Bool
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @Environment(Workspace.self) private var workspace

    func body(content: Content) -> some View {
        if on { screen(content) } else { content }
    }

    /// Only the modifiers the element sets, each erased: a list with a
    /// title and search doesn't set up a toolbar's, an inset's or a
    /// section index's types before its first frame.
    private func screen(_ content: Content) -> AnyView {
        let has = { (keys: [String]) in keys.contains { node.props[$0] != nil } }
        var view = AnyView(content)
        if has(["title", "titleMode", "subtitle", "hidesBar", "hidesTabBar"]) { view = AnyView(view.modifier(Title(node: node))) }
        if has(["toolbar"]) { view = AnyView(view.modifier(Toolbar(node: node, scope: scope, send: send))) }
        if has(["search"]) { view = AnyView(view.modifier(Search(node: node, send: send))) }
        if has(["refresh"]) { view = AnyView(view.modifier(Refresh(node: node, scope: scope, send: send, workspace: workspace))) }
        if has(["appear", "disappear"]) { view = AnyView(view.modifier(Lifecycle(node: node, send: send))) }
        if has(["inset"]) { view = AnyView(view.modifier(Inset(node: node, scope: scope))) }
        if has(["scrollTo"]) { view = AnyView(view.modifier(ScrollTo(node: node))) }
        if has(["index", "indexed"]) { view = AnyView(view.modifier(SectionIndex(node: node))) }
        return view
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
            .modifier(Shortcut(text: node.string("shortcut")))
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
    let on: Bool
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if on { row(content) } else { content }
    }

    /// Only the modifiers the element sets, each erased.
    private func row(_ content: Content) -> AnyView {
        var view = AnyView(content)
        if node.props["context"] != nil {
            view = AnyView(view.modifier(ContextMenu(items: node.elements("context"), scope: scope, send: send)))
        }
        if node.props["tint"] != nil {
            view = AnyView(view.modifier(Tint(color: workspace.stylesheet.paint(node.string("tint"), dark: scheme == .dark))))
        }
        if node.props["overlay"] != nil { view = AnyView(view.modifier(Over(node: node, scope: scope))) }
        if node.props["transition"] != nil { view = AnyView(view.modifier(Transition(name: node.string("transition")))) }
        if node.props["scheme"] != nil { view = AnyView(view.modifier(Scheme(name: node.string("scheme")))) }
        return view
    }
}

/// `scheme = "dark" | "light"`: the appearance for this element's window,
/// as an Appearance setting chooses. Anything else follows the system.
private struct Scheme: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        switch name {
        case "dark": content.preferredColorScheme(.dark)
        case "light": content.preferredColorScheme(.light)
        case nil: content
        default: content.preferredColorScheme(nil)
        }
    }
}

/// `inset = { edge = "bottom", <element> }`: an element the content scrolls
/// under, as a composer under a chat or a bar over a list. A list of them
/// insets several edges.
private struct Inset: ViewModifier {
    let node: Node
    let scope: Scope

    func body(content: Content) -> some View {
        let insets = Self.insets(node)
        let top = insets.first { $0.string("edge") == "top" }
        let bottom = insets.first { $0.string("edge") != "top" }
        if insets.isEmpty {
            content
        } else {
            inset(content, top: top, bottom: bottom)
        }
    }

    private func inset(_ content: Content, top: Overlay?, bottom: Overlay?) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let bottom, let first = bottom.content.first {
                    NodeView(node: first, scope: scope.child("inset-bottom")).equatable()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let top, let first = top.content.first {
                    NodeView(node: first, scope: scope.child("inset-top")).equatable()
                }
            }
    }

    static func insets(_ node: Node) -> [Overlay] {
        guard let value = node.props["inset"] else { return [] }
        if case .table(let array, let fields) = value, fields.isEmpty, array.allSatisfy({ $0["type"] == nil }) {
            return array.compactMap { item in
                guard case .table(let inner, let fields) = item else { return nil }
                return Overlay(fields: fields, content: inner.map(Node.init))
            }
        }
        return node.overlay("inset").map { [$0] } ?? []
    }
}

/// `scrollTo = key`: scrolls the list or scroll view to the row with that
/// key whenever it changes; `scrollAnchor = "bottom"` puts it there.
private struct ScrollTo: ViewModifier {
    let node: Node

    func body(content: Content) -> some View {
        if let target = node.props["scrollTo"] {
            ScrollViewReader { proxy in
                content.onChange(of: target, initial: true) { _, target in
                    let anchor: UnitPoint = switch node.string("scrollAnchor") {
                    case "bottom": .bottom
                    case "center": .center
                    default: .top
                    }
                    withAnimation(.snappy) {
                        proxy.scrollTo(target, anchor: anchor)
                        if let key = target.string { proxy.scrollTo(key, anchor: anchor) }
                    }
                }
            }
        } else {
            content
        }
    }
}

/// `index = "A"` on a section labels it in the list's index along the edge,
/// shown when the list says `indexed = true`.
private struct SectionIndex: ViewModifier {
    let node: Node

    func body(content: Content) -> some View {
        #if os(iOS)
        if let label = node.string("index") {
            content.sectionIndexLabel(Text(verbatim: label))
        } else if let shown = node.props["indexed"]?.bool {
            content.listSectionIndexVisibility(shown ? .visible : .hidden)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// `transition = "opacity" | "scale" | "slide" | "top" | "bottom" | ...`:
/// how the element comes and goes as the view changes.
private struct Transition: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        switch name {
        case "opacity": content.transition(.opacity)
        case "scale": content.transition(.scale.combined(with: .opacity))
        case "slide": content.transition(.slide)
        case "top": content.transition(.move(edge: .top).combined(with: .opacity))
        case "bottom": content.transition(.move(edge: .bottom).combined(with: .opacity))
        case "leading": content.transition(.move(edge: .leading).combined(with: .opacity))
        case "trailing": content.transition(.move(edge: .trailing).combined(with: .opacity))
        default: content
        }
    }
}

/// `shortcut = "cmd+n"`, `"cmd+shift+k"`, `"return"`, `"escape"`: a key
/// that presses the button, on a keyboard.
struct Shortcut: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let (key, modifiers) = text.flatMap(Self.parse) {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }

    static func parse(_ text: String) -> (KeyEquivalent, EventModifiers)? {
        var modifiers: EventModifiers = []
        var key: KeyEquivalent?
        for part in text.lowercased().split(separator: "+") {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            case "return", "enter": key = .return
            case "escape", "esc": key = .escape
            case "delete": key = .delete
            case "tab": key = .tab
            case "space": key = .space
            case "up": key = .upArrow
            case "down": key = .downArrow
            case "left": key = .leftArrow
            case "right": key = .rightArrow
            default: if part.count == 1, let character = part.first { key = KeyEquivalent(character) }
            }
        }
        return key.map { ($0, modifiers) }
    }
}

/// A row: its element as exactly one view, with its `badge` when it has
/// one. A badge, even none, lays the row out beside it, a layout around
/// every row measured on each that scrolls in, so only rows with one pay.
/// It sits inside the one view, where the list doesn't look: a branch
/// outside would make it draw every row to learn their traits.
struct RowView: View {
    let node: Node
    let scope: Scope

    var body: some View {
        _UnaryViewAdaptor(badged)
    }

    @ViewBuilder
    private var badged: some View {
        let view = NodeView(node: node, scope: scope).equatable()
        if let badge = RowTraits.badge(of: node) { view.badge(badge) } else { view }
    }
}

/// What a list reads off a row itself, so it must sit on the row's outside:
/// `swipe` and the row's chrome (`rowInsets`, `rowBackground`,
/// `separator = false`). Lists apply it where they make each row.
///
/// Every modifier here is always applied, unset ones with the system's
/// default. A lazy list reads these as traits, and a row whose traits sit
/// behind an `if` makes it build every row to find them: 10,000 rows, all
/// drawn at once.
struct RowTraits: ViewModifier {
    let node: Node
    let scope: Scope

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let swipe = node.props["swipe"]
        let trailing = swipe.map { $0["trailing"].map(Self.buttons) ?? ($0["leading"] == nil ? Self.buttons($0) : []) } ?? []
        let leading = swipe?["leading"].map(Self.buttons) ?? []
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: !trailing.isEmpty) { buttons(trailing) }
            .swipeActions(edge: .leading, allowsFullSwipe: !leading.isEmpty) { buttons(leading) }
            .listRowInsets(node.props["rowInsets"].flatMap { Edges($0) }.map { EdgeInsets($0) })
            .listRowBackground(workspace.stylesheet.paint(node.string("rowBackground"), dark: scheme == .dark))
            .listRowSeparator(node.props["separator"]?.bool == false ? .hidden : .automatic)
    }

    static func badge(of node: Node) -> Text? {
        if let count = node.number("badge") { return Text(verbatim: String(Int(count))) }
        return node.string("badge").map { Text(verbatim: $0) }
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

    private func send(_ message: LuauValue) {
        workspace.send(message, to: node.string("to") ?? scope.mod)
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

private struct Tint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color { content.tint(color) } else { content }
    }
}
