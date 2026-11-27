import Foundation
import Testing

@testable import MoonKit

/// Every component of the library, Moonframe's, drawn from its `example`
/// as Moonframe's Components window draws it. A component that fails here
/// fails a desktop mod on a phone; what draws as a placeholder is printed,
/// the list of what MoonSwift should add next.
@Suite("Moonframe's components")
struct GalleryTests {
    @Test func everyComponentDrawsItsExample() throws {
        let library = try #require(Folders.bundledLibrary)
        let names = try FileManager.default.contentsOfDirectory(atPath: library.appending(path: "components").path)
            .filter { $0.hasSuffix(".luau") }.map { String($0.dropLast(5)) }.sorted()
        #expect(names.count > 100)

        var files = ["main.luau": #"return mod { view = function() return ui.text "gallery" end }"#]
        for name in names {
            let source = try String(contentsOf: library.appending(path: "components/\(name).luau"), encoding: .utf8)
            files["mods/c-\(name)/main.luau"] = Self.preview(source)
        }
        let app = try Sandbox(files)
        let workspace = app.workspace()
        workspace.reload()

        let problems = workspace.problems.values.map { "\($0.file): \($0.message)" }.sorted()
        #expect(problems.isEmpty, "\(problems.count) components fail:\n\(problems.joined(separator: "\n"))")
        for (mod, tree) in workspace.trees {
            #expect(tree.problems.isEmpty, "\(mod) draws \(tree.problems)")
        }
        let gaps = Dictionary(grouping: workspace.warnings.values.flatMap(\.self), by: \.self).mapValues(\.count)
        for (gap, count) in gaps.sorted(by: { $0.value > $1.value }) {
            print("gallery \(count)× \(gap): \(workspace.warnings.filter { $0.value.contains(gap) }.keys.sorted().prefix(4))")
        }
    }

    /// A mod drawing a component's example the way Moonframe's preview
    /// does: `build(example, state, app)`, with the state its `init` makes.
    private static func preview(_ source: String) -> String {
        """
        local definition = (function()
        \(source)
        end)()

        return mod {
            view = function(_, app)
                local props = definition.example or {}
                local state = if definition.init then definition.init(nil, props) else nil
                return definition.build(props, state, app)
            end,
        }
        """
    }
}
