import Foundation
import Testing

@testable import MoonKit

/// Moonframe's rules the conformance suite can't show by a tree alone.
@Suite("Moonframe's rules")
struct CompatTests {
    @Test func aKeyMoonframeWouldRejectIsAProblem() throws {
        let app = try Sandbox(["main.luau": """
        return mod { providers = { "home" }, view = function() return ui.text "x" end }
        """])
        let workspace = app.workspace()
        workspace.reload()

        let message = try #require(workspace.problem(of: "shell")?.message)
        #expect(message.contains("no key `providers`"))
    }

    @Test func aModThatLoadsLaterHearsATopicsCurrentValue() throws {
        let listener = """
        return mod {
            subscribe = { "page" },
            init = function(previous) return previous or { page = "none" } end,
            update = function(state, msg) state.page = msg.value end,
            view = function(state) return ui.text { state.page } end,
        }
        """
        let app = try Sandbox([
            "main.luau": """
            return mod {
                update = function(state, msg) return state, { send "topic:page" (msg) } end,
                view = function() return ui.text "shell" end,
            }
            """,
        ])
        let workspace = app.workspace()
        workspace.reload()
        workspace.send(.string("tasks"), to: "shell")

        try app.write(listener, to: "mods/late/main.luau")
        workspace.reload()

        #expect(workspace.trees["late"]?.text == "tasks")
        #expect(workspace.topics["page"] == .string("tasks"))
    }

    @Test func aModCantPublishAsAProvider() throws {
        let app = try Sandbox(["main.luau": """
        return mod {
            update = function(state) return state, { send "topic:provider/git" (1) } end,
            view = function() return ui.text "x" end,
        }
        """])
        let workspace = app.workspace()
        workspace.reload()
        workspace.send(.string("go"), to: "shell")

        #expect(workspace.problem(of: "shell")?.message.contains("not a mod's to publish") == true)
        #expect(workspace.topics["provider/git"] == nil)
    }

    @Test func aModCantForgeAProvidersEventToAnother() throws {
        let app = try Sandbox([
            "main.luau": """
            return mod {
                update = function(state) return state, { send "victim" { topic = "provider/git", value = { branch = "x" } } } end,
                view = function() return ui.text "x" end,
            }
            """,
            "mods/victim/main.luau": """
            return mod {
                init = function() return { heard = "nothing" } end,
                update = function(state, msg) state.heard = msg.topic end,
                view = function(state) return ui.text { state.heard } end,
            }
            """,
        ])
        let workspace = app.workspace()
        workspace.reload()
        workspace.send(.string("go"), to: "shell")

        #expect(workspace.trees["victim"]?.text == "nothing")
        #expect(workspace.problem(of: "shell") != nil)

        // Nor through a control's msg, which reaches the workspace unsigned.
        workspace.send(.fields(["topic": .string("app/url"), "value": .string("x")]), to: "victim")
        workspace.send(.string("y"), to: "topic:provider/git")
        #expect(workspace.trees["victim"]?.text == "nothing")
        #expect(workspace.topics["provider/git"] == nil)
    }

    @Test func useGivesAComponentsBuildAndAnythingElseAsItIs() throws {
        let app = try Sandbox([
            "components/pill.luau": "return component { build = function(props) return ui.badge { props.text } end }",
            "components/parts.luau": "return { title = function(text) return ui.text { text } end }",
            "main.luau": """
            local pill, parts = use "pill", use "parts"
            return mod { view = function() return ui.row { pill { text = "new" }, parts.title("hi") } end }
            """,
        ])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.trees["shell"])
        #expect(tree.children.map(\.kind) == [.badge, .text])
        #expect(tree.children.map(\.text) == ["new", "hi"])
    }

    @Test func aModsStylesSitUnderTheStylesheet() throws {
        let app = try Sandbox([
            "style.luau": #"return style { rules = { [".card"] = { radius = 4 } } }"#,
            "main.luau": """
            return mod {
                styles = { [".card"] = { radius = 12, padding = "small" } },
                view = function() return ui.column { class = "card" } end,
            }
            """,
        ])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.trees["shell"])
        let style = workspace.stylesheet(for: "shell").resolve(tree)
        #expect(style.radius == 4, "the app's rule wins")
        #expect(style.padding?.top == 4, "the mod's fills in the rest")
        #expect(workspace.stylesheet.resolve(tree).padding == nil, "and only for what the mod draws")
    }

    @Test func tokensAndTonesReadAsMoonframes() {
        let node = Node(.fields([
            "type": .string("text"), "text": .string("x"), "tone": .string("muted"), "size": .string("small"),
            "padding": .string("normal"),
        ]))
        let style = Stylesheet().resolve(node)
        #expect(style.color == "muted-foreground")
        #expect(style.font == "footnote")
        #expect(style.padding?.leading == 8)
    }

    @Test func numbersPastAnIntDontTrapTheHost() throws {
        let app = try Sandbox(["main.luau": """
        return mod { view = function()
            return ui.column {
                [math.huge] = ui.text "far",
                ui.list { count = math.huge, row = function(i) return ui.text "row" end },
                ui.list { count = -math.huge, row = { __function = math.huge } },
            }
        end }
        """])
        let workspace = app.workspace()
        workspace.reload()

        let tree = try #require(workspace.trees["shell"])
        #expect(tree.children.map(\.kind) == [.list, .list], "a math.huge key is no list position")
        #expect(tree.children[0].lazyRows?.count == 0, "nor is math.huge a count")
        #expect(tree.children[1].lazyRows == nil)

        let big = Node(.fields(["type": .string("list"), "count": .number(1e12), "row": .fields(["__function": .number(1)])]))
        #expect(big.lazyRows?.count == Node.maxRows)
    }

    @Test func theAppKnowsItIsSwiftUI() throws {
        let app = try Sandbox(["main.luau": """
        return mod { view = function(_, app)
            return ui.text { `{app.renderer} {app.window.platform} {app.dark} {app.appearance.dark}` }
        end }
        """])
        let workspace = app.workspace()
        workspace.reload()

        #expect(workspace.trees["shell"]?.text == "swiftui macos false false")
    }
}
