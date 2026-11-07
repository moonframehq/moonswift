import Foundation
import Testing

import MoonLive

@testable import MoonKit

/// A throwaway app folder.
private final class Sandbox {
    let root: URL

    init(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "moon-\(UUID().uuidString)")
        for (file, text) in files { try write(text, to: file) }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ text: String, to file: String) throws {
        let url = root.appending(path: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func workspace(limits: Limits = Limits()) -> Workspace {
        Workspace(folders: Folders(builtin: root), limits: limits)
    }
}

nonisolated private func shell(_ body: String) -> String {
    """
    return mod {
        init = function(previous) return previous or { count = 0 } end,
        update = function(state, msg) if msg == "more" then state.count += 1 end end,
        view = function(state, app)
            \(body)
        end,
    }
    """
}

private let counter = shell(#"return ui.text { "count " .. state.count }"#)

@Suite("Mods")
struct ModTests {
    @Test func aViewBecomesATreeStampedWithItsLine() throws {
        let app = try Sandbox(["main.luau": shell("return ui.row {\n ui.text { 'hi' },\n false,\n ui.button { 'Go' } }")])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.trees["main"])
        #expect(workspace.problems.isEmpty)
        #expect(tree.kind == .row)
        #expect(tree.line == 5)
        #expect(tree.children.map(\.label) == [#"text "hi""#, #"button "Go""#])
        #expect(tree.children[0].line == 6)
    }

    @Test func updateChangesTheStateAndRedraws() throws {
        let app = try Sandbox(["main.luau": counter])
        let workspace = app.workspace()
        workspace.reload()

        workspace.send(.string("more"), to: "main")
        workspace.send(.string("more"), to: "main")

        #expect(workspace.trees["main"]?.text == "count 2")
    }

    @Test func modsTalkThroughSendsAndTopics() throws {
        let app = try Sandbox([
            "main.luau": """
            return mod {
                update = function(state, msg) return state, { { to = "topic:news", msg = "hello" } } end,
                view = function() return ui.row {} end,
            }
            """,
            "mods/listener/main.luau": """
            return mod {
                region = "left",
                subscribe = { "news" },
                init = function() return { heard = "nothing" } end,
                update = function(state, msg) state.heard = msg.value end,
                view = function(state) return ui.text { state.heard } end,
            }
            """,
        ])
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.mods(in: "left") == ["listener"])

        workspace.send(.string("go"), to: "main")

        #expect(workspace.trees["listener"]?.text == "hello")
    }

    @Test func componentsAreSharedWithUseAndPointAtTheModsLine() throws {
        let app = try Sandbox([
            "components/badge.luau": "return function(props)\n\n\n return ui.badge { props.text } end",
            "main.luau": "local badge = use 'badge'\nreturn mod { view = function()\n return badge { text = 'new' } end }",
        ])
        let workspace = app.workspace()
        workspace.reload()

        #expect(workspace.problems.isEmpty)
        #expect(workspace.trees["main"]?.text == "new")
        #expect(workspace.trees["main"]?.line == 3)
    }

    @Test func aBadElementIsAMarkNotABlankWindow() throws {
        let app = try Sandbox(["main.luau": shell("return ui.row { { type = 'nope' }, ui.text { 'fine' } }")])
        let workspace = app.workspace()
        workspace.reload()

        #expect(workspace.trees["main"]?.problems == ["no element named nope"])
        #expect(workspace.trees["main"]?.children[1].text == "fine")
    }

    @Test func messagesThatAnswerEachOtherStop() throws {
        let app = try Sandbox(["main.luau": """
        return mod {
            update = function(state, msg) return state, { { to = "main", msg = "again" } } end,
            view = function() return ui.row {} end,
        }
        """])
        let workspace = app.workspace()
        workspace.reload()

        workspace.send(.string("again"), to: "main")

        #expect(workspace.problems["messages"] != nil)
    }
}

@Suite("Live reload")
struct ReloadTests {
    @Test func anEditReplacesTheViewAndKeepsTheState() throws {
        let app = try Sandbox(["main.luau": counter])
        let workspace = app.workspace()
        workspace.reload()
        workspace.send(.string("more"), to: "main")

        try app.write(shell(#"return ui.text { "total " .. state.count }"#), to: "main.luau")
        workspace.reload()

        #expect(workspace.trees["main"]?.text == "total 1")
        #expect(workspace.reloads == 2)
    }

    @Test(arguments: [
        "return mod {",
        "error('boom')",
        "return 5",
        "return mod { view = 1 }",
        shell("error('view broke')"),
        shell("while true do end"),
    ])
    func aBrokenEditKeepsTheLastGoodViewAndState(broken: String) throws {
        let app = try Sandbox(["main.luau": counter])
        let workspace = app.workspace(limits: quick)
        workspace.reload()
        workspace.send(.string("more"), to: "main")

        try app.write(broken, to: "main.luau")
        workspace.reload()
        #expect(workspace.trees["main"]?.text == "count 1")
        #expect(workspace.problem(of: "main") != nil)

        workspace.send(.string("more"), to: "main")
        #expect(workspace.trees["main"]?.text == "count 2")

        try app.write(counter, to: "main.luau")
        workspace.reload()
        #expect(workspace.problem(of: "main") == nil)
        #expect(workspace.trees["main"]?.text == "count 2")
    }

    @Test func nothingChangedMeansNothingReloads() throws {
        let app = try Sandbox(["main.luau": counter])
        let workspace = app.workspace()
        workspace.reload()
        workspace.reload()

        #expect(workspace.reloads == 1)
    }

    @Test func aComponentEditReachesTheModsUsingIt() throws {
        let app = try Sandbox([
            "components/label.luau": "return function() return ui.text { 'old' } end",
            "main.luau": "local label = use 'label'\nreturn mod { view = function() return label() end }",
        ])
        let workspace = app.workspace()
        workspace.reload()

        try app.write("return function() return ui.text { 'new' } end", to: "components/label.luau")
        workspace.reload()

        #expect(workspace.trees["main"]?.text == "new")
    }

    @Test func aDeletedModGoesAwayWithItsProblem() throws {
        let app = try Sandbox(["main.luau": counter, "mods/gone/main.luau": "return mod {"])
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.problem(of: "gone") != nil)

        try FileManager.default.removeItem(at: app.root.appending(path: "mods/gone"))
        workspace.reload()

        #expect(workspace.problems.isEmpty)
    }

    @Test func theStylesheetReloadsAndABrokenOneIsKept() throws {
        let sheet = ##"""
        return style {
            colors = { accent = "#111111" },
            rules = { text = { radius = 3 }, nav = { radius = 9 }, ["nav:hover"] = { radius = 12 } },
        }
        """##
        let app = try Sandbox(["main.luau": shell("return ui.text { 'a', class = 'nav' }"), "style.luau": sheet])
        let workspace = app.workspace()
        workspace.reload()
        let tree = try #require(workspace.trees["main"])
        #expect(workspace.stylesheet.color("accent", dark: false) == "#111111")
        #expect(workspace.stylesheet.resolve(tree).radius == 9)
        #expect(workspace.stylesheet.resolve(tree, hovered: true).radius == 12)

        try app.write("return style {", to: "style.luau")
        workspace.reload()

        #expect(workspace.stylesheet.color("accent", dark: false) == "#111111")
        #expect(workspace.problems["style.luau"] != nil)
    }

    @Test func theWatcherSeesASavedFile() async throws {
        let app = try Sandbox(["main.luau": counter])
        let changes = folderChanges([app.root], latency: 0.01)
        try await Task.sleep(for: .milliseconds(200))

        try app.write(shell("return ui.row {}"), to: "main.luau")

        var iterator = changes.makeAsyncIterator()
        await iterator.next()
    }
}

@Suite("Overlay")
struct OverlayTests {
    @Test func aUserFileWinsAndEditsNeverTouchTheBuiltInApp() throws {
        let builtin = try Sandbox(["main.luau": counter])
        let user = try Sandbox([:])
        let folders = Folders(builtin: builtin.root, user: user.root)
        let workspace = Workspace(folders: folders)
        workspace.reload()

        try workspace.write(shell("return ui.text { 'mine' }"), to: "main.luau")

        #expect(workspace.trees["main"]?.text == "mine")
        #expect(folders.locate("main.luau")?.path.hasPrefix(user.root.path) == true)
        #expect(try String(contentsOf: builtin.root.appending(path: "main.luau"), encoding: .utf8) == counter)
    }
}

/// Small enough that an endless loop ends quickly in tests.
private let quick: Limits = {
    var limits = Limits()
    limits.budget = 100_000
    return limits
}()

@Suite("Sandbox")
struct SandboxTests {
    private func failure(of body: String, limits: Limits = quick) throws -> String? {
        let app = try Sandbox(["main.luau": shell(body)])
        let workspace = app.workspace(limits: limits)
        workspace.reload()
        return workspace.problem(of: "main")?.message
    }

    @Test func anEndlessLoopRunsOutOfInstructions() throws {
        let message = try failure(of: "while true do end")
        #expect(message?.contains("ran out of instructions") == true)
    }

    @Test func anEndlessRecursionIsCaught() throws {
        #expect(try failure(of: "local function f() return 1 + f() end return f()") != nil)
    }

    @Test func runawayMemoryHitsTheCap() throws {
        var limits = Limits()
        limits.memory = 4 * 1024 * 1024
        let hog = "local t = {} while true do t[#t + 1] = string.rep('x', 4096) .. #t end"
        let message = try failure(of: hog, limits: limits)
        #expect(message?.contains("not enough memory") == true)
    }

    @Test(arguments: [
        "os", "io", "debug", "require", "loadstring", "getfenv", "setfenv", "collectgarbage", "__caller_line", "__components",
    ])
    func dangerousGlobalsAreGone(name: String) throws {
        let app = try Sandbox(["main.luau": shell("return ui.text { type(\(name)) }")])
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.trees["main"]?.text == "nil")
    }

    @Test(arguments: ["ui.text = 1", "string.rep = nil", "x = 1"])
    func theGlobalsAreSealed(attempt: String) throws {
        let message = try failure(of: attempt + " return ui.row {}")
        #expect(message?.contains("readonly") == true)
    }

    @Test func aStateThatHoldsItselfIsRefusedNotAHang() throws {
        let app = try Sandbox(["main.luau": """
        return mod {
            init = function() local s = {} s.me = s return s end,
            view = function() return ui.row {} end,
        }
        """])
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.problem(of: "main") == nil)

        try app.write(counter, to: "main.luau")
        workspace.reload()
        #expect(workspace.problem(of: "main")?.message.contains("nested too deep") == true)
    }

    @Test func bytecodeIsNotLoaded() throws {
        let app = try Sandbox(["main.luau": "\u{1B}Lua\u{0}\u{1}"])
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.problem(of: "main") != nil)
    }
}

@Suite("The bundled app")
struct BundledAppTests {
    private var folders: Folders {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return Folders(builtin: root.appending(path: "app"))
    }

    @Test func everyModuleLoadsClean() throws {
        let workspace = Workspace(folders: folders)
        workspace.reload()

        #expect(workspace.problems.isEmpty)
        #expect(workspace.trees.values.flatMap(\.problems).isEmpty)
        #expect(Set(workspace.trees.keys) == ["main", "sidebar", "counter", "tasks", "status"])
    }

    @Test func thePagesConnect() throws {
        let workspace = Workspace(folders: folders)
        workspace.reload()

        workspace.send(.fields(["go": .string("tasks")]), to: "sidebar")

        let page = try #require(workspace.trees["main"]?.children[0].children.last?.children.first)
        #expect(page.string("mod") == "tasks")
        #expect(workspace.trees["status"]?.children[0].text == "tasks")
    }
}
