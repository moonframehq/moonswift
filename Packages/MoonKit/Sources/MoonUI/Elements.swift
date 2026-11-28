import MoonKit
import SwiftUI

/// What each element draws inside its box: one erased view per kind. As a
/// `@ViewBuilder` switch, the first element drawn would make SwiftUI set up
/// the types of every kind, controls and markdown too, before the first
/// frame; erased, it sets up only the kinds a screen shows.
extension NodeView {
    func content(_ style: StyleRule) -> AnyView {
        let font = font(style)
        switch node.kind {
        case .row:
            let gap = style.gap.map { CGFloat($0) } ?? node.spacing
            if node.flag("wrap") {
                return AnyView(FlowLayout(spacing: gap) { Children(node: node, scope: scope) })
            }
            if Fixed.fits(node) {
                return AnyView(FixedRow(alignment: node.verticalAlignment, spacing: gap, children: node.children, scope: scope))
            }
            return AnyView(HStack(alignment: node.verticalAlignment, spacing: gap) { Children(node: node, scope: scope) })
        case .column:
            let gap = style.gap.map { CGFloat($0) } ?? node.spacing
            if Fixed.fits(node) {
                let column = FixedColumn(alignment: node.horizontalAlignment, spacing: gap, children: node.children, scope: scope)
                return scrolling(column)
            }
            return scrolling(VStack(alignment: node.horizontalAlignment, spacing: gap) { Children(node: node, scope: scope) })
        case .panel:
            return scrolling(VStack(alignment: .leading, spacing: node.spacing) {
                if let title = node.string("title") { panelTitle(title) }
                Children(node: node, scope: scope)
            })
        case .scroll:
            return AnyView(ScrollNode(node: node, scope: scope))
        case .grid:
            return AnyView(GridNode(node: node, scope: scope))
        case .fits:
            return AnyView(ViewThatFits { Children(node: node, scope: scope) })
        case .labeled:
            return AnyView(LabeledNode(node: node, scope: scope))
        case .share:
            return AnyView(ShareNode(node: node, identifier: identifier))
        case .edit:
            #if os(iOS)
            return AnyView(EditButton().accessibilityIdentifier(identifier))
            #else
            return AnyView(EmptyView())
            #endif
        case .divider:
            return AnyView(Divider())
        case .text:
            // A plain string, the most common element, without a view of its own.
            if TextNode.isPlain(node) {
                return AnyView(
                    TextNode.plain(node).digits(node.flag("digits")).font(font)
                        .lineLimit(TextNode.lines(node))
                        .accessibilityIdentifier(identifier)
                )
            }
            return AnyView(TextNode(node: node, identifier: identifier).font(font))
        case .markdown:
            return AnyView(MarkdownNode(node: node).font(font))
        case .label:
            return AnyView(LabelNode(node: node, scope: scope).font(font))
        case .badge:
            // A pill, as Moonframe's theme draws one, unless a rule says how.
            let text = Text(verbatim: node.string("text") ?? "")
            if style.background == nil {
                return AnyView(
                    text.font(font ?? .caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.tint.opacity(0.15)))
                )
            }
            return AnyView(text.font(font))
        case .icon:
            return AnyView(IconNode(node: node).font(font))
        case .image:
            return AnyView(ImageNode(node: node))
        case .progress:
            return AnyView(ProgressNode(node: node))
        case .unavailable:
            return AnyView(UnavailableNode(node: node, scope: scope))
        case .link:
            return AnyView(LinkNode(node: node, scope: scope, identifier: identifier, send: send))
        case .disclosure:
            return AnyView(DisclosureNode(node: node, scope: scope, send: send))
        case .button:
            return AnyView(ButtonNode(node: node, identifier: identifier, send: send))
        case .input, .secure, .editor, .toggle, .slider, .stepper, .picker:
            return AnyView(ControlNode(node: node, identifier: identifier, send: send))
        case .menu:
            return AnyView(MenuNode(node: node, scope: scope, identifier: identifier, send: send).font(font))
        case .native, .view:
            return AnyView(NativeNode(node: node, send: send))
        case .terminal:
            return AnyView(NativeNode(node: node, send: send, name: "terminal"))
        case .item:
            return AnyView(ItemNode(node: node).font(font))
        case .pane:
            return AnyView(VStack(alignment: .leading, spacing: node.spacing) { Children(node: node, scope: scope) })
        case .popover:
            return AnyView(PopoverNode(node: node, scope: scope, send: send))
        case .overlay:
            return AnyView(OverlayNode(node: node, scope: scope, send: send))
        case .browser:
            return AnyView(BrowserNode(node: node))
        case .line:
            return AnyView(LineNode(node: node))
        case .hatch:
            return AnyView(HatchNode(node: node))
        case .map, .video, .paths, .revisionTimeline, .missing, .instance:
            return AnyView(PlaceholderNode(node: node))
        case .invalid:
            return AnyView(WarningMark(text: node.problem ?? "bad element"))
        case .region, .mount, .spacer, .stack, .tabs, .tab, .split, .list, .form, .section, .hsplit, .vsplit:
            return AnyView(EmptyView())
        }
    }

    /// The system's containers, drawn bare.
    @ViewBuilder
    var container: some View {
        switch node.kind {
        case .stack: StackNode(node: node, scope: scope, send: send)
        case .tabs: TabsNode(node: node, scope: scope, send: send)
        case .split: SplitNode(node: node, scope: scope)
        case .hsplit, .vsplit: SplitPanesNode(node: node, scope: scope)
        case .list: ListNode(node: node, scope: scope, send: send)
        case .form: FormNode(node: node, scope: scope)
        // Outside a list or form, a section is just its rows.
        case .section, .tab: VStack(alignment: .leading) { Children(node: node, scope: scope) }
        default: EmptyView()
        }
    }

    private func scrolling(_ stack: some View) -> AnyView {
        if node.flag("scroll") {
            // Held to the scroll view's width: a desktop row wider than a
            // phone runs off the right, not the page off both sides.
            return AnyView(ScrollView { Clamped { stack } })
        }
        return AnyView(stack)
    }

    private func panelTitle(_ title: String) -> some View {
        let style = workspace.stylesheet.resolve(selector: "panel-header")
        return Text(title.uppercased())
            .font(font(style))
            .foregroundStyle(workspace.stylesheet.paint(style.color, dark: dark) ?? .secondary)
    }
}

/// `ui.text`: a string, markdown, or a date the system keeps current, such
/// as `{ date = t, format = "relative" }`, with no timer in Luau.
struct TextNode: View {
    let node: Node
    let identifier: String

    /// A string and nothing else, which `NodeView` draws itself.
    static func isPlain(_ node: Node) -> Bool {
        node.props["date"] == nil && !node.flag("numeric") && !node.flag("selectable") && !node.flag("markdown")
            && node.props["align"] == nil
    }

    /// `lines`, or one line for `truncate`.
    static func lines(_ node: Node) -> Int? {
        node.integer("lines", in: 1...10_000) ?? (node.flag("truncate") ? 1 : nil)
    }

    static func plain(_ node: Node) -> Text {
        Text(verbatim: node.string("text") ?? "")
    }

    var body: some View {
        text
            .lineLimit(Self.lines(node))
            .modifier(Aligned(alignment: alignment))
            .modifier(Numeric(on: node.flag("numeric")))
            .modifier(Selectable(on: node.flag("selectable")))
            .modifier(Linked(on: node.flag("markdown")))
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var text: some View {
        let text = plain.digits(node.flag("digits"))
        // A date the system keeps current takes all the width it's offered;
        // held to its own, it sits where a spacer puts it.
        if node.number("date") != nil {
            text.fixedSize(horizontal: true, vertical: false)
        } else {
            text
        }
    }

    private var plain: Text {
        if let seconds = node.number("date") {
            let date = Date(timeIntervalSince1970: seconds)
            switch node.string("format") {
            case "relative": return Text(date, style: .relative)
            case "timer": return Text(timerInterval: date...Date.distantFuture, countsDown: false)
            case "offset": return Text(date, style: .offset)
            case "time": return Text(date, style: .time)
            case "date": return Text(date, style: .date)
            case "ago": return Text(date, format: .relative(presentation: .named))
            default: return Text(date, format: .dateTime)
            }
        }
        let string = node.string("text") ?? ""
        if node.flag("markdown"), let attributed = try? AttributedString(
            markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(verbatim: string)
    }

    private var alignment: TextAlignment {
        switch node.string("align") {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }
}

extension Text {
    func digits(_ on: Bool) -> Text {
        on ? monospacedDigit() : self
    }
}

private struct Selectable: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.textSelection(.enabled) } else { content }
    }
}

private struct Aligned: ViewModifier {
    let alignment: TextAlignment

    func body(content: Content) -> some View {
        if alignment == .leading { content } else { content.multilineTextAlignment(alignment) }
    }
}

private struct Numeric: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.contentTransition(.numericText()) } else { content }
    }
}

/// Only markdown has links to keep safe.
private struct Linked: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.modifier(SafeLinks()) } else { content }
    }
}

/// `ui.labeled { "Version", value = "1.2" }`: a label and its value, as
/// settings show them; children, if any, are the value instead.
struct LabeledNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        LabeledContent {
            if node.children.isEmpty {
                Text(verbatim: node.props["value"]?.plain ?? "")
            } else {
                Children(node: node, scope: scope)
            }
        } label: {
            NodeLabel(node: node, scope: scope)
        }
    }
}

/// An element's label: its text, or its children, beside its `icon` (a
/// symbol) or `iconView` (any element, as Settings' colored tiles). The
/// system's `Label`, so a list lines its separators up with the text.
struct NodeLabel: View {
    let node: Node
    let scope: Scope
    var key = "text"

    var body: some View {
        if let view = node.elements("iconView").first {
            Label {
                title
            } icon: {
                NodeView(node: view, scope: scope.child("icon")).equatable()
            }
        } else if let icon = node.string("icon") {
            Label {
                title
            } icon: {
                Image(systemName: Icons.symbol(or: icon, default: "questionmark"))
            }
        } else {
            title
        }
    }

    @ViewBuilder
    private var title: some View {
        if node.children.isEmpty || key != "text" {
            Text(verbatim: node.string(key) ?? "")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Identified.of(node.children)) { child in
                    NodeView(node: child.node, scope: scope.child(child.id)).equatable()
                }
            }
        }
    }
}

/// `ui.share { url = "https://...", label = "Share" }` or `{ text = "..." }`:
/// the system's share sheet, on a tap. What goes out is in plain sight.
struct ShareNode: View {
    let node: Node
    let identifier: String

    var body: some View {
        Group {
            if let url = node.string("url").flatMap(URL.init(string:)) {
                ShareLink(item: url, subject: subject, message: message) { label }
            } else {
                ShareLink(item: node.string("text") ?? "", subject: subject, message: message) { label }
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private var subject: Text? { node.string("subject").map { Text(verbatim: $0) } }
    private var message: Text? { node.string("message").map { Text(verbatim: $0) } }

    @ViewBuilder
    private var label: some View {
        let text = node.string("label") ?? "Share"
        if node.flag("iconOnly") {
            Image(systemName: Icons.symbol(or: node.string("icon"), default: "square.and.arrow.up"))
        } else {
            Label(text, systemImage: Icons.symbol(or: node.string("icon"), default: "square.and.arrow.up"))
        }
    }
}

/// `ui.label { "Settings", icon = "gear" }`: the system's text and icon.
struct LabelNode: View {
    let node: Node
    var scope = Scope(mod: "", path: "", trail: [])

    var body: some View {
        let label = NodeLabel(node: node, scope: scope)
        switch node.string("variant") {
        case "icon": label.labelStyle(.iconOnly)
        case "title": label.labelStyle(.titleOnly)
        case "both": label.labelStyle(.titleAndIcon)
        default: label
        }
    }
}

/// An SF Symbol, with its color and rendering mode.
struct IconNode: View {
    let node: Node
    var key = "name"

    /// A known symbol and nothing else, which `NodeView` draws itself.
    static func isPlain(_ node: Node) -> Bool {
        node.props["rendering"] == nil && !node.flag("fill") && node.props["effect"] == nil && !node.flag("spin")
            && node.props["tint"] == nil && node.string("name").flatMap(Icons.symbol) != nil
    }

    static func image(_ node: Node) -> Image {
        Image(systemName: node.string("name").flatMap(Icons.symbol) ?? "questionmark")
    }

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let symbol = node.string(key).flatMap(Icons.symbol) {
            let image = Image(systemName: symbol)
            let tint = workspace.stylesheet.paint(node.string("tint"), dark: scheme == .dark)
            if rendering == nil, !node.flag("fill"), node.props["effect"] == nil, !node.flag("spin"), tint == nil {
                image
            } else {
                image
                    .symbolRenderingMode(rendering)
                    .symbolVariant(node.flag("fill") ? .fill : .none)
                    .modifier(SymbolEffect(name: key == "name" ? (node.flag("spin") ? "rotate" : node.string("effect")) : nil))
                    .modifier(Ink(color: tint))
            }
        } else {
            WarningMark(text: "no icon named \(node.string(key) ?? "")")
        }
    }

    private var rendering: SymbolRenderingMode? {
        switch node.string("rendering") {
        case "multicolor": .multicolor
        case "hierarchical": .hierarchical
        case "palette": .palette
        case "monochrome": .monochrome
        default: nil
        }
    }
}

/// `effect = "pulse" | "variableColor" | "breathe" | "rotate"`, running.
private struct SymbolEffect: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        switch name {
        case "pulse": content.symbolEffect(.pulse)
        case "variableColor": content.symbolEffect(.variableColor.iterative)
        case "breathe": content.symbolEffect(.breathe)
        case "rotate": content.symbolEffect(.rotate)
        default: content
        }
    }
}

/// A picture from the asset catalog, a symbol, or a URL on a host the app
/// allows, fitted or filled. Luau has no network: a fetch to any URL would
/// let a mod send out whatever it can read, in the address. So only hosts
/// the app lists in `imageHosts` load, over HTTPS; others show a mark.
struct ImageNode: View {
    let node: Node

    @Environment(\.imageHosts) private var hosts

    var body: some View {
        // Moonframe's `src`: a URL, or here the name of an asset.
        let source = node.string("src")
        if let text = node.string("url") ?? source.flatMap({ $0.contains("://") ? $0 : nil }) {
            if let url = URL(string: text), url.scheme == "https", let host = url.host(), hosts.contains(host) {
                AsyncImage(url: url) { image in
                    fitted(image.resizable())
                } placeholder: {
                    ProgressView()
                }
            } else {
                WarningMark(text: "images load only over HTTPS from hosts the app allows")
            }
        } else if let asset = node.string("asset") ?? source {
            fitted(Image(asset).resizable())
        } else {
            Image(systemName: node.string("symbol") ?? "photo")
        }
    }

    @ViewBuilder
    private func fitted(_ image: Image) -> some View {
        if node.string("fit") == "fill" {
            image.scaledToFill().clipped()
        } else {
            image.scaledToFit()
        }
    }
}

/// `ui.progress {}` spins; with `value` (0 to `total`, 1 by default) it fills.
struct ProgressNode: View {
    let node: Node

    var body: some View {
        let label = node.string("label")
        let view = Group {
            if let value = node.number("value") {
                ProgressView(value: value, total: node.number("total") ?? 1) {
                    if let label { Text(verbatim: label) }
                }
            } else {
                ProgressView {
                    if let label { Text(verbatim: label) }
                }
            }
        }
        switch node.string("variant") {
        case "circular": view.progressViewStyle(.circular)
        case "linear": view.progressViewStyle(.linear)
        default: view
        }
    }
}

/// An empty state: `ui.unavailable { "No Sessions", icon = ..., description = ... }`,
/// with any children as its actions. `variant = "search"` is the system's
/// "No results for …".
struct UnavailableNode: View {
    let node: Node
    let scope: Scope

    var body: some View {
        if node.string("variant") == "search" {
            ContentUnavailableView.search(text: node.string("query") ?? "")
        } else {
            ContentUnavailableView {
                Label(node.string("text") ?? "", systemImage: Icons.symbol(or: node.string("icon"), default: "tray"))
            } description: {
                if let description = node.string("description") { Text(verbatim: description) }
            } actions: {
                Children(node: node, scope: scope)
            }
        }
    }
}

/// A view the app registers in Swift, for what Luau can't draw well: a
/// terminal, a web page, a map. Unknown names draw as a warning mark.
struct NativeNode: View {
    let node: Node
    let send: (LuauValue) -> Void
    /// The native view to draw, if not the element's `name`: `ui.terminal`
    /// draws the app's `terminal`.
    var name: String?

    @Environment(\.nativeViews) private var natives

    var body: some View {
        let name = name ?? node.string("name") ?? ""
        if let make = natives.makers[name] {
            make(NativeContext(node: node, send: send))
        } else if self.name != nil {
            PlaceholderNode(node: node)
        } else {
            WarningMark(text: "no native view named \(name)")
        }
    }
}

/// The native views an app offers Luau, by name.
public struct NativeViews: Sendable {
    public typealias Maker = @MainActor @Sendable (NativeContext) -> AnyView
    var makers: [String: Maker] = [:]

    public init() {}

    public mutating func register(_ name: String, _ make: @escaping Maker) {
        makers[name] = make
    }
}

/// What a native view gets: its element, and a way to send its mod messages.
public struct NativeContext {
    public let node: Node
    public let send: (LuauValue) -> Void
}

extension EnvironmentValues {
    @Entry public var nativeViews = NativeViews()
    /// Hosts `ui.image { url = ... }` may load from. None by default.
    @Entry public var imageHosts: Set<String> = []
}
