import MoonKit
import SwiftUI

/// `{ msg = change, value = value }`, or `change` with `value` added if it's
/// a table already, as Moonframe's controls report.
func event(_ message: LuauValue?, value: LuauValue) -> LuauValue? {
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
        let button = Button(role: node.role) {
            if let message = node.props["msg"] { send(message) }
        } label: {
            ButtonLabel(node: node)
        }
        .disabled(node.flag("disabled"))
        .accessibilityIdentifier(identifier)
        .controlSize(node.controlSize)
        .modifier(Shortcut(text: node.string("shortcut")))

        switch node.string("variant") {
        case "primary": button.buttonStyle(.borderedProminent)
        // Moonframe's variants.
        case "ghost": button.buttonStyle(.borderless)
        case "outline", "normal": button.buttonStyle(.bordered)
        case "danger": button.buttonStyle(.bordered).tint(.red)
        case "glass": button.buttonStyle(.glass)
        case "prominentGlass": button.buttonStyle(.glassProminent)
        case "plain": button.buttonStyle(.plain)
        case "borderless": button.buttonStyle(.borderless)
        case "bordered": button.buttonStyle(.bordered)
        // In lists, menus and toolbars the system's own look fits best.
        case nil where node.props["place"] != nil: button
        default: button.buttonStyle(.bordered)
        }
    }
}

/// A button's text and icon, as menus, toolbars and swipes show them.
struct ButtonLabel: View {
    let node: Node

    var body: some View {
        if let icon = node.string("icon") {
            if node.string("label") == nil {
                Image(systemName: Icons.symbol(or: icon, default: "questionmark"))
            } else {
                Label(node.string("label") ?? "", systemImage: Icons.symbol(or: icon, default: "questionmark"))
            }
        } else {
            Text(verbatim: node.string("label") ?? "")
        }
    }
}

extension Node {
    /// `role = "destructive"` or `"cancel"`, and `"confirm"` where it is.
    var role: ButtonRole? {
        switch string("role") {
        case "destructive": .destructive
        case "cancel": .cancel
        case "confirm": .confirm
        case "close": .close
        default: nil
        }
    }

    var controlSize: ControlSize {
        if flag("small") { return .small }
        return switch string("size") {
        case "mini": .mini
        case "small": .small
        case "large": .large
        case "extraLarge": .extraLarge
        default: .regular
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
        case .input, .secure, .editor: InputNode(node: node, identifier: identifier, send: send)
        case .stepper: StepperNode(node: node, identifier: identifier, send: send)
        case .picker: PickerNode(node: node, identifier: identifier, send: send)
        case .toggle:
            let toggle = Toggle(isOn: Binding {
                node.flag("value")
            } set: { value in
                event(node.props["change"], value: .bool(value)).map(send)
            }) {
                if let icon = node.string("icon") {
                    Label(node.string("label") ?? "", systemImage: Icons.symbol(or: icon, default: "questionmark"))
                } else {
                    Text(verbatim: node.string("label") ?? "")
                }
            }
            .accessibilityIdentifier(identifier)
            switch node.string("variant") {
            case "button": toggle.toggleStyle(.button)
            case "switch": toggle.toggleStyle(.switch)
            #if os(macOS)
            case "checkbox": toggle.toggleStyle(.checkbox)
            #endif
            default: toggle
            }
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
    @FocusState private var focused: Bool

    var body: some View {
        field
            .focused($focused)
            // `focus = true` puts the cursor here; losing it sends `blur`.
            .onChange(of: node.flag("focus"), initial: true) { _, focus in
                if focus != focused { focused = focus }
            }
            .onChange(of: focused) { _, focus in
                if !focus, node.flag("focus") { node.props["blur"].map(send) }
                if focus, !node.flag("focus") { node.props["focused"].map(send) }
            }
            .accessibilityIdentifier(identifier)
            .disabled(node.flag("disabled"))
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

    @ViewBuilder
    private var field: some View {
        let placeholder = node.string("placeholder") ?? ""
        switch node.kind {
        case .input where node.flag("secret"), .secure:
            bordered(SecureField(placeholder, text: $text))
        case .editor:
            TextEditor(text: $text)
                .frame(minHeight: node.number("minHeight").map { CGFloat($0) } ?? 80)
        default:
            bordered(
                TextField(placeholder, text: $text, axis: node.flag("multiline") ? .vertical : .horizontal)
                    .lineLimit(node.flag("multiline") ? 1...(node.integer("lines", in: 1...10_000) ?? 6) : 1...1)
            )
        }
    }

    /// Inside a list or form the field is the row; elsewhere it needs a box.
    @ViewBuilder
    private func bordered(_ field: some View) -> some View {
        if node.string("variant") == "plain" {
            field.textFieldStyle(.plain)
        } else {
            field.textFieldStyle(.roundedBorder)
        }
    }
}

/// `ui.stepper { "Copies", value = 2, min = 1, max = 9, change = "copies" }`.
struct StepperNode: View {
    let node: Node
    let identifier: String
    let send: (LuauValue) -> Void

    var body: some View {
        let low = node.number("min") ?? -.infinity
        let high = node.number("max") ?? .infinity
        Stepper(value: Binding {
            node.number("value") ?? 0
        } set: { value in
            event(node.props["change"], value: .number(value)).map(send)
        }, in: low...max(low, high), step: node.number("step") ?? 1) {
            Text(verbatim: node.string("label") ?? "")
        }
        .accessibilityIdentifier(identifier)
    }
}

/// `ui.picker { "Sort", value = state.sort, change = "sort", options = { "name", "date" } }`.
/// Options are values, or `{ value = ..., label = ..., icon = ... }`.
/// `variant` is `segmented`, `menu`, `inline`, `palette`, or on iOS `wheel`
/// and `navigation`.
struct PickerNode: View {
    let node: Node
    let identifier: String
    let send: (LuauValue) -> Void

    var body: some View {
        let picker = Picker(selection: Binding {
            node.props["value"] ?? .bool(false)
        } set: { value in
            event(node.props["change"], value: value).map(send)
        }) {
            ForEach(options, id: \.value) { option in
                if let icon = option.icon {
                    Label(option.label, systemImage: Icons.symbol(or: icon, default: "questionmark")).tag(option.value)
                } else {
                    Text(verbatim: option.label).tag(option.value)
                }
            }
        } label: {
            NodeLabel(node: node, scope: Scope(mod: "", path: identifier, trail: []), key: "label")
        }
        .accessibilityIdentifier(identifier)

        switch node.string("variant") {
        case "segmented": picker.pickerStyle(.segmented)
        case "menu": picker.pickerStyle(.menu)
        case "inline": picker.pickerStyle(.inline)
        case "palette": picker.pickerStyle(.palette)
        #if os(iOS)
        case "wheel": picker.pickerStyle(.wheel)
        case "navigation": picker.pickerStyle(.navigationLink)
        #endif
        default: picker
        }
    }

    private var options: [Option] {
        (node.props["options"]?.array ?? []).map { option in
            if case .table = option, let value = option["value"] {
                return Option(value: value, label: option["label"]?.string ?? value.plain, icon: option["icon"]?.string)
            }
            return Option(value: option, label: option.plain, icon: nil)
        }
    }

    private struct Option {
        let value: LuauValue
        let label: String
        let icon: String?
    }
}

extension LuauValue {
    /// The value as a person reads it: a string without its quotes.
    var plain: String {
        string ?? summary
    }
}
