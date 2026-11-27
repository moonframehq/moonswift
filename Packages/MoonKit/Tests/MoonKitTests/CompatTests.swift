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
