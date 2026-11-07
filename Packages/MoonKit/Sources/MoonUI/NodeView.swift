import MoonKit
import SwiftUI

/// Where an element sits: its mod, its path in that mod's tree, and the
/// elements around it, across mods, outermost first.
public struct Scope: Equatable, Sendable {
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
public struct Crumb: Equatable, Hashable, Sendable {
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
/// in its place if it never loaded.
struct ModView: View {
    let name: String
    var trail: [Crumb] = []

    @Environment(Workspace.self) private var workspace

    var body: some View {
        if let tree = workspace.trees[name] {
            NodeView(node: tree, scope: Scope(mod: name, path: "", trail: trail))
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

struct WarningMark: View {
    let text: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .help(text)
    }
}

/// Draws one element and, through itself, everything under it.
struct NodeView: View {
    let node: Node
    let scope: Scope

    @Environment(Workspace.self) private var workspace
    @Environment(\.elementTracker) private var tracker
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    private var dark: Bool { scheme == .dark }

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
            Spacer(minLength: 0)
        default:
            styled(workspace.stylesheet.resolve(node, hovered: hovered))
        }
    }

    private var crumb: Crumb {
        Crumb(mod: scope.mod, path: scope.path, label: node.label)
    }

    private func styled(_ style: StyleRule) -> some View {
        let sheet = workspace.stylesheet
        let shape = RoundedRectangle(cornerRadius: style.radius ?? 0, style: .continuous)
        return content(style)
            .padding(EdgeInsets(style.padding))
            .frame(
                width: node.number("width").map { CGFloat($0) },
                height: node.number("height").map { CGFloat($0) },
                alignment: .topLeading
            )
            .frame(
                maxWidth: fills ? .infinity : nil,
                maxHeight: node.growsTall ? .infinity : nil,
                alignment: .topLeading
            )
            .foregroundStyle(sheet.paint(style.color, dark: dark).map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .background(sheet.paint(style.background, dark: dark) ?? .clear, in: shape)
            .overlay {
                if let border = sheet.paint(style.border, dark: dark) {
                    shape.strokeBorder(border, lineWidth: 1)
                }
            }
            .modifier(Glass(on: style.glass ?? false, shape: shape))
            .shadow(color: .black.opacity(style.shadow == nil ? 0 : 0.18), radius: style.shadow ?? 0, y: (style.shadow ?? 0) / 3)
            .opacity(style.opacity ?? 1)
            .padding(EdgeInsets(style.margin))
            .modifier(Tap(node: node, send: send))
            .help(node.string("tooltip") ?? "")
            .onHover { hovered = $0 }
            .modifier(Tracked(tracker: tracker, scope: scope, label: node.label))
    }

    private var fills: Bool {
        node.growsWide || node.kind == .panel
    }

    @ViewBuilder
    private func content(_ style: StyleRule) -> some View {
        switch node.kind {
        case .row:
            HStack(alignment: node.verticalAlignment, spacing: node.spacing) { children }
        case .column:
            scrolling {
                VStack(alignment: node.horizontalAlignment, spacing: node.spacing) { children }
            }
        case .panel:
            scrolling {
                VStack(alignment: .leading, spacing: node.spacing) {
                    if let title = node.string("title") { panelTitle(title) }
                    children
                }
            }
        case .divider:
            Divider()
        case .text:
            Text(node.string("text") ?? "")
                .font(font(style))
                .contentTransition(node.flag("numeric") ? .numericText() : .identity)
                .accessibilityIdentifier(identifier)
        case .badge:
            Text(node.string("text") ?? "").font(font(style))
        case .icon:
            Image(systemName: node.string("name") ?? "questionmark").font(font(style))
        case .button:
            ButtonNode(node: node, identifier: identifier, send: send)
        case .input, .toggle, .slider:
            ControlNode(node: node, identifier: identifier, send: send)
        case .invalid:
            WarningMark(text: node.problem ?? "bad element")
        case .region, .mount, .spacer:
            EmptyView()
        }
    }

    /// Every element is findable by `id`, or by where it sits.
    private var identifier: String {
        node.string("id") ?? scope.key
    }

    private var children: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { index, child in
            NodeView(node: child, scope: scope.child(child.identity(at: index)))
                .id(child.identity(at: index))
        }
    }

    @ViewBuilder
    private func scrolling(@ViewBuilder _ stack: () -> some View) -> some View {
        if node.flag("scroll") {
            ScrollView { stack().frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            stack()
        }
    }

    private func panelTitle(_ title: String) -> some View {
        let style = workspace.stylesheet.resolve(selector: "panel-title")
        return Text(title.uppercased())
            .font(font(style))
            .foregroundStyle(workspace.stylesheet.paint(style.color, dark: dark) ?? .secondary)
    }

    private func font(_ style: StyleRule) -> Font {
        .system(size: style.size ?? 13, weight: Font.Weight(name: style.weight) ?? .regular)
    }

    /// Controls report to their own mod unless `to` names another.
    private func send(_ message: LuauValue) {
        workspace.send(message, to: node.string("to") ?? scope.mod)
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
        } else {
            content
        }
    }
}
