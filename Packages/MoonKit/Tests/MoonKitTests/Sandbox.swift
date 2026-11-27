import Foundation

@testable import MoonKit

/// A throwaway app folder.
final class Sandbox {
    let root: URL

    init(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "moon-\(UUID().uuidString)")
        for (file, text) in files { try write(text, to: file) }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ text: String, to file: String) throws {
        let url = root.appending(path: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func workspace(limits: Limits = Limits()) -> Workspace {
        Workspace(folders: Folders(builtin: root), limits: limits)
    }
}
