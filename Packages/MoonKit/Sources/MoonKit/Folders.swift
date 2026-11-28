import Foundation

/// The two folders of an app laid over each other, as in Moonframe: the
/// built-in one and, on top, the user's. A file in the user's wins at the
/// same path. With no user folder, edits go straight to the built-in one.
/// Under both lies the library: Moonframe's components, which an app's own
/// of the same name replace.
public struct Folders: Equatable, Sendable {
    public let builtin: URL
    public let user: URL?
    /// Read-only, never watched: the components MoonKit ships.
    public let library: URL?

    public init(builtin: URL, user: URL? = nil, library: URL? = Folders.bundledLibrary) {
        self.builtin = builtin
        self.user = user
        self.library = library
    }

    /// Moonframe's components, as MoonKit bundles them.
    public static let bundledLibrary: URL? = Bundle.module.url(forResource: "Library", withExtension: nil)

    public var all: [URL] { [builtin] + (user.map { [$0] } ?? []) }

    /// Where `file` (relative, as `mods/x/main.luau`) is read from.
    public func locate(_ file: String) -> URL? {
        for folder in all.reversed() + (library.map { [$0] } ?? []) {
            let url = folder.appending(path: file)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Where an edit of `file` is written: the built-in app stays untouched
    /// when there is a user folder, so an edit shadows it there.
    public func writable(_ file: String) -> URL {
        (user ?? builtin).appending(path: file)
    }

    public func read(_ file: String) -> String? {
        locate(file).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// The names under `folder` of either layer, sorted.
    func names(in folder: String) -> [String] {
        let found = (all + (library.map { [$0] } ?? [])).flatMap { root in
            (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: folder).path)) ?? []
        }
        return Set(found).filter { !$0.hasPrefix(".") }.sorted()
    }
}
