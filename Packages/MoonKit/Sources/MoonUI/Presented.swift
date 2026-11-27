import MoonKit
import SwiftUI

/// Sheets, full-screen covers, popovers, alerts and dialogs, as props:
///
///     sheet = { open = state.composing, dismiss = "closed", detents = { "medium", "large" }, <content> }
///     alert = { open = state.asking, title = "Delete?", message = "...", dismiss = "closed", <buttons> }
///
/// The mod keeps `open`; when the system closes one (a swipe down, a tap
/// outside, any of its buttons) the view sends `dismiss`.
struct Presented: ViewModifier {
    var on = true
    let node: Node
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if on { presented(content) } else { content }
    }

    /// Only the presentations the element sets, each erased: one alert
    /// doesn't set up sheets, covers, popovers and dialogs too.
    private func presented(_ content: Content) -> AnyView {
        var view = AnyView(content)
        if let sheet = node.overlay("sheet") {
            view = AnyView(view.modifier(SheetModifier(overlay: sheet, scope: scope.child("sheet"), send: send)))
        }
        if let cover = node.overlay("cover") {
            view = AnyView(view.modifier(CoverModifier(overlay: cover, scope: scope.child("cover"), send: send)))
        }
        if let popover = node.overlay("popover") {
            view = AnyView(view.modifier(PopoverModifier(overlay: popover, scope: scope.child("popover"), send: send)))
        }
        if let alert = node.overlay("alert") {
            view = AnyView(view.modifier(AlertModifier(overlay: alert, scope: scope.child("alert"), send: send)))
        }
        if let confirm = node.overlay("confirm") {
            view = AnyView(view.modifier(ConfirmModifier(overlay: confirm, scope: scope.child("confirm"), send: send)))
        }
        return view
    }
}

/// `open` as the system wants it: closing sends `dismiss`.
private func shown(_ overlay: Overlay, send: @escaping (LuauValue) -> Void) -> Binding<Bool> {
    Binding {
        overlay.open
    } set: { open in
        if !open, let dismiss = overlay.fields["dismiss"] { send(dismiss) }
    }
}

/// An overlay's content: its first element, drawn as part of the mod.
private struct OverlayContent: View {
    let overlay: Overlay
    let scope: Scope

    var body: some View {
        if let first = Identified.of(overlay.content).first {
            NodeView(node: first.node, scope: scope.child(first.id)).equatable()
        }
    }
}

private struct SheetModifier: ViewModifier {
    let overlay: Overlay?
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let overlay {
            content.sheet(isPresented: shown(overlay, send: send)) {
                OverlayContent(overlay: overlay, scope: scope)
                    .presentationDetents(detents(overlay))
                    .presentationDragIndicator(overlay.fields["grabber"]?.bool == true ? .visible : .automatic)
                    .interactiveDismissDisabled(overlay.fields["modal"]?.bool ?? false)
                    .modifier(Sizing(name: overlay.string("sizing")))
                    .presentationBackgroundInteraction(
                        overlay.string("interactive") == "medium" ? .enabled(upThrough: .medium) : .automatic
                    )
            }
        } else {
            content
        }
    }

    private func detents(_ overlay: Overlay) -> Set<PresentationDetent> {
        let names = overlay.fields["detents"]?.array ?? []
        let detents = names.compactMap { name -> PresentationDetent? in
            if let height = name.number { return .height(height) }
            switch name.string {
            case "medium": return .medium
            case "large": return .large
            default: return nil
            }
        }
        return detents.isEmpty ? [.large] : Set(detents)
    }
}

private struct CoverModifier: ViewModifier {
    let overlay: Overlay?
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let overlay {
            #if os(iOS)
            content.fullScreenCover(isPresented: shown(overlay, send: send)) {
                OverlayContent(overlay: overlay, scope: scope)
            }
            #else
            content.sheet(isPresented: shown(overlay, send: send)) {
                OverlayContent(overlay: overlay, scope: scope)
            }
            #endif
        } else {
            content
        }
    }
}

private struct PopoverModifier: ViewModifier {
    let overlay: Overlay?
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let overlay {
            content.popover(isPresented: shown(overlay, send: send)) {
                OverlayContent(overlay: overlay, scope: scope)
                    .presentationCompactAdaptation(overlay.string("compact") == "sheet" ? .sheet : .popover)
            }
        } else {
            content
        }
    }
}

/// The buttons and fields of an alert or dialog.
private struct Actions: View {
    let overlay: Overlay
    let scope: Scope
    let send: (LuauValue) -> Void

    var body: some View {
        ForEach(Identified.of(overlay.content)) { item in
            switch item.node.kind {
            case .input, .secure:
                ControlNode(node: item.node, identifier: item.node.string("id") ?? scope.child(item.id).key, send: send)
            default:
                Button(role: item.node.role) {
                    if let message = item.node.props["msg"] { send(message) }
                } label: {
                    Text(verbatim: item.node.string("label") ?? "")
                }
                // No identifier of our own: the system copies it onto the
                // dialog's button too, and a test finds two.
            }
        }
    }
}

private struct AlertModifier: ViewModifier {
    let overlay: Overlay?
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let overlay {
            content.alert(overlay.string("title") ?? "", isPresented: shown(overlay, send: send)) {
                Actions(overlay: overlay, scope: scope, send: send)
            } message: {
                if let message = overlay.string("message") { Text(verbatim: message) }
            }
        } else {
            content
        }
    }
}

private struct ConfirmModifier: ViewModifier {
    let overlay: Overlay?
    let scope: Scope
    let send: (LuauValue) -> Void

    func body(content: Content) -> some View {
        if let overlay {
            content.confirmationDialog(
                overlay.string("title") ?? "", isPresented: shown(overlay, send: send),
                titleVisibility: overlay.string("title") == nil ? .hidden : .visible
            ) {
                Actions(overlay: overlay, scope: scope, send: send)
            } message: {
                if let message = overlay.string("message") { Text(verbatim: message) }
            }
        } else {
            content
        }
    }
}

/// `sizing = "page"` or `"form"`: how big a sheet is on iPad and the Mac.
private struct Sizing: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        switch name {
        case "page": content.presentationSizing(.page)
        case "form": content.presentationSizing(.form)
        case "fitted": content.presentationSizing(.fitted)
        default: content
        }
    }
}
