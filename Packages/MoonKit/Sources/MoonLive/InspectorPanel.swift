import MoonKit
import MoonUI
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The card for the picked element: what it is, which file and line drew it,
/// what's around it, and that file, editable, with the window following.
struct InspectorPanel: View {
    let selection: Selection

    @Environment(Workspace.self) private var workspace
    @Environment(Inspection.self) private var inspection

    @State private var buffer = ""
    /// What the file held when last read or saved: anything else in the
    /// buffer is the user's typing.
    @State private var saved = ""
    @State private var saving: Task<Void, Never>?
    @State private var failure: String?
    @State private var copied = false

    private var file: String { workspace.file(of: selection.mod) }
    private var node: Node? { workspace.trees[selection.mod]?.node(at: selection.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            location
            trail
            properties
            source
        }
        .padding(14)
        .task(id: file) { read() }
        .onChange(of: workspace.reloads) { readIfChangedOutside() }
        .onChange(of: buffer) { save() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.tint)
            Text(node?.label ?? selection.label)
                .font(.headline)
                .lineLimit(2)
                .accessibilityIdentifier("moon.element")
            Spacer()
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                .labelStyle(.iconOnly)
                .help("Copy this element for an agent")
            Button("Close", systemImage: "xmark") { inspection.selection = nil }
                .labelStyle(.iconOnly)
                .help("Close the inspector")
        }
    }

    private var location: some View {
        let label = Label("\(file):\(node?.line.map(String.init) ?? "?")", systemImage: "doc.text")
            .font(.caption.monospaced())
            .accessibilityIdentifier("moon.location")
        #if os(macOS)
        return Button {
            if let url = workspace.folders.locate(file) { NSWorkspace.shared.open(url) }
        } label: {
            label
        }
        .buttonStyle(.link)
        .help("Open in your editor")
        #else
        return label
        #endif
    }

    private var trail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(selection.trail, id: \.self) { crumb in
                    Button(crumb.label.split(separator: " ").first.map(String.init) ?? crumb.label) {
                        inspection.select(crumb, in: workspace)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("\(crumb.label) in \(crumb.mod)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var properties: some View {
        let props = (node?.props ?? [:]).sorted { $0.key < $1.key }
        if !props.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(props, id: \.key) { key, value in
                    GridRow {
                        Text(key).foregroundStyle(.secondary)
                        Text(value.summary).lineLimit(1).textSelection(.enabled)
                    }
                }
            }
            .font(.caption.monospaced())
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Source").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("applies as you type").font(.caption2).foregroundStyle(.tertiary)
            }
            CodeEditor(text: $buffer, line: node?.line)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            if let message = failure ?? workspace.problems[file]?.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .accessibilityIdentifier("moon.source.problem")
            }
        }
    }

    private func read() {
        let text = workspace.folders.read(file) ?? ""
        saved = text
        buffer = text
    }

    private func readIfChangedOutside() {
        let text = workspace.folders.read(file) ?? ""
        if text != saved, saving == nil { read() }
    }

    /// Writes typing out once it pauses; the reload it causes redraws the window.
    private func save() {
        guard buffer != saved else { return }
        saving?.cancel()
        let (text, file) = (buffer, file)
        saving = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            saved = text
            saving = nil
            do {
                try workspace.write(text, to: file)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inspection.report(in: workspace), forType: .string)
        #else
        UIPasteboard.general.string = inspection.report(in: workspace)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}
