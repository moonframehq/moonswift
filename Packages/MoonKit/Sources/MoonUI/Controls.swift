import MoonKit
import SwiftUI

/// `{ msg = change, value = value }`, or `change` with `value` added if it's
/// a table already, as Moonframe's controls report.
private func event(_ message: LuauValue?, value: LuauValue) -> LuauValue? {
    switch message {
    case nil: nil
    case .table(let array, var fields)?:
        { fields["value"] = value; return .table(array: array, fields: fields) }()
    case let message?: .fields(["msg": message, "value": value])
    }
}

struct ButtonNode: View {
    let node: Node
    let identifier: String
    let send: (LuauValue) -> Void

    var body: some View {
        let button = Button {
            if let message = node.props["msg"] { send(message) }
        } label: {
            if let icon = node.string("icon") {
                Label(node.string("label") ?? "", systemImage: icon)
            } else {
                Text(node.string("label") ?? "")
            }
        }
        .disabled(node.flag("disabled"))
        .accessibilityIdentifier(identifier)

        switch node.string("variant") {
        case "primary": button.buttonStyle(.borderedProminent)
        case "glass": button.buttonStyle(.glass)
        case "plain": button.buttonStyle(.plain)
        default: button.buttonStyle(.bordered)
        }
    }
}

/// Text fields, toggles and sliders. Each is controlled by the mod: it shows
/// the `value` the view gave and reports changes.
struct ControlNode: View {
    let node: Node
    let identifier: String
    let send: (LuauValue) -> Void

    var body: some View {
        switch node.kind {
        case .input: InputNode(node: node, identifier: identifier, send: send)
        case .toggle:
            Toggle(node.string("label") ?? "", isOn: Binding {
                node.flag("value")
            } set: { value in
                event(node.props["change"], value: .bool(value)).map(send)
            })
            .accessibilityIdentifier(identifier)
        default:
            let low = node.number("min") ?? 0
            let high = max(node.number("max") ?? 1, low + .ulpOfOne)
            Slider(
                value: Binding {
                    node.number("value") ?? low
                } set: { value in
                    event(node.props["change"], value: .number(value)).map(send)
                },
                in: low...high,
                step: node.number("step") ?? (high - low) / 100
            )
            .accessibilityIdentifier(identifier)
        }
    }
}

private struct InputNode: View {
    let node: Node
    let identifier: String
    let send: (LuauValue) -> Void

    @State private var text = ""

    var body: some View {
        TextField(node.string("placeholder") ?? "", text: $text)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier(identifier)
            .onChange(of: node.string("value") ?? "", initial: true) { _, value in
                if value != text { text = value }
            }
            .onChange(of: text) { _, value in
                if value != node.string("value") ?? "" {
                    event(node.props["change"], value: .string(value)).map(send)
                }
            }
            .onSubmit {
                event(node.props["submit"], value: .string(text)).map(send)
            }
    }
}
