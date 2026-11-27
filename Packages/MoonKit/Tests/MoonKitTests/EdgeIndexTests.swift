import Testing

@testable import MoonKit
@testable import MoonUI

/// `ui.list { edge = true }`: what its index shows, and where each mark
/// scrolls to.
@Suite("Edge index")
struct EdgeIndexTests {
    private let list = Node(.table(array: [
        .fields([
            "type": .string("section"), "title": .string("Review requested"),
            "count": .number(3), "row": .fields(["__function": .number(1)]),
            "edge": .fields(["dots": .table(array: [.string("red"), .string("green"), .string("yellow")], fields: [:])]),
        ]),
        .fields(["type": .string("section"), "title": .string("No index"), "count": .number(2)]),
        .fields([
            "type": .string("section"), "key": .string("mine"), "count": .number(1),
            "row": .fields(["__function": .number(2)]),
            "edge": .fields(["letter": .string("M"), "dots": .table(array: [.string("teal"), .string("red")], fields: [:])]),
        ]),
    ], fields: ["type": .string("list"), "edge": .bool(true)]))

    @Test func aSectionWithEdgeGivesALetterAndADotPerRow() {
        let scope = Scope(mod: "shell", path: "", trail: [])
        let parts = EdgePart.parts(of: list, scope: scope)
        #expect(parts.map(\.letter) == ["R", "M"])
        #expect(parts[0].rows.map(\.color) == ["red", "green", "yellow"])
        #expect(parts[0].target == "edge:0")
        #expect(parts[0].rows.map(\.id) == ["edge:0/1", "edge:0/2", "edge:0/3"])
        #expect(parts[1].rows.map(\.color) == ["teal"], "no more dots than rows")
        #expect(parts[1].target == "edge:mine")
    }

    @Test func dotsPastWhatFitsAreThinnedAndLettersStay() {
        let rows = (1...40).map { (id: "r\($0)", color: "green") }
        let parts = [
            EdgePart(target: "a", letter: "A", rows: Array(rows.prefix(30))),
            EdgePart(target: "b", letter: "B", rows: Array(rows.suffix(10))),
        ]
        #expect(EdgePart.entries(parts, capacity: 100).count == 42)
        let thinned = EdgePart.entries(parts, capacity: 12)
        #expect(thinned.filter { $0.letter != nil }.map(\.target) == ["a", "b"])
        #expect(thinned.count <= 12)
        #expect(thinned.contains { $0.target == "r31" }, "each section keeps its first row")
    }
}
