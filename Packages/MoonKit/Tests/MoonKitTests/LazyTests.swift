import Foundation
import Testing

@testable import MoonKit

/// A list of `count` items whose rows the mod draws on demand.
nonisolated func lazyList(count: Int) -> String {
    """
    return mod {
        init = function(previous)
            local items = {}
            for i = 1, \(count) do items[i] = { id = "s" .. i, title = "Session " .. i } end
            return { items = items, query = "", picked = nil, calls = 0 }
        end,
        update = function(state, msg)
            if type(msg) == "table" and msg.msg == "query" then state.query = msg.value end
            if type(msg) == "table" and msg.pick then state.picked = msg.pick end
        end,
        view = function(state)
            local shown = {}
            for _, item in state.items do
                if state.query == "" or string.find(item.title, state.query, 1, true) then
                    table.insert(shown, item)
                end
            end
            return ui.list {
                search = { value = state.query, change = "query" },
                id = "sessions", count = #shown, row_height = 44,
                row = function(i)
                    local item = shown[i]
                    return ui.text { item.title, selected = state.picked == item.id, msg = { pick = item.id } }
                end,
            }
        end,
    }
    """
}

@Suite("Lazy views")
struct LazyTests {
    @Test func rowsAreCountedAndDrawnOnlyWhenAsked() throws {
        let app = try Sandbox(["main.luau": lazyList(count: 500)])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.drawing(of: "shell").tree)
        #expect(workspace.problems.isEmpty)
        let rows = try #require(tree.lazyRows)
        #expect(rows.count == 500)
        #expect(tree.children.isEmpty, "no row is drawn with the view")

        let row = workspace.part(rows.function, key: .number(42), of: "shell")
        #expect(row.text == "Session 42")
    }

    @Test func aRowIsKeptUntilTheStateChanges() throws {
        let app = try Sandbox(["main.luau": lazyList(count: 10)])
        let workspace = app.workspace()
        workspace.reload()

        let before = workspace.part(1, key: .number(3), of: "shell")
        #expect(before.flag("selected") == false)
        let generation = workspace.drawing(of: "shell").generation

        workspace.send(.fields(["pick": .string("s3")]), to: "shell")

        #expect(workspace.drawing(of: "shell").generation > generation)
        let after = workspace.part(1, key: .number(3), of: "shell")
        #expect(after.flag("selected") == true)
        #expect(after != before)
    }

    @Test func aMissingFunctionIsAMarkNotACrash() throws {
        let app = try Sandbox(["main.luau": lazyList(count: 3)])
        let workspace = app.workspace()
        workspace.reload()

        let node = workspace.part(9, key: .number(1), of: "shell")
        #expect(node.kind == .invalid)
        #expect(node.problem?.contains("that view is gone") == true)
    }

    @Test func aRowReadsTheDataItsViewBuilt() throws {
        let app = try Sandbox(["main.luau": lazyList(count: 30)])
        let workspace = app.workspace()
        workspace.reload()

        workspace.send(.fields(["msg": .string("query"), "value": .string("Session 2")]), to: "shell")

        let tree = try #require(workspace.drawing(of: "shell").tree)
        #expect(tree.lazyRows?.count == 11)
        #expect(workspace.part(1, key: .number(2), of: "shell").text == "Session 20")
    }

    @Test func anUpdateRedrawsOnlyItsMod() throws {
        let app = try Sandbox([
            "main.luau": """
            return mod { view = function() return ui.column { ui.region { "left" } } end }
            """,
            "mods/a/main.luau": """
            return mod {
                region = "left",
                init = function() return { n = 0 } end,
                update = function(state) state.n += 1 end,
                view = function(state) return ui.text { "a " .. state.n } end,
            }
            """,
            "mods/b/main.luau": """
            return mod { region = "left", view = function() return ui.text { "b" } end }
            """,
        ])
        let workspace = app.workspace()
        workspace.reload()
        let b = workspace.drawing(of: "b").generation
        let main = workspace.drawing(of: "shell").generation

        workspace.send(.string("go"), to: "a")

        #expect(workspace.drawing(of: "a").tree?.text == "a 1")
        #expect(workspace.drawing(of: "b").generation == b)
        #expect(workspace.drawing(of: "shell").generation == main)
    }

    @Test func equalTreesHaveEqualDigestsAndAChangeShowsUp() throws {
        let one = Node(.fields(["type": .string("text"), "text": .string("hi")]))
        let two = Node(.fields(["type": .string("text"), "text": .string("hi")]))
        let three = Node(.fields(["type": .string("text"), "text": .string("ho")]))
        #expect(one == two)
        #expect(one != three)

        let row = { (child: Node) in
            Node(.table(array: [], fields: ["type": .string("row")]))
                .digest == Node(.table(array: [], fields: ["type": .string("row")])).digest && child == child
        }
        #expect(row(one))
        let deep = Node(.table(array: [.fields(["type": .string("text"), "text": .string("a")])], fields: ["type": .string("row")]))
        let deeper = Node(.table(array: [.fields(["type": .string("text"), "text": .string("b")])], fields: ["type": .string("row")]))
        #expect(deep != deeper, "a change deep down changes the root's digest")
    }

    @Test func everyNewElementIsKnown() throws {
        let kinds = Node.Kind.allCases.filter { $0 != .invalid }.map(\.rawValue)
        let body = kinds.map { "ui.\($0) {}" }.joined(separator: ",\n")
        let app = try Sandbox(["main.luau": "return mod { view = function() return ui.column {\n\(body)\n} end }"])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.drawing(of: "shell").tree)
        #expect(tree.problems.isEmpty)
        #expect(tree.children.map(\.kind.rawValue) == kinds)
    }

    @Test func aFirstElementStaysAChildNotThePrimaryProp() throws {
        let app = try Sandbox(["main.luau": """
        return mod { view = function()
            return ui.column { ui.link { ui.text { "inside" }, route = "r" }, ui.link { "Open", url = "https://x.dev" } }
        end }
        """])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.drawing(of: "shell").tree)
        #expect(tree.children[0].string("text") == nil)
        #expect(tree.children[0].children.first?.text == "inside")
        #expect(tree.children[1].string("text") == "Open")
    }

    @Test func overlaysAndPropElementsAreRead() throws {
        let app = try Sandbox(["main.luau": """
        return mod { view = function()
            return ui.list {
                toolbar = { ui.button { icon = "plus", place = "primary" }, ui.menu { "More" } },
                sheet = { open = true, dismiss = "closed", ui.text { "inside" } },
                swipe = { ui.button { "Delete", role = "destructive" } },
            }
        end }
        """])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.drawing(of: "shell").tree)
        #expect(tree.elements("toolbar").map(\.kind) == [.button, .menu])
        let sheet = try #require(tree.overlay("sheet"))
        #expect(sheet.open)
        #expect(sheet.fields["dismiss"] == .string("closed"))
        #expect(sheet.content.first?.text == "inside")
        #expect(tree.elements("swipe").first?.string("role") == "destructive")
    }
}

/// A provider that publishes a count and answers what it's asked.
private final class Counter: Provider {
    let name = "counter"
    var link: ProviderLink?
    var heard: [LuauValue] = []

    func start(_ link: ProviderLink) {
        self.link = link
        link.publish(.fields(["count": .number(1)]))
    }

    func receive(_ message: LuauValue, from mod: String?) {
        heard.append(message)
        if let mod { link?.send(.fields(["reply": .string("done")]), to: mod) }
    }
}

@Suite("Providers")
struct ProviderTests {
    private let reader = """
    return mod {
        init = function() return { reply = "" } end,
        update = function(state, msg)
            if msg == "ask" then return state, { { to = "provider:counter", msg = { want = 1 } } } end
            if type(msg) == "table" and msg.reply then state.reply = msg.reply end
        end,
        view = function(state, app)
            return ui.text { (if app.counter then tostring(app.counter.count) else "none") .. " " .. state.reply }
        end,
    }
    """

    @Test func aModReadsWhatAProviderPublishes() throws {
        let app = try Sandbox(["main.luau": reader])
        let workspace = app.workspace()
        let counter = Counter()
        workspace.attach(counter)
        workspace.reload()

        #expect(workspace.drawing(of: "shell").tree?.text == "1 ")
        counter.link?.publish(.fields(["count": .number(7)]))
        #expect(workspace.drawing(of: "shell").tree?.text == "7 ")
    }

    @Test func aModAsksAndHearsBack() throws {
        let app = try Sandbox(["main.luau": reader])
        let workspace = app.workspace()
        let counter = Counter()
        workspace.attach(counter)
        workspace.reload()

        workspace.send(.string("ask"), to: "shell")

        #expect(counter.heard == [.fields(["want": .number(1)])])
        #expect(workspace.drawing(of: "shell").tree?.text == "1 done")
    }

    @Test func anUnknownProviderIsAProblem() throws {
        let app = try Sandbox(["main.luau": reader])
        let workspace = app.workspace()
        workspace.reload()

        workspace.send(.string("ask"), to: "shell")
        #expect(workspace.problems["provider:counter"] != nil)
    }

    @Test func modsThatDontReadAProviderDontRedraw() throws {
        let app = try Sandbox([
            "main.luau": "return mod { view = function() return ui.region { \"x\" } end }",
            "mods/reader/main.luau": reader.replacingOccurrences(of: "return mod {", with: "return mod { region = \"x\","),
        ])
        let workspace = app.workspace()
        let counter = Counter()
        workspace.attach(counter)
        workspace.reload()
        let main = workspace.drawing(of: "shell").generation

        counter.link?.publish(.fields(["count": .number(2)]))

        #expect(workspace.drawing(of: "reader").tree?.text == "2 ")
        #expect(workspace.drawing(of: "shell").generation == main)
    }
}

/// A provider that publishes only when told.
private final class Quiet: Provider {
    let name = "counter"
    var link: ProviderLink?

    func start(_ link: ProviderLink) {
        self.link = link
    }
}

@Suite("Provider data")
struct ProviderDataTests {
    @Test func dataIsNilUntilTheFirstPublishAndGoesOutOnItsTopic() throws {
        let app = try Sandbox([
            "main.luau": """
            return mod { view = function(_, app) return ui.text { if app.counter then "some" else "none" } end }
            """,
            "mods/watch/main.luau": """
            return mod {
                subscribe = { "provider/counter" },
                init = function() return { heard = 0 } end,
                update = function(state, msg) if msg.topic == "provider/counter" then state.heard = msg.value.count end end,
                view = function(state) return ui.text { tostring(state.heard) } end,
            }
            """,
        ])
        let workspace = app.workspace()
        let quiet = Quiet()
        workspace.attach(quiet)
        workspace.reload()
        #expect(workspace.drawing(of: "shell").tree?.text == "none")
        let watch = workspace.drawing(of: "watch").generation

        quiet.link?.publish(.fields(["count": .number(4)]))

        #expect(workspace.drawing(of: "shell").tree?.text == "some")
        #expect(workspace.drawing(of: "watch").tree?.text == "4")
        #expect(workspace.drawing(of: "watch").generation == watch + 1, "it read no app.counter, so only the topic redrew it")
    }
}

@Suite("Context")
struct ContextTests {
    @Test func aModSeesTheScenePhaseAndRedrawsWhenItChanges() throws {
        let app = try Sandbox(["main.luau": "return mod { view = function(_, app) return ui.text { app.phase } end }"])
        let workspace = app.workspace()
        workspace.reload()
        #expect(workspace.drawing(of: "shell").tree?.text == "active")

        workspace.context.phase = "background"

        #expect(workspace.drawing(of: "shell").tree?.text == "background")
    }
}
