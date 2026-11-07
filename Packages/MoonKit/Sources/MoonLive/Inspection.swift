import Foundation
import MoonKit
import MoonUI
import Observation

typealias Placed = PlacedElement

/// What was picked. The element itself is looked up in the live tree, so the
/// card follows reloads; `label` stands in if an edit removed it.
public struct Selection: Equatable, Sendable {
    public let mod: String
    public let path: String
    public let label: String
    public let trail: [Crumb]
}

/// The sparkle: pick any element in the window, as in a browser's developer
/// tools, to see which file and line drew it and change it there.
@Observable
public final class Inspection: ElementTracker {
    public private(set) var picking = false
    /// What a click would pick now.
    private(set) var aim: Placed?
    public var selection: Selection?

    /// What ↑ stepped out of, for ↓ to go back to.
    @ObservationIgnored private var inner: [Placed] = []
    @ObservationIgnored private var placed: [String: Placed] = [:]

    public init() {}

    /// Where the element at `path` of `mod` landed in the window, top left
    /// origin, if it is on screen.
    public func windowFrame(mod: String, path: String) -> CGRect? {
        placed["\(mod):\(path)"]?.windowFrame
    }

    /// Every element on screen, by label.
    public var labels: Set<String> {
        Set(placed.values.map(\.label))
    }

    public func togglePicking() {
        picking.toggle()
        aim = nil
        inner = []
    }

    public func cancelPicking() {
        if picking { togglePicking() }
    }

    public func place(_ element: PlacedElement) {
        placed[element.scope.key] = element
    }

    public func remove(_ key: String) {
        placed[key] = nil
    }

    /// Aims at the deepest element under `point`.
    func aim(at point: CGPoint?) {
        inner = []
        aim = point.flatMap { point in
            placed.values.filter { $0.frame.contains(point) }.max { lhs, rhs in
                let (left, right) = (depth(lhs), depth(rhs))
                return left != right ? left < right : area(lhs) > area(rhs)
            }
        }
    }

    private func depth(_ element: Placed) -> Int {
        element.scope.trail.count * 1000 + element.scope.path.split(separator: "/").count
    }

    private func area(_ element: Placed) -> CGFloat {
        element.frame.width * element.frame.height
    }

    /// ↑: the element around the aimed one.
    func aimOutward() {
        guard let aim, let outer = parent(of: aim) else { return }
        inner.append(aim)
        self.aim = outer
    }

    /// ↓: back to where ↑ came from.
    func aimInward() {
        if let last = inner.popLast() { aim = last }
    }

    private func parent(of element: Placed) -> Placed? {
        var path = element.scope.path.split(separator: "/").dropLast()
        let hasOwnParent = !element.scope.path.isEmpty
        while hasOwnParent {
            if let found = placed["\(element.scope.mod):\(path.joined(separator: "/"))"] { return found }
            if path.isEmpty { break }
            path = path.dropLast()
        }
        return element.scope.trail.reversed().lazy.compactMap { self.placed[$0.key] }.first
    }

    /// Takes what is aimed at, and leaves it where an agent can read it.
    func pick(in workspace: Workspace) {
        guard let aim else { return }
        select(mod: aim.scope.mod, path: aim.scope.path, label: aim.label, trail: trail(of: aim), in: workspace)
        togglePicking()
    }

    func select(_ crumb: Crumb, in workspace: Workspace) {
        guard let element = placed[crumb.key] else { return }
        select(mod: crumb.mod, path: crumb.path, label: crumb.label, trail: trail(of: element), in: workspace)
    }

    private func select(mod: String, path: String, label: String, trail: [Crumb], in workspace: Workspace) {
        selection = Selection(mod: mod, path: path, label: label, trail: trail)
        saveReport(in: workspace)
    }

    /// The elements around `element`, outermost first, ending with itself.
    private func trail(of element: Placed) -> [Crumb] {
        var crumbs = element.scope.trail
        var path: [Substring] = []
        let parts = element.scope.path.split(separator: "/")
        for part in [nil] + parts.map(Optional.some) {
            if let part { path.append(part) }
            let key = "\(element.scope.mod):\(path.joined(separator: "/"))"
            if let found = placed[key] {
                crumbs.append(Crumb(mod: found.scope.mod, path: found.scope.path, label: found.label))
            }
        }
        return crumbs
    }

    /// What's picked, in words: for the clipboard or an agent.
    public func report(in workspace: Workspace) -> String {
        guard let selection else { return "" }
        let file = workspace.file(of: selection.mod)
        let path = workspace.folders.locate(file)?.path ?? file
        let node = workspace.trees[selection.mod]?.node(at: selection.path)
        var lines = [
            "element: \(node?.label ?? selection.label)",
            "mod: \(selection.mod)",
            "at: \(path):\(node?.line.map(String.init) ?? "?")",
            "trail: \(selection.trail.map(\.label).joined(separator: " > "))",
        ]
        for (key, value) in (node?.props ?? [:]).sorted(by: { $0.key < $1.key }) {
            lines.append("\(key) = \(value.summary)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `~/.cache/moonswift/selection.md`, where agents look for "here".
    private func saveReport(in workspace: Workspace) {
        #if os(macOS)
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/moonswift")
        #else
        let folder = URL.cachesDirectory.appending(path: "moonswift")
        #endif
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? report(in: workspace).write(to: folder.appending(path: "selection.md"), atomically: true, encoding: .utf8)
    }
}
