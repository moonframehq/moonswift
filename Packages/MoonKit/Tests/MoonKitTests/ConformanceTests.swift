import Foundation
import Testing

@testable import MoonKit
@testable import MoonUI

/// The conformance suite of `conformance/`: the same mods Moonframe's tests
/// run, which must draw the same trees and send the same messages here.
/// See conformance/README.md for the format.
@Suite("Conformance")
struct ConformanceTests {
    nonisolated static let folder = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../conformance").standardized

    nonisolated static let cases: [String] = {
        let found = try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "cases").path)
        return (found ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }()

    @Test func thereAreCases() {
        #expect(Self.cases.count >= 5)
    }

    @Test(arguments: cases)
    func aCaseDrawsAsMoonframeDoes(_ name: String) throws {
        let root = Self.folder.appending(path: "cases/\(name)")
        let data = try Data(contentsOf: root.appending(path: "case.json"))
        let steps = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["steps"] as? [Any])

        let workspace = Workspace(folders: Folders(builtin: root))
        var recorders: [String: Recorder] = [:]
        for case let step as [String: Any] in steps {
            for name in Self.providers(in: step) where recorders[name] == nil {
                let recorder = Recorder(name: name)
                recorders[name] = recorder
                workspace.attach(recorder)
            }
        }
        workspace.reload()
        try expectNoProblems(workspace, after: "loading")

        var outbox: [LuauValue] = []
        for recorder in recorders.values { recorder.heard = { outbox.append($0) } }

        for (index, item) in steps.enumerated() {
            let step = try #require(item as? [String: Any])
            let at = "\(name) step \(index + 1)"
            if let message = step["send"] {
                workspace.send(Self.value(message), to: try #require(step["to"] as? String))
            } else if let provider = step["publish"] as? String {
                recorders[provider]?.link?.publish(Self.value(step["data"] ?? [:] as [String: Any]))
            } else if let expected = step["expect"] as? [String: Any] {
                for (mod, tree) in expected.sorted(by: { $0.key < $1.key }) {
                    let actual = try Self.tree(of: mod, in: workspace)
                    #expect(!(tree is NSNull), "\(at): \(mod) has no tree yet; MoonSwift draws:\n\(Self.json(actual))")
                    if !(tree is NSNull) {
                        let wanted = Self.value(tree)
                        #expect(actual == wanted, "\(at): \(mod) draws\n\(Self.json(actual))\nnot\n\(Self.json(wanted))")
                    }
                }
            } else if let expected = step["outbox"] as? [Any] {
                let wanted = expected.map(Self.value)
                #expect(outbox == wanted, "\(at): providers heard \(outbox.map(\.summary)), not \(wanted.map(\.summary))")
                outbox = []
            } else if let regions = step["regions"] as? [String: [String]] {
                for (region, mods) in regions {
                    #expect(workspace.mods(in: region) == mods, "\(at): region \(region)")
                }
            } else {
                Issue.record("\(at): a step this runner doesn't know: \(step.keys.sorted())")
            }
            try expectNoProblems(workspace, after: at)
        }
    }

    @Test func everySharedIconHasASymbol() throws {
        let names = try String(contentsOf: Self.folder.appending(path: "icons.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        #expect(names.count > 100)
        let missing = names.filter { Icons.symbols[$0] == nil }
        #expect(missing.isEmpty, "no SF Symbol for \(missing)")
    }

    // MARK: Running

    private func expectNoProblems(_ workspace: Workspace, after step: String) throws {
        #expect(workspace.problems.isEmpty, "\(step): \(workspace.problems.values.map { "\($0.file): \($0.message)" })")
        for (mod, tree) in workspace.trees {
            #expect(tree.problems.isEmpty, "\(step): \(mod) draws \(tree.problems)")
        }
    }

    /// Providers a step names, which get a recorder in their place.
    private static func providers(in step: [String: Any]) -> [String] {
        var names: [String] = []
        if let name = step["publish"] as? String { names.append(name) }
        for case let entry as [String: Any] in step["outbox"] as? [Any] ?? [] {
            if let name = entry["to"] as? String { names.append(name) }
        }
        return names
    }

    /// A mod's view as data, the way the README writes trees.
    private static func tree(of mod: String, in workspace: Workspace) throws -> LuauValue {
        let raw = try #require(try workspace.rawView(of: mod), "\(mod) drew nothing")
        return try canonical(raw, of: mod, in: workspace)
    }

    private static func canonical(_ value: LuauValue, of mod: String, in workspace: Workspace) throws -> LuauValue {
        guard case .table(let array, var fields) = value else { return value }
        if let function = fields["__function"]?.number, fields.count == 1, array.isEmpty {
            _ = function
            return .string("<function>")
        }
        let element = fields["type"] != nil
        fields["__line"] = nil
        var items = element ? array.filter { $0 != .bool(false) } : array
        items = try items.map { try canonical($0, of: mod, in: workspace) }
        if element, fields["type"] == .string("list"), let row = fields["row"]?["__function"]?.number {
            let count = min(50, Int(fields["count"]?.number ?? 0))
            fields["rows"] = .table(array: try (0..<count).map { index in
                let built = try workspace.rawCall(Int(row), with: .number(Double(index + 1)), of: mod)
                return try canonical(built ?? .bool(false), of: mod, in: workspace)
            }, fields: [:])
        }
        var out: [String: LuauValue] = [:]
        for (key, item) in fields {
            out[key] = key == "rows" ? item : try canonical(item, of: mod, in: workspace)
        }
        if out.isEmpty { return .table(array: items, fields: [:]) }
        if !items.isEmpty { out["children"] = .table(array: items, fields: [:]) }
        return .fields(out)
    }

    /// JSON as a value the same shape `canonical` makes.
    static func value(_ json: Any) -> LuauValue {
        switch json {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            .bool(number.boolValue)
        case let number as NSNumber: .number(number.doubleValue)
        case let text as String: .string(text)
        case let list as [Any]: .table(array: list.map(value), fields: [:])
        case let object as [String: Any]:
            object.isEmpty ? .emptyTable : .fields(object.mapValues(value))
        default: .bool(false)
        }
    }

    /// A value as the README's JSON, for messages.
    static func json(_ value: LuauValue) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: plain(value), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        ) else { return value.summary }
        return String(decoding: data, as: UTF8.self)
    }

    private static func plain(_ value: LuauValue) -> Any {
        switch value {
        case .bool(let flag): flag
        case .number(let number): number == number.rounded() && abs(number) < 1e15 ? Int(number) as Any : number
        case .string(let text): text
        case .table(let array, let fields):
            fields.isEmpty ? array.map(plain) as Any : fields.mapValues(plain) as Any
        }
    }
}

/// Stands in for a provider a case names: it publishes when the case says
/// and notes what mods send it.
private final class Recorder: Provider {
    let name: String
    var link: ProviderLink?
    var heard: (LuauValue) -> Void = { _ in }

    init(name: String) {
        self.name = name
    }

    func start(_ link: ProviderLink) {
        self.link = link
    }

    func receive(_ message: LuauValue, from mod: String?) {
        heard(.fields(["to": .string(name), "from": .string(mod ?? ""), "msg": message]))
    }
}
