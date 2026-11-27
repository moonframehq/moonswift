#if DEBUG && os(macOS)
import AppKit
import Foundation
import MoonKit
import MoonLive

/// `just smoke`: the debug app driving itself on a throwaway copy of `app/`.
/// Real mouse events through the real window, files changed behind its back
/// and seen by the real watcher, and pictures of the result. It lives in the
/// app rather than in UI tests because XCUITest needs Automation Mode, which
/// takes an admin's approval; this runs anywhere, in seconds.
struct SelfDrive {
    private struct Failure: Error {
        let message: String
    }

    let workspace: Workspace
    let inspection: Inspection
    let agent: AgentSession
    let snapshots: URL

    private let more = "0/more"
    private let count = "0/count"

    private var counterFile: URL {
        workspace.folders.builtin.appending(path: "mods/counter/main.luau")
    }

    private var countText: String? {
        workspace.trees["counter"]?.node(at: count)?.text
    }

    /// Starts if `MOONSWIFT_SELFDRIVE` names a folder for the pictures.
    static func startIfAsked(workspace: Workspace, inspection: Inspection, agent: AgentSession) {
        guard let folder = ProcessInfo.processInfo.environment["MOONSWIFT_SELFDRIVE"] else { return }
        let drive = SelfDrive(workspace: workspace, inspection: inspection, agent: agent, snapshots: URL(filePath: folder))
        // Whatever happens, never hang whoever is waiting.
        DispatchQueue.global().asyncAfter(deadline: .now() + 240) {
            print("✘ timed out")
            exit(2)
        }
        Task { await drive.run() }
    }

    private func run() async {
        let steps: [(String, () async throws -> Void)] = [
            ("clicks reach Luau and the window redraws", clicks),
            ("navigation and topics connect the mods", navigation),
            ("saving a file reshapes the window and keeps the state", liveReload),
            ("a broken save keeps the window, then recovers", brokenSave),
            ("the sparkle finds the source and edits it live", sparkle),
            ("an agent changes the picked element live", askAgent),
        ]
        var failed = 0
        do {
            try await prepare()
        } catch {
            print("✘ setup: \(error)")
            exit(1)
        }
        for (name, step) in steps {
            do {
                try await reset()
                try await step()
                print("✔ \(name)")
            } catch {
                failed += 1
                print("✘ \(name): \(error)")
            }
        }
        print(failed == 0 ? "all \(steps.count) passed" : "\(failed) of \(steps.count) failed")
        exit(failed == 0 ? 0 : 1)
    }

    private func prepare() async throws {
        try await until("the window lays out") { inspection.windowFrame(mod: "counter", path: more) != nil }
        // Nothing here needs focus, which a locked or busy Mac won't give.
        NSApp.activate()
    }

    private func reset() async throws {
        inspection.selection = nil
        inspection.cancelPicking()
        workspace.send(.string("reset"), to: "counter")
        try await until("the count resets") { countText == "0" }
        // The panel closing moves everything: wait, or clicks land where things were.
        try await settle()
    }

    // MARK: Helpers

    private func check(_ condition: Bool, _ what: String) throws {
        if !condition { throw Failure(message: what) }
    }

    private func until(_ what: String, timeout: Duration = .seconds(6), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { throw Failure(message: "timed out waiting: \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func window() throws -> NSWindow {
        guard let window = NSApp.windows.first(where: { $0.title == "MoonSwift" && $0.contentView != nil }) else {
            throw Failure(message: "no window")
        }
        return window
    }

    /// Mouse down and up through the window at a point in it, top left
    /// origin, so hit testing decides what gets the click.
    private func click(at point: CGPoint) async throws {
        let window = try window()
        let height = window.contentView?.bounds.height ?? 0
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: CGPoint(x: point.x, y: height - point.y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
            if let event { window.sendEvent(event) }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func click(mod: String, path: String) async throws {
        guard let frame = inspection.windowFrame(mod: mod, path: path) else {
            throw Failure(message: "\(mod):\(path) is not on screen")
        }
        try await click(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// The sparkle in the toolbar, clicked where it actually is.
    private func clickSparkle() async throws {
        let window = try window()
        let items = window.toolbar?.items ?? []
        guard let view = items.first(where: { $0.label == "Inspect" })?.view else {
            throw Failure(message: "no sparkle among \(items.map(\.label))")
        }
        let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        try await click(at: CGPoint(x: center.x, y: (window.contentView?.bounds.height ?? 0) - center.y))
    }

    /// From the view tree, which needs no Screen Recording permission, unlike
    /// the window server, which hands back a blank image without it. A blank
    /// picture fails the run: it proves nothing.
    private func snapshot(_ name: String) throws {
        guard let view = try window().contentView?.superview,
              let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(message: "no picture of the window")
        }
        view.cacheDisplay(in: view.bounds, to: image)
        // Below the title bar, where the app draws.
        let colors = stride(from: 120, to: image.pixelsHigh, by: 37).flatMap { y in
            stride(from: 0, to: image.pixelsWide, by: 41).map { x in image.colorAt(x: x, y: y) }
        }
        try check(Set(colors).count > 1, "\(name): the window drew nothing")
        guard let data = image.representation(using: .png, properties: [:]) else { return }
        try data.write(to: snapshots.appending(path: "\(name).png"))
    }

    private func editor(in view: NSView?) -> NSTextView? {
        if let text = view as? NSTextView, text.isEditable { return text }
        return view?.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    private func lineIsVisible(_ line: Int, in view: NSTextView?) -> Bool {
        guard let view, let manager = view.layoutManager, let container = view.textContainer else { return false }
        let lines = view.string.components(separatedBy: "\n")
        let start = lines.prefix(line - 1).reduce(0) { $0 + ($1 as NSString).length + 1 }
        let glyphs = manager.glyphRange(
            forCharacterRange: NSRange(location: start, length: (lines[line - 1] as NSString).length),
            actualCharacterRange: nil
        )
        return view.visibleRect.contains(manager.boundingRect(forGlyphRange: glyphs, in: container))
    }

    private func lineReport(_ line: Int, in view: NSTextView?) -> String {
        guard let view, let manager = view.layoutManager, let container = view.textContainer else { return "no view" }
        let lines = view.string.components(separatedBy: "\n")
        let start = lines.prefix(line - 1).reduce(0) { $0 + ($1 as NSString).length + 1 }
        let glyphs = manager.glyphRange(
            forCharacterRange: NSRange(location: start, length: (lines[line - 1] as NSString).length),
            actualCharacterRange: nil
        )
        return "visible \(view.visibleRect), line \(manager.boundingRect(forGlyphRange: glyphs, in: container))"
    }

    private func source() throws -> String {
        try String(contentsOf: counterFile, encoding: .utf8)
    }

    private func save(_ text: String) throws {
        try text.write(to: counterFile, atomically: true, encoding: .utf8)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    // MARK: Steps

    private func clicks() async throws {
        for path in [more, more, more, "0/less"] {
            try await click(mod: "counter", path: path)
        }
        try await until("the count reaches 2") { countText == "2" }
        try await until("the new text is on screen") { inspection.labels.contains(#"text "2""#) }
        try await settle()
        try snapshot("1-counter")
    }

    private func navigation() async throws {
        try await click(mod: "sidebar", path: "nav-tasks")
        try await until("the tasks page shows") {
            inspection.labels.contains(#"text "Press the sparkles and pick something""#)
        }
        try check(workspace.trees["status"]?.children[0].text == "tasks", "the status bar should follow")
        try await settle()
        try snapshot("2-tasks")
        try await click(mod: "sidebar", path: "nav-counter")
        try await until("back on the counter") { inspection.windowFrame(mod: "counter", path: more) != nil }
    }

    private func liveReload() async throws {
        let original = try source()
        defer { try? save(original) }
        try await click(mod: "counter", path: more)
        try await click(mod: "counter", path: more)
        try await until("the count reaches 2") { countText == "2" }

        try save(original.replacingOccurrences(
            of: #"title = "Counter","#, with: #"title = "Live", ui.text { "edited on disk" },"#
        ))

        try await until("the watcher reloads the mod") { inspection.labels.contains(#"text "edited on disk""#) }
        try await until("the count survives") { inspection.labels.contains(#"text "2""#) }
        try await settle()
        try snapshot("3-reloaded")

        try save(original)
        try await until("the original comes back") { !inspection.labels.contains(#"text "edited on disk""#) }
    }

    private func brokenSave() async throws {
        let original = try source()
        defer { try? save(original) }
        try await click(mod: "counter", path: more)
        try await until("the count reaches 1") { countText == "1" }

        try save("return mod {")

        try await until("the problem shows") { workspace.problem(of: "counter") != nil }
        try check(inspection.windowFrame(mod: "counter", path: more) != nil, "the last good view should stay")
        try await settle()
        try snapshot("4-broken")
        try await click(mod: "counter", path: more)
        try await until("the old version still works") { countText == "2" }

        try save(original)

        try await until("the problem clears") { workspace.problem(of: "counter") == nil }
        try check(countText == "2", "the state should survive the whole episode")
    }

    private func sparkle() async throws {
        let original = try source()
        defer { try? save(original) }
        try await click(mod: "counter", path: more)
        try await until("the count reaches 1") { countText == "1" }

        try await clickSparkle()
        try check(inspection.picking, "the sparkle should start picking")
        try await click(mod: "counter", path: more)

        guard let selection = inspection.selection else { throw Failure(message: "nothing was picked") }
        try check(!inspection.picking, "a pick should end picking")
        try check(countText == "1", "the click should go to the inspector, not the button")
        try check(selection.label == #"button "More""#, "picked \(selection.label)")

        let lines = original.components(separatedBy: "\n")
        let line = (lines.firstIndex { $0.contains(#"label = "More""#) } ?? -1) + 1
        let report = inspection.report(in: workspace)
        try check(report.contains("mods/counter/main.luau:\(line)"), "wrong location in:\n\(report)")
        try check(selection.trail.map(\.label).contains(#"panel "Counter""#), "trail: \(selection.trail.map(\.label))")
        let cache = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/moonswift/selection.md")
        try check(try String(contentsOf: cache, encoding: .utf8) == report, "selection.md should hold the report")

        var text: NSTextView?
        try await until("the inspector shows the source") {
            text = try? editor(in: window().contentView?.superview)
            return text?.string == original
        }
        try await settle()
        // Found isn't enough: it has to be seen, beside a narrower canvas.
        try check((text?.visibleRect.width ?? 0) > 200, "the inspector's editor should be visible")
        // The editor scrolls once the panel has opened, which takes longer on a
        // busy machine: wait for it rather than sample once.
        do {
            // Found again each time: SwiftUI may replace the editor's view.
            try await until("line \(line) on screen in the editor", timeout: .seconds(7)) {
                text = try? editor(in: window().contentView?.superview)
                return lineIsVisible(line, in: text)
            }
        } catch {
            throw Failure(message: "line \(line) should be on screen in the editor: \(lineReport(line, in: text))")
        }
        let room = try window().frame.width - workspace.context.width
        try check(room >= 300, "the canvas should make room for the panel, gave \(room)")
        try snapshot("5-inspected")

        // Type into the inspector's editor, as a user would.
        guard let view = text else { return }
        let changed = original.replacingOccurrences(of: #"label = "More""#, with: #"label = "Way more""#)
        view.selectAll(nil)
        view.insertText(changed, replacementRange: view.selectedRange())

        try await until("typing redraws the window") { inspection.labels.contains(#"button "Way more""#) }
        try check(try source() == changed, "the edit should be saved")
        try check(countText == "1", "the state should survive")
        try check(inspection.report(in: workspace).contains(#"element: button "Way more""#), "the card should follow")
        try await settle()
        try snapshot("6-edited")
    }

    private func askAgent() async throws {
        let original = try source()
        defer { try? save(original) }
        try await click(mod: "counter", path: more)
        try await until("the count reaches 1") { countText == "1" }
        try await clickSparkle()
        try await click(mod: "counter", path: more)
        try check(inspection.selection != nil, "nothing was picked")

        agent.ask(
            #"Change this button's label to "Agent was here". Nothing else."#,
            about: inspection.report(in: workspace), in: workspace
        )

        try await until("the agent changes the window", timeout: .seconds(180)) {
            inspection.labels.contains(#"button "Agent was here""#)
        }
        try await until("the agent finishes", timeout: .seconds(60)) { !agent.running }
        try check(workspace.problems.isEmpty, "the app should end up healthy: \(workspace.problems)")
        try check(countText == "1", "the state should survive")
        for entry in agent.entries { print("  [\(entry.kind)] \(entry.text.prefix(150))") }
        try await settle()
        try snapshot("7-agent")
    }
}
#endif
