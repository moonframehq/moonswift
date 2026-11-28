#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing

import MoonKit
@testable import MoonUI

/// A list asks for the rows it shows, not for all of them, whatever its
/// rows carry: a trait SwiftUI can't find without drawing a row (one
/// behind a branch it can't see past) makes it draw every row up front.
@MainActor
@Suite("List laziness", .serialized)
struct ListLazinessTests {
    /// 10,000 lazy rows, some with a badge, a context menu or swipe
    /// actions, and a `drawn` function that counts the rows drawn so far.
    private func app(count: Int, edge: Bool = false) throws -> Sandbox {
        try Sandbox(["main.luau": """
        local drawn = 0
        return mod {
            init = function() return {} end,
            view = function()
                return ui.list {
                    edge = \(edge),
                    count = \(count),
                    row = function(i)
                        drawn += 1
                        return ui.row {
                            badge = i % 3 == 0 and i or nil,
                            context = i % 4 == 0 and { ui.button { "Open", msg = "open" } } or nil,
                            swipe = i % 5 == 0 and { ui.button { "Delete", role = "destructive", msg = "delete" } } or nil,
                            ui.icon { "star" },
                            ui.text { "Row " .. i },
                            ui.spacer {},
                            ui.text { tostring(i), style = { color = "secondary" } },
                        }
                    end,
                    drawn = function() return ui.text { tostring(drawn) } end,
                }
            end,
        }
        """])
    }

    @Test(arguments: [false, true])
    func aListDrawsOnlyTheRowsItShows(edge: Bool) async throws {
        let app = try app(count: 10_000, edge: edge)
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.problems.isEmpty)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false
        )
        // Made in code, a window is released as it closes: Swift owns it here.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MoonCanvas().environment(workspace))
        window.orderFrontRegardless()
        defer { window.close() }
        for _ in 0..<10 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }

        let tree = try #require(workspace.drawing(of: Workspace.shell).tree)
        let counter = try #require(tree.function("drawn"))
        let counted = workspace.part(counter, key: .string(UUID().uuidString), of: Workspace.shell)
        let drawn = Int(counted.string("text") ?? "") ?? -1
        #expect(drawn > 0, "the list drew no row")
        // A Mac list measures some 600 rows ahead; one that draws them all
        // draws 10,000.
        #expect(drawn < 2000, "the list drew \(drawn) of 10,000 rows")
    }
}
#endif
