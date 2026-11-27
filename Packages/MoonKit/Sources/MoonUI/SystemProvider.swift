import MoonKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// `system`: what any app can offer its mods without giving them the
/// machine. Mods read `app.system.idiom` (`phone`, `pad`, `mac`) and send
/// `provider:system`:
///
///     { haptic = "success" }   -- success, warning, error, light, medium, heavy, selection
///     { copy = "text" }        -- onto the clipboard
///
/// Nothing here reads back what the person has, so it gives Luau no way out:
/// there is no `paste`, and no `open` (a link opens only on a tap).
public final class SystemProvider: Provider {
    public let name = "system"

    public init() {}

    public func start(_ link: ProviderLink) {
        link.publish(.fields(["idiom": .string(Self.idiom)]))
    }

    public func receive(_ message: LuauValue, from mod: String?) {
        if let kind = message["haptic"]?.string { Self.haptic(kind) }
        if let text = message["copy"]?.string { Self.copy(text) }
    }

    static var idiom: String {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone"
        #else
        "mac"
        #endif
    }

    static func haptic(_ kind: String) {
        #if os(iOS)
        switch kind {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "selection": UISelectionFeedbackGenerator().selectionChanged()
        case "light": UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
