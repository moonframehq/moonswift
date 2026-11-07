import Foundation
import MoonKit
import MoonUI
import SwiftUI
#if MOON_LIVE
import MoonLive
#endif

/// One entry point for three targets. `MOON_LIVE` is set by the ones that
/// link MoonLive: the Mac app and the iOS beta. The store target has neither.
@main
struct MoonSwiftApp: App {
    @State private var workspace = Workspace(folders: .forThisRun())
    #if MOON_LIVE
    @State private var inspection = Inspection()
    #endif
    #if MOON_LIVE && os(macOS)
    @State private var agent = AgentSession()
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("MoonSwift", id: "main") { root }
            .defaultSize(width: 1040, height: 680)
            .commands { MoonCommands(workspace: workspace, inspection: inspection) }
        #else
        WindowGroup { root }
        #endif
    }

    @ViewBuilder private var root: some View {
        #if MOON_LIVE
        LiveWindow()
            .environment(workspace)
            .environment(inspection)
            #if os(macOS)
            .environment(agent)
            #endif
            .task {
                workspace.reload()
                #if DEBUG && os(macOS)
                SelfDrive.startIfAsked(workspace: workspace, inspection: inspection, agent: agent)
                #endif
                await workspace.watch()
            }
        #else
        MoonCanvas()
            .environment(workspace)
            .task { workspace.reload() }
        #endif
    }
}

extension Folders {
    static func forThisRun() -> Folders {
        guard let bundled = Bundle.main.url(forResource: "app", withExtension: nil) else {
            fatalError("the app folder is missing from the bundle")
        }
        #if MOON_LIVE
        // `MOONSWIFT_APP` runs straight from a folder, as `just run` does.
        if let path = ProcessInfo.processInfo.environment["MOONSWIFT_APP"] {
            return Folders(builtin: URL(filePath: path))
        }
        // Otherwise edits land in a folder laid over the bundled app.
        #if os(macOS)
        let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/moonswift")
        #else
        let user = URL.documentsDirectory.appending(path: "moonswift")
        #endif
        // Back to the bundled app, as the tests start, whatever edits were left.
        if ProcessInfo.processInfo.environment["MOONSWIFT_RESET"] != nil {
            try? FileManager.default.removeItem(at: user)
        }
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        return Folders(builtin: bundled, user: user)
        #else
        return Folders(builtin: bundled)
        #endif
    }
}
