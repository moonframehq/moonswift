import MoonKit
import SwiftUI

/// Where an element sits: its mod, its path in that mod's tree, and the
/// elements around it, across mods, outermost first.
nonisolated public struct Scope: Equatable, Hashable, Sendable {
    public let mod: String
    public let path: String
    public let trail: [Crumb]

    public var key: String { "\(mod):\(path)" }

    func child(_ identity: String) -> Scope {
        Scope(mod: mod, path: path.isEmpty ? identity : "\(path)/\(identity)", trail: trail)
    }

    func within(_ crumb: Crumb) -> Scope {
        Scope(mod: mod, path: path, trail: trail + [crumb])
    }
}

/// One element around a pick.
nonisolated public struct Crumb: Equatable, Hashable, Sendable {
    public let mod: String
    public let path: String
    public let label: String

    public var key: String { "\(mod):\(path)" }

    public init(mod: String, path: String, label: String) {
        self.mod = mod
        self.path = path
        self.label = label
    }
}

/// An element where it landed on screen.
public struct PlacedElement: Equatable, Sendable {
    public let scope: Scope
    public let label: String
    /// In the canvas.
    public let frame: CGRect
    /// In the window, top left origin.
    public let windowFrame: CGRect
}

/// Told where every element lands. Nothing listens in a store build.
public protocol ElementTracker: AnyObject {
    func place(_ element: PlacedElement)
    func remove(_ key: String)
}

extension EnvironmentValues {
    @Entry public var elementTracker: (any ElementTracker)?
}

/// A mod's tree, its warning mark while its last edit is broken, and a note
/// in its place if it never loaded. It follows that mod's drawing alone, so
/// another mod's update doesn't reach it.
struct ModView: View {
    let name: String
    var trail: [Crumb] = []

    @Environment(Workspace.self) private var workspace

    var body: some View {
        if let tree = workspace.drawing(of: name).tree {
            NodeView(node: tree, scope: Scope(mod: name, path: "", trail: trail))
                .equatable()
                .overlay(alignment: .topTrailing) {
                    if let problem = workspace.problem(of: name) {
                        WarningMark(text: problem.message).padding(6)
                    }
                }
        } else {
            ContentUnavailableView(
                "\(name) did not load",
                systemImage: "exclamationmark.triangle",
                description: Text(workspace.problem(of: name)?.message ?? "No such mod.")
            )
        }
    }
}

/// What a function in a mod's tree draws, when SwiftUI shows it: a list's
/// `row(i)` or a stack's `screen(route)`. It follows the mod's generation,
/// and its tree is compared by digest, so a row whose look didn't change
/// costs one Luau call.
struct PartView: View {
    let function: Int
    let key: LuauValue
    let scope: Scope

    @Environment(Workspace.self) private var workspace

    var body: some View {
        let node = workspace.part(function, key: key, of: scope.mod)
        // Exactly one view, whatever the element: a lazy list must know
        // each row is one view without asking, or it builds them all.
        VStack(spacing: 0) {
            NodeView(node: node, scope: scope).equatable()
        }
        .modifier(RowTraits(node: node, scope: scope))
    }
}

struct WarningMark: View {
    let text: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .help(text)
    }
}

/// Draws one element and, through itself, everything under it. Equal by
/// digest: SwiftUI skips a subtree whose tree didn't change.
struct NodeView: View, Equatable {
    let node: Node
    let scope: Scope

    @Environment(Workspace.self) var workspace
    @Environment(\.elementTracker) private var tracker
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    nonisolated static func == (lhs: NodeView, rhs: NodeView) -> Bool {
        lhs.node.digest == rhs.node.digest && lhs.scope == rhs.scope
    }

    var dark: Bool { scheme == .dark }

    var body: some View {
        switch node.kind {
        // These place other mods' trees and have no box of their own.
        case .region:
            // With a `direction`, as in Moonframe, a stack of its own.
            switch node.string("direction") {
            case "row": HStack(spacing: node.spacing) { regionMods }
            case "column": VStack(alignment: .leading, spacing: node.spacing) { regionMods }
            default: regionMods
            }
        case .mount:
            ModView(name: node.string("mod") ?? "", trail: scope.trail + [crumb])
        // Bare: wrapped in modifiers, a stack no longer treats it as a spacer
        // and it stretches both ways.
        case .spacer:
            Spacer(minLength: node.number("min").map { CGFloat($0) } ?? 0)
        // The system's own containers: their look is the platform's, and a
        // box around them would break what they expect of their children.
        case .stack, .tabs, .tab, .split, .list, .form, .section, .hsplit, .vsplit:
            container
                .accessibilityIdentifier(identifier)
                .modifier(Decorations(node: node, scope: scope, send: send))
                .modifier(Tracked(tracker: tracker, scope: scope, label: node.label))
        default:
            styled(workspace.stylesheet(for: scope.mod).resolve(node, hovered: hovered))
        }
    }

    private var regionMods: some View {
        ForEach(workspace.mods(in: node.string("name") ?? ""), id: \.self) { name in
            ModView(name: name, trail: scope.trail + [crumb])
        }
    }

    var crumb: Crumb {
        Crumb(mod: scope.mod, path: scope.path, label: node.label)
    }

    private func styled(_ style: StyleRule) -> some View {
        let sheet = workspace.stylesheet(for: scope.mod)
        return content(style)
            .modifier(Box(style: style, node: node, sheet: sheet, dark: dark, fills: fills, scope: scope))
            .modifier(Tap(node: node, send: send))
            .modifier(Hover(on: sheet.hovers(Stylesheet.selectors(of: node)), hovered: $hovered))
            .modifier(Decorations(node: node, scope: scope, send: send))
            .modifier(Tracked(tracker: tracker, scope: scope, label: node.label))
    }

    /// Whether it takes its parent's width: it grows that way, it is a
    /// panel, or a Moonframe column stretches it (its containers; a text or
    /// button keeps its own width) and it doesn't `hug`.
    private var fills: Bool {
        node.growsWide || node.kind == .panel
            || (node.across && Self.stretchable.contains(node.kind) && !node.flag("hug") && node.props["self_align"] == nil)
    }

    private static let stretchable: Set<Node.Kind> = [.row, .column, .panel, .pane, .item, .input, .markdown, .list]

    /// Every element is findable by `id`, or by where it sits.
    var identifier: String {
        node.string("id") ?? scope.key
    }

    func font(_ style: StyleRule) -> Font? {
        Font(style)
    }

    /// Controls report to their own mod unless `to` names another.
    func send(_ message: LuauValue) {
        workspace.send(message, to: node.string("to") ?? scope.mod)
    }
}

/// A node's children, each by its identity, and its lazy rows after them.
struct Children: View {
    let node: Node
    let scope: Scope

    @Environment(Workspace.self) private var workspace
    /// In a list: each child is a row, with the row's chrome and tag. Never
    /// elsewhere, as a spacer wrapped in modifiers stops being one.
    var rows = false

    private func send(_ message: LuauValue) {
        workspace.send(message, to: node.string("to") ?? scope.mod)
    }

    var body: some View {
        if rows {
            let children = Identified.of(node.children)
            let keys = children.map { $0.node.props["key"] ?? .string($0.id) }
            ForEach(children) { child in
                NodeView(node: child.node, scope: scope.child(child.id)).equatable()
                    .modifier(RowTraits(node: child.node, scope: scope.child(child.id)))
                    .tag(child.node.props["key"] ?? .string(child.id))
            }
            .onMove(perform: RowEditing(node: node, keys: keys, send: send).move)
            .onDelete(perform: RowEditing(node: node, keys: keys, send: send).delete)
        } else {
            // Moonframe's `between`, as spacers the stack shares out; `center`
            // and `end` place the stack in its box instead (`Box`).
            let justify = node.kind == .row || node.kind == .column ? node.string("justify") : nil
            let children = Identified.of(node.children)
            // A floated child is drawn over the stack instead (`Floats`).
            ForEach(children.filter { $0.node.props["float"] == nil }) { child in
                if justify == "between", child.id != children.first?.id { Spacer(minLength: 0) }
                // A stack sees a spacer only bare, not inside another view.
                if child.node.kind == .spacer {
                    Spacer(minLength: child.node.number("min").map { CGFloat($0) } ?? 0)
                } else {
                    NodeView(node: child.node, scope: scope.child(child.id)).equatable()
                }
            }
        }
        if let rows = node.lazyRows {
            LazyRows(count: rows.count, function: rows.function, scope: scope, owner: node)
        }
    }
}

/// Rows a mod draws on demand, `row(i)` for `i` from 1 to `count`: SwiftUI
/// asks only for those it shows.
struct LazyRows: View {
    let count: Int
    let function: Int
    let scope: Scope
    /// The list or section the rows are in, for `move` and `delete`.
    var owner: Node?

    @Environment(Workspace.self) private var workspace

    /// The rows' keys, their positions, made only for a list that edits.
    private var editing: RowEditing? {
        guard let owner, owner.props["move"] != nil || owner.props["delete"] != nil else { return nil }
        return RowEditing(node: owner, keys: (0..<count).map { .number(Double($0 + 1)) }, send: send)
    }

    var body: some View {
        let editing = editing
        ForEach(1..<(count + 1), id: \.self) { index in
            PartView(function: function, key: .number(Double(index)), scope: scope.child("row:\(index)"))
                .tag(LuauValue.number(Double(index)))
        }
        .onMove(perform: editing?.move)
        .onDelete(perform: editing?.delete)
    }

    private func send(_ message: LuauValue) {
        workspace.send(message, to: owner?.string("to") ?? scope.mod)
    }
}

/// `move = msg` and `delete = msg` on a list or section: dragging rows in
/// edit mode sends `{ msg = move, keys = { ... }, to = n }`, the position
/// before which they land (1-based); swiping delete sends
/// `{ msg = delete, keys = { ... } }`. The mod changes its rows.
struct RowEditing {
    let node: Node
    let keys: [LuauValue]
    let send: (LuauValue) -> Void

    var move: ((IndexSet, Int) -> Void)? {
        guard let message = node.props["move"] else { return nil }
        return { from, to in
            let moved = from.filter { $0 < keys.count }.map { keys[$0] }
            event(message, value: .table(array: moved, fields: [:]))
                .map { Self.adding(["keys": .table(array: moved, fields: [:]), "to": .number(Double(to + 1))], to: $0) }
                .map(send)
        }
    }

    var delete: ((IndexSet) -> Void)? {
        guard let message = node.props["delete"] else { return nil }
        return { offsets in
            let gone = offsets.filter { $0 < keys.count }.map { keys[$0] }
            event(message, value: .table(array: gone, fields: [:]))
                .map { Self.adding(["keys": .table(array: gone, fields: [:])], to: $0) }
                .map(send)
        }
    }

    private static func adding(_ extra: [String: LuauValue], to message: LuauValue) -> LuauValue {
        guard case .table(let array, var fields) = message else { return message }
        fields.merge(extra) { _, new in new }
        return .table(array: array, fields: fields)
    }
}

/// Children with identities unique among their siblings: a repeated `key`
/// gets its position added, so SwiftUI never sees two alike.
struct Identified: Identifiable {
    let id: String
    let node: Node

    static func of(_ nodes: [Node]) -> [Identified] {
        var seen: Set<String> = []
        return nodes.enumerated().map { index, node in
            var id = node.identity(at: index)
            if !seen.insert(id).inserted { id += "#\(index)" }
            return Identified(id: id, node: node)
        }
    }
}

/// The box rules draw: padding, size, colors, corners, glass and shadow,
/// each only if set, so a plain element costs no extra views.
private struct Box: ViewModifier {
    let style: StyleRule
    let node: Node
    let sheet: Stylesheet
    let dark: Bool
    let fills: Bool
    let scope: Scope

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.radius ?? 0, style: .continuous)
        content
            .padding(EdgeInsets(style.padding))
            .frame(
                width: node.number("width").map { CGFloat($0) },
                height: node.number("height").map { CGFloat($0) },
                alignment: frameAlignment
            )
            .frame(
                maxWidth: fills || selfAlign != nil ? node.number("max_width").map { CGFloat($0) } ?? .infinity
                    : node.number("max_width").map { CGFloat($0) },
                maxHeight: node.growsTall ? node.number("max_height").map { CGFloat($0) } ?? .infinity
                    : node.number("max_height").map { CGFloat($0) },
                alignment: selfAlign ?? frameAlignment
            )
            .modifier(Ink(color: sheet.paint(style.color, dark: dark)))
            .background {
                if let background = sheet.paint(style.background, dark: dark) {
                    shape.fill(background)
                }
            }
            .overlay(alignment: edgeAlignment) {
                if let edges = style.edges, edges != "none",
                   let border = sheet.paint(style.border ?? "border", dark: dark) {
                    let width = style.borderWidth ?? 1
                    switch edges {
                    case "top", "bottom": border.frame(height: width)
                    case "left", "right": border.frame(width: width)
                    default: shape.strokeBorder(border, lineWidth: width)
                    }
                }
                // Children with `float`, over the box rather than in it.
                if node.hasFloats {
                    Floats(node: node, scope: scope)
                }
            }
            .modifier(Glass(on: style.glass ?? false, shape: shape))
            .modifier(Shadow(radius: style.shadow))
            .opacity(style.opacity ?? 1)
            .modifier(Turn(degrees: node.number("rotate")))
            .modifier(Fixed(axis: node.props["fixed"] ?? shrinkless))
            .padding(EdgeInsets(style.margin))
    }

    /// Moonframe's `self_align` in a column: where it sits across the
    /// width, in a box as wide as the column.
    private var selfAlign: Alignment? {
        guard node.axis == .vertical, let align = node.string("self_align"), align != "stretch" else { return nil }
        return align == "end" ? .trailing : align == "center" ? .center : .leading
    }

    /// Moonframe's `shrink = false`: its own size along its parent's axis.
    private var shrinkless: LuauValue? {
        guard node.props["shrink"] == .bool(false) else { return nil }
        return switch node.axis {
        case .horizontal: .string("x")
        case .vertical: .string("y")
        case nil: .bool(true)
        }
    }

    /// Where a one-edge border goes.
    private var edgeAlignment: Alignment {
        switch style.edges {
        case "top": .top
        case "bottom": .bottom
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }

    /// Where the content sits in a box bigger than it: by the column's or
    /// row's `align`, from the top leading corner otherwise.
    private var frameAlignment: Alignment {
        let justify = node.string("justify")
        switch node.kind {
        case .column:
            return Alignment(horizontal: node.horizontalAlignment, vertical: justify == "end" ? .bottom : justify == "center" ? .center : .top)
        case .row:
            return Alignment(horizontal: justify == "end" ? .trailing : justify == "center" ? .center : .leading, vertical: node.verticalAlignment)
        default: return .topLeading
        }
    }
}

/// A color only when one is set: otherwise the system's own styling stays,
/// as a labeled row's secondary value.
private struct Ink: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

/// `fixed = "y"` (or `"x"`, or `true` for both): the element keeps its ideal
/// size that way, as a row whose side bar should be as tall as its text.
private struct Fixed: ViewModifier {
    let axis: LuauValue?

    func body(content: Content) -> some View {
        switch axis {
        case .string("y")?: content.fixedSize(horizontal: false, vertical: true)
        case .string("x")?: content.fixedSize(horizontal: true, vertical: false)
        case .bool(true)?: content.fixedSize()
        default: content
        }
    }
}

private struct Turn: ViewModifier {
    let degrees: Double?

    func body(content: Content) -> some View {
        if let degrees { content.rotationEffect(.degrees(degrees)) } else { content }
    }
}

private struct Shadow: ViewModifier {
    let radius: Double?

    func body(content: Content) -> some View {
        if let radius {
            content.shadow(color: .black.opacity(0.18), radius: radius, y: radius / 3)
        } else {
            content
        }
    }
}

/// Follows the pointer only where a `:hover` rule could use it.
private struct Hover: ViewModifier {
    let on: Bool
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        if on {
            content.onHover { hovered = $0 }
        } else {
            content
        }
    }
}

private struct Tracked: ViewModifier {
    let tracker: (any ElementTracker)?
    let scope: Scope
    let label: String

    func body(content: Content) -> some View {
        if let tracker {
            content
                .onGeometryChange(for: [CGRect].self) {
                    [$0.frame(in: .named(MoonCanvas.space)), $0.frame(in: .global)]
                } action: { frames in
                    tracker.place(PlacedElement(scope: scope, label: label, frame: frames[0], windowFrame: frames[1]))
                }
                .onDisappear { tracker.remove(scope.key) }
        } else {
            content
        }
    }
}

private struct Glass<S: Shape>: ViewModifier {
    let on: Bool
    let shape: S

    func body(content: Content) -> some View {
        if on {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}

/// `msg` on anything but a control makes it a button: clickable from an
/// inactive window, and reachable by keyboard and VoiceOver.
private struct Tap: ViewModifier {
    let node: Node
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let message = node.props["msg"], node.kind != .button {
            Button {
                send(message)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(node.string("id") ?? "")
            .help(node.string("tooltip") ?? "")
        } else if let tooltip = node.string("tooltip") {
            content.help(tooltip)
        } else {
            content
        }
    }
}
