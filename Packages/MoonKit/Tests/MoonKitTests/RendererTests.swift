import SwiftUI
import Testing

import MoonKit
@testable import MoonUI

@Suite("Renderer")
struct RendererTests {
    private let keys: [LuauValue] = ["a", "b", "c"].map(LuauValue.string)

    private func list(_ props: [String: LuauValue]) -> Node {
        var fields = props
        fields["type"] = .string("list")
        return Node(.fields(fields))
    }

    @Test func movingRowsSaysWhichAndWhere() {
        var sent: [LuauValue] = []
        let editing = RowEditing(node: list(["move": .string("moved")]), keys: keys, send: { sent.append($0) })

        editing.move?(IndexSet([0]), 3)

        #expect(sent.count == 1)
        #expect(sent[0]["msg"] == .string("moved"))
        #expect(sent[0]["keys"] == .table(array: [.string("a")], fields: [:]))
        #expect(sent[0]["to"] == .number(4))
    }

    @Test func deletingRowsSaysWhich() {
        var sent: [LuauValue] = []
        let editing = RowEditing(node: list(["delete": .fields(["drop": .bool(true)])]), keys: keys, send: { sent.append($0) })

        editing.delete?(IndexSet([1, 2]))

        #expect(sent[0]["drop"] == .bool(true))
        #expect(sent[0]["keys"] == .table(array: [.string("b"), .string("c")], fields: [:]))
    }

    @Test func noMessageMeansNoEditing() {
        let editing = RowEditing(node: list([:]), keys: keys, send: { _ in })
        #expect(editing.move == nil)
        #expect(editing.delete == nil)
    }

    @Test func shortcutsParse() throws {
        let cases: [(String, Character, EventModifiers)] = [
            ("cmd+n", "n", .command), ("cmd+shift+k", "k", [.command, .shift]), ("ctrl+opt+1", "1", [.control, .option]),
        ]
        for (text, key, modifiers) in cases {
            let parsed = try #require(Shortcut.parse(text))
            #expect(parsed.0 == KeyEquivalent(key))
            #expect(parsed.1 == modifiers)
        }
    }

    @Test func aShortcutNeedsAKey() {
        #expect(Shortcut.parse("cmd+shift") == nil)
        #expect(Shortcut.parse("return")?.0 == .return)
    }

    @Test func theSystemProviderTellsTheDevice() {
        #if os(macOS)
        #expect(SystemProvider.idiom == "mac")
        #endif
    }
}
