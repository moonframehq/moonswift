import Foundation
import Testing

import MoonKit
@testable import MoonUI

/// The pull request rows of `examples/prs` (Benchmark B6) take the short
/// ways that make them cost what hand-written SwiftUI does.
@Suite("Flat rows")
struct FlatRowTests {
    private func rows() throws -> [Node] {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../examples/prs").standardized
        let workspace = Workspace(folders: Folders(builtin: folder))
        workspace.reload()
        #expect(workspace.problems.isEmpty)
        let list = try #require(workspace.drawing(of: Workspace.shell).tree)
        let sections = list.children.compactMap(\.lazyRows)
        #expect(sections.count == 2)
        return try sections.flatMap { rows in
            try [1, 5, 3, 4].map { index in
                let row = workspace.part(rows.function, key: .number(Double(index)), of: Workspace.shell)
                #expect(row.kind == .link)
                return try #require(Optional(row))
            }
        }
    }

    private func walk(_ node: Node, _ visit: (Node) -> Void) {
        visit(node)
        node.children.forEach { walk($0, visit) }
    }

    @Test func aRowIsSixteenToThirtyElements() throws {
        for row in try rows() {
            var count = 0
            walk(row) { _ in count += 1 }
            #expect((16...32).contains(count), "a row has \(count) elements")
        }
    }

    @Test func everyStackInARowIsFixed() throws {
        for row in try rows() {
            walk(row) { node in
                guard [.row, .column, .link].contains(node.kind) else { return }
                #expect(Fixed.fits(node), "\(node.label) at line \(node.line ?? 0) is not fixed")
            }
        }
    }

    @Test func stateKeepersAreNotFixed() {
        let input = Node(.table(array: [.fields(["type": .string("input")])], fields: ["type": .string("row")]))
        #expect(!Fixed.fits(input))
        let keyed = Node(.table(array: [.fields(["type": .string("text"), "key": .string("a")])], fields: ["type": .string("row")]))
        #expect(!Fixed.fits(keyed))
        let six = Node(.table(array: Array(repeating: .fields(["type": .string("text")]), count: 6), fields: ["type": .string("row")]))
        #expect(!Fixed.fits(six))
        let children: [LuauValue] = [.fields(["type": .string("text")]), .fields(["type": .string("spacer")])]
        let plain = Node(.table(array: children, fields: ["type": .string("row")]))
        #expect(Fixed.fits(plain))
    }
}
