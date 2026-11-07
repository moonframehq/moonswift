import Foundation
import MoonKit

extension Workspace {
    /// Saves an edit of `file` and applies it at once.
    public func write(_ text: String, to file: String) throws {
        let url = folders.writable(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    /// Follows the folders until cancelled. iOS has no FSEvents, and nothing
    /// outside the app writes there: `write` reloads by itself.
    public func watch() async {
        #if os(macOS)
        for await _ in folderChanges(folders.all) { reload() }
        #endif
    }
}
