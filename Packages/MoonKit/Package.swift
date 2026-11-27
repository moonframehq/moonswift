// swift-tools-version: 6.2
import PackageDescription

let isolated: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "MoonKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "MoonKit", targets: ["MoonKit"]),
        .library(name: "MoonUI", targets: ["MoonUI"]),
        .library(name: "MoonLive", targets: ["MoonLive"]),
        .executable(name: "moon", targets: ["moon"]),
    ],
    targets: [
        // Luau's sources, vendored by scripts/vendor-luau.sh, and the seam to Swift.
        .target(
            name: "CLuau",
            exclude: ["luau/LICENSE.txt", "luau/lua_LICENSE.txt", "luau/VERSION"],
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("luau/Ast/include"),
                .headerSearchPath("luau/Bytecode/include"),
                .headerSearchPath("luau/Common/include"),
                .headerSearchPath("luau/Compiler/include"),
                .headerSearchPath("luau/Compiler/src"),
                .headerSearchPath("luau/VM/src"),
                .define("LUA_API", to: "extern \"C\""),
                .define("LUACODE_API", to: "extern \"C\""),
                // Third-party code: its warnings aren't ours to fix.
                .unsafeFlags(["-w"]),
            ]
        ),
        // The headless runtime: VMs, mods, reloads, trees and styles.
        .target(name: "MoonKit", dependencies: ["CLuau"], swiftSettings: isolated),
        // Draws trees with SwiftUI. All an App Store build gets.
        .target(name: "MoonUI", dependencies: ["MoonKit"], swiftSettings: isolated),
        // Everything that changes the app while it runs: the sparkle, the
        // source editor, the file watcher and writes. App Review guideline
        // 2.5.2 rules this out, so store targets must never link it, and
        // `just store-audit` checks they don't.
        .target(name: "MoonLive", dependencies: ["MoonKit", "MoonUI"], swiftSettings: isolated),
        // `moon check <folder>`: every module loaded headlessly.
        .executableTarget(name: "moon", dependencies: ["MoonKit"], swiftSettings: isolated),
        .testTarget(name: "MoonKitTests", dependencies: ["MoonKit", "MoonUI", "MoonLive"], swiftSettings: isolated),
    ],
    cxxLanguageStandard: .cxx17
)
