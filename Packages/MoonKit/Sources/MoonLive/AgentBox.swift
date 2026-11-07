#if os(macOS)
import MoonKit
import SwiftUI

/// Ask for a change to the picked element, and follow the agent making it.
struct AgentBox: View {
    let report: () -> String

    @Environment(Workspace.self) private var workspace
    @Environment(AgentSession.self) private var agent
    @State private var request = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !agent.entries.isEmpty { transcript }
            HStack(spacing: 6) {
                TextField("Ask for a change to this…", text: $request)
                    .textFieldStyle(.roundedBorder)
                    .disabled(agent.running)
                    .onSubmit(send)
                    .accessibilityIdentifier("moon.ask")
                if agent.running {
                    ProgressView().controlSize(.small)
                    Button("Stop", systemImage: "stop.fill") { agent.stop() }
                        .labelStyle(.iconOnly)
                } else {
                    Button("Send", systemImage: "arrow.up", action: send)
                        .labelStyle(.iconOnly)
                        .disabled(request.isEmpty)
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agent.entries) { entry in
                        Label {
                            Text(entry.text).textSelection(.enabled)
                        } icon: {
                            Image(systemName: icon(entry.kind)).foregroundStyle(tint(entry.kind))
                        }
                        .font(entry.kind == .tool ? .caption.monospaced() : .caption)
                        .foregroundStyle(entry.kind == .tool ? .secondary : .primary)
                        .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .onChange(of: agent.entries.count) {
                withAnimation { reader.scrollTo(agent.entries.last?.id, anchor: .bottom) }
            }
        }
    }

    private func icon(_ kind: AgentSession.Entry.Kind) -> String {
        switch kind {
        case .you: "person.fill"
        case .tool: "pencil"
        case .answer: "sparkles"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    private func tint(_ kind: AgentSession.Entry.Kind) -> Color {
        switch kind {
        case .answer: .accentColor
        case .problem: .orange
        default: .secondary
        }
    }

    private func send() {
        guard !request.isEmpty, !agent.running else { return }
        agent.ask(request, about: report(), in: workspace)
        request = ""
    }
}
#endif
