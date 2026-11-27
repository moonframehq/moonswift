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

/// One of a mod's `views`, drawn when SwiftUI shows it: a list's row or a
/// pushed screen. It follows the mod's generation, and its tree is compared
/// by digest, so a row whose look didn't change costs one Luau call.
struct PartView: View {
    let view: String
    let key: LuauValue
    let scope: Scope

    @Environment(Workspace.self) private var workspace

    var body: some View {
        let node = workspace.part(view, key: key, of: scope.mod)
        NodeView(node: node, scope: scope).equatable()
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
            ForEach(workspace.mods(in: node.string("name") ?? ""), id: \.self) { name in
                ModView(name: name, trail: scope.trail + [crumb])
            }
        case .mount:
            ModView(name: node.string("mod") ?? "", trail: scope.trail + [crumb])
        // Bare: wrapped in modifiers, a stack no longer treats it as a spacer
        // and it stretches both ways.
        case .spacer:
            Spacer(minLength: node.number("min").map { CGFloat($0) } ?? 0)
        // The system's own containers: their look is the platform's, and a
        // box around them would break what they expect of their children.
        case .stack, .tabs, .tab, .split, .list, .form, .section:
            container
                .modifier(Decorations(node: node, scope: scope, send: send))
                .modifier(Tracked(tracker: tracker, scope: scope, label: node.label))
        default:
            styled(workspace.stylesheet.resolve(node, hovered: hovered))
        }
    }

    var crumb: Crumb {
        Crumb(mod: scope.mod, path: scope.path, label: node.label)
    }

    private func styled(_ style: StyleRule) -> some View {
        let sheet = workspace.stylesheet
        return content(style)
            .modifier(Box(style: style, node: node, sheet: sheet, dark: dark, fills: fills))
            .modifier(Tap(node: node, send: send))
            .modifier(Hover(on: sheet.hovers(Stylesheet.selectors(of: node)), hovered: $hovered))
            .modifier(Decorations(node: node, scope: scope, send: send))
            .modifier(Tracked(tracker: tracker, scope: scope, label: node.label))
    }

    private var fills: Bool {
        node.growsWide || node.kind == .panel
    }

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

    var body: some View {
        ForEach(Identified.of(node.children)) { child in
            NodeView(node: child.node, scope: scope.child(child.id)).equatable()
                .tag(child.node.props["key"] ?? .string(child.id))
        }
        if let rows = node.lazyRows {
            LazyRows(keys: rows.keys, view: rows.view, scope: scope)
        }
    }
}

/// Rows a mod draws on demand: SwiftUI asks only for those it shows.
struct LazyRows: View {
    let keys: [LuauValue]
    let view: String
    let scope: Scope

    var body: some View {
        ForEach(keys, id: \.self) { key in
            PartView(view: view, key: key, scope: scope.child("\(view):\(key.summary)"))
                .tag(key)
        }
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
                maxWidth: fills ? .infinity : nil,
                maxHeight: node.growsTall ? .infinity : nil,
                alignment: frameAlignment
            )
            .foregroundStyle(sheet.paint(style.color, dark: dark).map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .background {
                if let background = sheet.paint(style.background, dark: dark) {
                    shape.fill(background)
                }
            }
            .overlay {
                if let border = sheet.paint(style.border, dark: dark) {
                    shape.strokeBorder(border, lineWidth: 1)
                }
            }
            .modifier(Glass(on: style.glass ?? false, shape: shape))
            .modifier(Shadow(radius: style.shadow))
            .opacity(style.opacity ?? 1)
            .padding(EdgeInsets(style.margin))
    }

    private var frameAlignment: Alignment { .topLeading }
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
