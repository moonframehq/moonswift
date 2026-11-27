import MoonKit
import SwiftUI

/// The app Luau lays out, and all a store build shows.
public struct MoonCanvas: View {
    public nonisolated static let space = "moon.canvas"

    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase

    public init() {}

    public var body: some View {
        ModView(name: Workspace.shell)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
            .animation(.smooth(duration: 0.22), value: workspace.revision)
            .animation(.smooth(duration: 0.22), value: workspace.stylesheet)
            .background(alignment: .center) {
                // The shell's color runs on under the system bars.
                (workspace.stylesheet.paint("ground", dark: scheme == .dark) ?? .clear).ignoresSafeArea()
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                workspace.context.width = size.width
                workspace.context.height = size.height
            }
            .onChange(of: scheme, initial: true) { _, scheme in
                workspace.context.dark = scheme == .dark
            }
            .onChange(of: phase, initial: true) { _, phase in
                workspace.context.phase = switch phase {
                case .background: "background"
                case .inactive: "inactive"
                default: "active"
                }
            }
    }
}
