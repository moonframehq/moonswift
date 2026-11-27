import MoonKit
import SwiftUI

/// `ui.menu { "Sort", icon = "arrow.up.arrow.down", <items> }`: a button that
/// opens its items. With `msg`, a tap sends it and a long press opens the menu.
struct MenuNode: View {
    let node: Node
    let scope: Scope
    let identifier: String
    let send: (LuauValue) -> Void

    var body: some View {
        Group {
            if let primary = node.props["msg"] {
                Menu {
                    MenuItems(nodes: node.children, scope: scope, send: send)
                } label: {
                    ButtonLabel(node: node)
                } primaryAction: {
                    send(primary)
                }
            } else {
                Menu {
                    MenuItems(nodes: node.children, scope: scope, send: send)
                } label: {
                    ButtonLabel(node: node)
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

/// Elements as menu items: buttons, dividers, menus inside menus, pickers,
/// toggles and titled sections. Context menus and toolbars use these too.
struct MenuItems: View {
    let nodes: [Node]
    let scope: Scope
    let send: (LuauValue) -> Void

    var body: some View {
        ForEach(Identified.of(nodes)) { item in
            MenuItem(node: item.node, scope: scope.child(item.id), send: send)
        }
    }
}

private struct MenuItem: View {
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    @Environment(Workspace.self) private var workspace

    var body: some View {
        switch node.kind {
        case .button:
            Button(role: node.role) {
                if let message = node.props["msg"] { reply(message) }
            } label: {
                ButtonLabel(node: node)
            }
            .disabled(node.flag("disabled"))
            .accessibilityIdentifier(node.string("id") ?? scope.key)
        case .divider:
            Divider()
        case .menu:
            MenuNode(node: node, scope: scope, identifier: node.string("id") ?? scope.key, send: reply)
        case .section:
            Section(node.string("title") ?? "") {
                MenuItems(nodes: node.children, scope: scope, send: send)
            }
        case .picker, .toggle:
            ControlNode(node: node, identifier: node.string("id") ?? scope.key, send: reply)
        case .link:
            LinkNode(node: node, scope: scope, identifier: node.string("id") ?? scope.key, send: reply)
        default:
            NodeView(node: node, scope: scope).equatable()
        }
    }

    private func reply(_ message: LuauValue) {
        if let to = node.string("to") {
            workspace.send(message, to: to)
        } else {
            send(message)
        }
    }
}
