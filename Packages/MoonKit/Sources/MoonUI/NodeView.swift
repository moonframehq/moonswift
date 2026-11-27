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
        // Exactly one view, whatever the element, a region too: a lazy list
        // must know each row is one view without asking, or it builds them
        // all, and a branch here would make it ask.
        RowView(node: node, scope: scope)
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
    /// Set by `Hovering`, for the few elements a `:hover` rule styles.
    var hover: Binding<Bool>?

    nonisolated static func == (lhs: NodeView, rhs: NodeView) -> Bool {
        lhs.node.digest == rhs.node.digest && lhs.scope == rhs.scope
    }

    var dark: Bool { scheme == .dark }

    /// The element as exactly one view. SwiftUI otherwise can't tell from
    /// the type how many views an element makes, so a stack builds each
    /// child's list of views to find out, on every row that scrolls in.
    /// Regions, which place a view per mod, stay many.
    @ViewBuilder
    static func one(_ node: Node, _ scope: Scope) -> some View {
        if node.kind == .region {
            NodeView(node: node, scope: scope).equatable()
        } else {
            _UnaryViewAdaptor(NodeView(node: node, scope: scope).equatable())
        }
    }

    /// One erased view, chosen here in Swift: the common elements are a
    /// concrete view each, so SwiftUI has no branch to track for them.
    var body: AnyView {
        if Self.boxed.contains(node.kind), hover == nil {
            let look = Look(node: node, sheet: sheet, dark: dark, hovered: false)
            if !look.hovers, isFlat(look), let kind = fast(look) {
                return erased(kind, look)
            }
        }
        return AnyView(general)
    }

    /// The elements drawn in a box of their own, not placed bare.
    private static let boxed: Set<Node.Kind> = Set(Node.Kind.allCases).subtracting([
        .region, .mount, .spacer, .stack, .tabs, .tab, .split, .list, .form, .section, .hsplit, .vsplit,
    ])

    /// The stylesheet of the element's mod.
    var sheet: Stylesheet { workspace.stylesheet(for: scope.mod) }

    @ViewBuilder
    private var general: some View {
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
            let look = Look(node: node, sheet: sheet, dark: dark, hovered: hover?.wrappedValue ?? false)
            if look.hovers, hover == nil {
                Hovering(node: node, scope: scope)
            } else if isFlat(look) {
                flat(look)
            } else if isFlat(look, menu: true) {
                // A row's root with its context menu: the box, tap and
                // decorations it doesn't use stay out of it.
                flat(look).contextMenu {
                    MenuItems(nodes: node.elements("context"), scope: scope.child("context"), send: send)
                }
            } else {
                styled(look)
            }
        }
    }

    private var regionMods: some View {
        ForEach(workspace.mods(in: node.string("name") ?? ""), id: \.self) { name in
            ModView(name: name, trail: scope.trail + [crumb])
        }
    }

    /// Most elements of a row: a text or icon with a font and a color, a
    /// stack with a gap and padding. They take the short way, one static
    /// chain each: every optional modifier is a branch SwiftUI tracks on
    /// its own, and a row of 25 elements made hundreds of them.
    private func isFlat(_ look: Look, menu: Bool = false) -> Bool {
        look.uses.isSubset(of: [.padding, .stretch]) && !look.hovers && tracker == nil && !Tap.used(by: node)
            && (menu ? Decorations.menuOnly(node) : !Decorations.used(by: node))
    }

    /// Branches nested straight in each other are one to SwiftUI.
    @ViewBuilder
    private func flat(_ look: Look) -> some View {
        let padded = look.uses.contains(.padding), stretched = look.uses.contains(.stretch)
        let content = content(look.style)
        let maxWidth: CGFloat? = look.wide ? .infinity : nil, maxHeight: CGFloat? = look.tall ? .infinity : nil
        if padded, stretched {
            inked(look, content.padding(look.padding).frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: look.alignment))
        } else if padded {
            inked(look, content.padding(look.padding))
        } else if stretched {
            inked(look, content.frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: look.alignment))
        } else {
            inked(look, content)
        }
    }

    @ViewBuilder
    private func inked(_ look: Look, _ view: some View) -> some View {
        if let color = look.color { view.foregroundStyle(color) } else { view }
    }

    var crumb: Crumb {
        Crumb(mod: scope.mod, path: scope.path, label: node.label)
    }

    private func styled(_ look: Look) -> some View {
        content(look.style)
            .modifier(Box(look: look))
            .modifier(Tap(node: node, send: send))
            .modifier(Hover(binding: hover))
            .modifier(Decorations(node: node, scope: scope, send: send))
            .modifier(Tracked(tracker: tracker, scope: scope, label: node.label))
    }

    /// Every element is findable by `id`, or by where it sits.
    var identifier: String {
        node.string("id") ?? scope.key
    }

    func font(_ style: StyleRule) -> Font? {
        Fonts.font(style)
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
                RowView(node: child.node, scope: scope.child(child.id))
                    .modifier(RowTraits(node: child.node, scope: scope.child(child.id)))
                    .tag(child.node.props["key"] ?? .string(child.id))
            }
            .onMove(perform: RowEditing(node: node, keys: keys, send: send).move)
            .onDelete(perform: RowEditing(node: node, keys: keys, send: send).delete)
        } else {
            // Moonframe's `justify`, as spacers the stack shares out.
            let justify = node.kind == .row || node.kind == .column ? node.string("justify") : nil
            let children = Identified.of(node.children)
            if justify == "center" || justify == "end" { Spacer(minLength: 0) }
            ForEach(children) { child in
                if justify == "between", child.id != children.first?.id { Spacer(minLength: 0) }
                // A stack sees a spacer only bare, not inside another view.
                if child.node.kind == .spacer {
                    Spacer(minLength: child.node.number("min").map { CGFloat($0) } ?? 0)
                } else {
                    NodeView.one(child.node, scope.child(child.id))
                }
            }
            if justify == "center" { Spacer(minLength: 0) }
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

/// Keeps whether the pointer is over an element a `:hover` rule styles:
/// state no other element pays for.
private struct Hovering: View {
    let node: Node
    let scope: Scope

    @State private var hovered = false

    var body: some View {
        NodeView(node: node, scope: scope, hover: $hovered)
    }
}

/// Follows the pointer only where a `:hover` rule could use it.
private struct Hover: ViewModifier {
    let binding: Binding<Bool>?

    func body(content: Content) -> some View {
        if let binding {
            content.onHover { binding.wrappedValue = $0 }
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

/// `msg` on anything but a control makes it a button: clickable from an
/// inactive window, and reachable by keyboard and VoiceOver.
private struct Tap: ViewModifier {
    let node: Node
    let send: (LuauValue) -> Void

    static func used(by node: Node) -> Bool {
        (node.props["msg"] != nil && node.kind != .button) || node.props["tooltip"] != nil
    }

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
