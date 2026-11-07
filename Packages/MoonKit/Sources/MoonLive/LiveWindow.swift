import MoonKit
import MoonUI
import SwiftUI

/// The canvas, and what the host keeps for itself so a broken script can
/// never take it away: the sparkle, the reload status, and the problems.
public struct LiveWindow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(Inspection.self) private var inspection

    public init() {}

    public var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            canvas
            if let selection = inspection.selection {
                Divider()
                InspectorPanel(selection: selection)
                    .frame(width: 380)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.2), value: inspection.selection == nil)
        .toolbar { tools }
        #else
        NavigationStack {
            canvas
                .toolbar { tools }
                .toolbarTitleDisplayMode(.inline)
                .sheet(isPresented: inspectorShown) {
                    if let selection = inspection.selection {
                        InspectorPanel(selection: selection)
                            .presentationDetents([.medium, .large])
                            // The app stays usable beside it, to see edits land.
                            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    }
                }
        }
        #endif
    }

    @ToolbarContentBuilder
    private var tools: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { ReloadStatus() }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) { Sparkle() }
    }

    private var canvas: some View {
        MoonCanvas()
            .environment(\.elementTracker, inspection)
            .overlay {
                if inspection.picking { PickerOverlay() }
            }
            .safeAreaInset(edge: .bottom) { ProblemBanner() }
    }

    private var inspectorShown: Binding<Bool> {
        Binding { inspection.selection != nil } set: { shown in
            if !shown { inspection.selection = nil }
        }
    }
}

/// The sparkle: click, then click anything in the window.
struct Sparkle: View {
    @Environment(Inspection.self) private var inspection
    #if os(macOS)
    @Environment(AgentSession.self) private var agent
    private var working: Bool { agent.running }
    #else
    private let working = false
    #endif

    var body: some View {
        Button {
            inspection.togglePicking()
        } label: {
            Label("Inspect", systemImage: "sparkles")
                .foregroundStyle(inspection.picking ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .symbolEffect(.pulse, isActive: inspection.picking || working)
        }
        .help("Point at anything to see what drew it and change it (⇧⌘X)")
        .accessibilityIdentifier("moon.sparkle")
    }
}

/// How the last reload went, so a change is seen to have landed.
struct ReloadStatus: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let count = workspace.problems.count
        Label(text(count), systemImage: count == 0 ? "bolt.fill" : "exclamationmark.triangle.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption.monospacedDigit())
            .foregroundStyle(count == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            .padding(.horizontal, 8)
            .contentTransition(.numericText())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text(count))
            .accessibilityIdentifier("moon.status")
    }

    private func text(_ problems: Int) -> String {
        if problems > 0 { return problems == 1 ? "1 problem" : "\(problems) problems" }
        let milliseconds = Double(workspace.lastReload.components.attoseconds) / 1e15
            + Double(workspace.lastReload.components.seconds) * 1000
        return "reload \(workspace.reloads) · \(milliseconds.formatted(.number.precision(.fractionLength(1)))) ms"
    }
}

/// Why the window isn't showing the latest edit.
struct ProblemBanner: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let problems = workspace.problems.values.sorted { $0.file < $1.file }
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(problems) { problem in
                    Text(problem.message)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("moon.problem")
                }
                Text("Showing the last good version.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.22), in: .rect(cornerRadius: 12))
            .background(.background, in: .rect(cornerRadius: 12))
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// View-menu commands: the same keys Moonframe uses.
public struct MoonCommands: Commands {
    let workspace: Workspace
    let inspection: Inspection

    public init(workspace: Workspace, inspection: Inspection) {
        self.workspace = workspace
        self.inspection = inspection
    }

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Inspect Element") { inspection.togglePicking() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Quick Inspect") { inspection.togglePicking() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Reload") { workspace.reload() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}
