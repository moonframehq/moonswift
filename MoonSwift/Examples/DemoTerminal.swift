import MoonKit
import MoonUI
import SwiftUI

/// Sheprd's terminal, as the example's native view: what a real app would
/// draw in Swift and hand Luau by name. `ui.native { "terminal", pane = ... }`
/// places it; Luau never sees the screen's cells.
struct DemoTerminal: View {
    let context: NativeContext

    private static let lines = [
        "~/forecast main ❯ swift test",
        "Building for debugging...",
        "[42/42] Linking ForecastPackageTests",
        "Test Suite 'All tests' started.",
        "Test Suite 'ForecastWidgetTests' passed.",
        "     Executed 148 tests, with 0 failures in 2.413 seconds",
        "~/forecast main ❯ ",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.lines.indices, id: \.self) { index in
                    Text(verbatim: Self.lines[index])
                        .foregroundStyle(Self.lines[index].contains("❯") ? Color.green : Color(white: 0.9))
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("terminal.\(context.node.string("pane") ?? "")")
    }

    static var views: NativeViews {
        var views = NativeViews()
        views.register("terminal") { AnyView(DemoTerminal(context: $0)) }
        return views
    }
}
