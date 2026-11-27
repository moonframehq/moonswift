import MoonKit
import SwiftUI

/// `ui.markdown { text }`: an agent's answer as a document: headings,
/// paragraphs, lists, quotes and code blocks, with inline emphasis, code
/// and links. Parsed in Swift, as it may stream a token at a time; the
/// element's digest keeps an unchanged answer from being parsed again.
struct MarkdownNode: View {
    let node: Node

    var body: some View {
        let blocks = MarkdownBlock.parse(node.string("text") ?? "")
        VStack(alignment: .leading, spacing: node.number("gap").map { CGFloat($0) } ?? 12) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlockView(block: blocks[index])
            }
        }
        .textSelection(.enabled)
    }
}

/// One block of a markdown document.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case quote(String)
    case code(String)

    /// Splits `text` into blocks. Lines continue a paragraph or list item
    /// until a blank line or the next marker, as GitHub reads them.
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [String] = []
        var numbered = false
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !items.isEmpty { blocks.append(numbered ? .numbered(items) : .bullets(items)) }
            paragraph = []
            items = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                flush()
            } else if let level = Self.heading(line) {
                flush()
                blocks.append(.heading(level: level, text: String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("> ") {
                flush()
                blocks.append(.quote(String(line.dropFirst(2))))
            } else if let item = Self.bullet(line) {
                if !paragraph.isEmpty || (numbered && !items.isEmpty) { flush() }
                numbered = false
                items.append(item)
            } else if let item = Self.numberedItem(line) {
                if !paragraph.isEmpty || (!numbered && !items.isEmpty) { flush() }
                numbered = true
                items.append(item)
            } else if !items.isEmpty {
                items[items.count - 1] += " " + line
            } else {
                paragraph.append(line)
            }
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) { return String(line.dropFirst(2)) }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(line.dropFirst(digits.count + 2))
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Self.inline(text).font(level <= 1 ? .title2.weight(.semibold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, 4)
        case .paragraph(let text):
            Self.inline(text)
        case .bullets(let items):
            list(items) { _ in "•" }
        case .numbered(let items):
            list(items) { "\($0 + 1)." }
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle().fill(.tertiary).frame(width: 3)
                Self.inline(text).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: text).font(.callout.monospaced()).padding(12)
            }
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
    }

    private func list(_ items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: marker(index)).foregroundStyle(.secondary).monospacedDigit()
                    Self.inline(items[index])
                }
            }
        }
    }

    /// Emphasis, code and links inside a block.
    static func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) { return Text(attributed) }
        return Text(verbatim: text)
    }
}
