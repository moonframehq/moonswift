import Foundation
import Testing

@testable import MoonKit

/// The budgets of plans/ios-parity.md, headless. Each runs the Luau path
/// and the same work in plain Swift, prints both, and fails past a budget
/// set for a debug build on a laptop; `just bench` runs them optimized.
@Suite("Benchmarks", .serialized)
struct BenchmarkTests {
    private static let rows = 10_000

    /// Median of `runs` timings of `body`, in milliseconds.
    private func median(_ runs: Int = 15, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var times: [Double] = []
        for _ in 0..<runs {
            let start = clock.now
            body()
            let elapsed = clock.now - start
            times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        return times.sorted()[runs / 2]
    }

    private func report(_ name: String, luau: Double, swift: Double, unit: String = "ms", against: String = "swift") {
        let ratio = swift > 0 ? luau / swift : 0
        print(String(
            format: "bench %-28@ luau %8.3f %@   %@ %8.3f %@   ×%.1f",
            name as NSString, luau, unit, against as NSString, swift, unit, ratio
        ))
    }

    private func workspace() throws -> (Sandbox, Workspace) {
        let app = try Sandbox(["main.luau": lazyList(count: Self.rows)])
        let workspace = app.workspace()
        workspace.reload()
        return (app, workspace)
    }

    /// The Swift a hand-written screen would run per keystroke: filter the
    /// model and hand SwiftUI the ids.
    private struct Item { let id: String; let title: String }
    private let items = (1...rows).map { Item(id: "s\($0)", title: "Session \($0)") }

    private func filtered(_ query: String) -> [String] {
        items.filter { query.isEmpty || $0.title.contains(query) }.map(\.id)
    }

    @Test func aKeystrokeOnATenThousandRowList() throws {
        let (app, workspace) = try workspace()
        _ = app
        var flip = false
        let luau = median {
            flip.toggle()
            workspace.send(.fields(["msg": .string("query"), "value": .string(flip ? "1" : "")]), to: "main")
        }
        var sink = 0
        let swift = median {
            flip.toggle()
            sink += filtered(flip ? "1" : "").count
        }
        report("keystroke, 10k rows", luau: luau, swift: swift)
        #expect(workspace.problems.isEmpty)
        // Under half a 120 Hz frame in a debug build.
        #expect(luau < 40, "a keystroke took \(luau) ms")
    }

    @Test func redrawingTheVisibleRows() throws {
        let (app, workspace) = try workspace()
        _ = app
        // What a phone shows of a list at once, and then some.
        let visible = (100..<130).map { LuauValue.string("s\($0)") }
        var flip = false
        let luau = median {
            flip.toggle()
            workspace.send(.fields(["pick": .string(flip ? "s101" : "s102")]), to: "main")
            for key in visible { _ = workspace.part("session", key: key, of: "main") }
        }
        let cached = median {
            for key in visible { _ = workspace.part("session", key: key, of: "main") }
        }
        report("30 rows after a change", luau: luau, swift: cached, against: "cached")
        #expect(luau < 20, "30 rows took \(luau) ms")
        #expect(cached < 1, "30 cached rows took \(cached) ms")
    }

    @Test func coldStart() throws {
        let app = try Sandbox(["main.luau": lazyList(count: Self.rows)])
        let luau = median(5) {
            let workspace = app.workspace()
            workspace.reload()
        }
        let swift = median(5) { _ = (1...Self.rows).map { Item(id: "s\($0)", title: "Session \($0)") } }
        report("cold start, 10k items", luau: luau, swift: swift)
        #expect(luau < 300, "a cold start took \(luau) ms")
    }

    @Test func theBundledAppStartsFast() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../app").standardized
        let luau = median(5) {
            let workspace = Workspace(folders: Folders(builtin: folder))
            workspace.reload()
        }
        report("cold start, bundled app", luau: luau, swift: 0)
        #expect(luau < 200, "the bundled app took \(luau) ms to load")
    }

    @Test func memoryForTenThousandItems() throws {
        let (app, workspace) = try workspace()
        _ = app
        let bytes = try #require(workspace.memory(of: "main"))
        let swift = MemoryLayout<Item>.stride * Self.rows + Self.rows * 2 * 16
        report("memory, 10k items", luau: Double(bytes) / 1_048_576, swift: Double(swift) / 1_048_576, unit: "MB")
        #expect(bytes < 16 * 1_048_576, "10k items took \(bytes) bytes")
    }
}
