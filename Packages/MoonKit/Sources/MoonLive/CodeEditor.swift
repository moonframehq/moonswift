import SwiftUI

/// The range of 1-based `line` in `source`.
private func range(ofLine line: Int, in source: NSString) -> NSRange {
    var location = 0
    for _ in 1..<max(line, 1) where location < source.length {
        location = NSMaxRange(source.lineRange(for: NSRange(location: location, length: 0)))
    }
    return source.lineRange(for: NSRange(location: min(location, source.length), length: 0))
}

#if os(macOS)
import AppKit

/// A plain source editor that highlights and scrolls to one line.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let line: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.drawsBackground = false
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier("moon.source")
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let replaced = view.string != text
        if replaced { view.string = text }
        let moved = context.coordinator.line != line
        if replaced || moved {
            context.coordinator.line = line
            highlight(in: view)
        }
    }

    private func highlight(in view: NSTextView) {
        guard let manager = view.layoutManager, let container = view.textContainer else { return }
        let source = view.string as NSString
        manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: source.length))
        guard let line, line > 0 else { return }
        let target = range(ofLine: line, in: source)
        manager.addTemporaryAttribute(
            .backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.22), forCharacterRange: target
        )
        // Once the panel has finished opening and the text is laid out: until
        // then the editor isn't its final size, and the scroll wouldn't hold.
        // Tried until it holds, as a busy machine may take longer.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            for _ in 0..<20 {
                manager.ensureLayout(for: container)
                view.scrollRangeToVisible(target)
                let glyphs = manager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
                if view.visibleRect.contains(manager.boundingRect(forGlyphRange: glyphs, in: container)) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        var line: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { text.wrappedValue = view.string }
        }
    }
}
#else
import UIKit

/// A plain source editor that highlights and scrolls to one line.
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    let line: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.spellCheckingType = .no
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "moon.source"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let replaced = view.text != text
        if replaced { view.text = text }
        let moved = context.coordinator.line != line
        if replaced || moved {
            context.coordinator.line = line
            highlight(in: view)
        }
    }

    private func highlight(in view: UITextView) {
        let storage = view.textStorage
        let whole = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: whole)
        storage.addAttribute(.foregroundColor, value: UIColor.label, range: whole)
        guard let line, line > 0 else { return }
        let target = range(ofLine: line, in: storage.string as NSString)
        storage.addAttribute(.backgroundColor, value: UIColor.tintColor.withAlphaComponent(0.22), range: target)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            view.scrollRangeToVisible(target)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>
        var line: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ view: UITextView) {
            text.wrappedValue = view.text
        }
    }
}
#endif
