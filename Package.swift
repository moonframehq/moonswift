// swift-tools-version: 6.2
// MoonKit for apps that fetch this repository with SwiftPM, which reads a
// manifest only at a repository's root. It names the same sources as
// `Packages/MoonKit/Package.swift`, where MoonKit is developed and tested,
// without the tests or the `moon` tool. Keep the two in step.
import PackageDescription

let sources = "Packages/MoonKit/Sources"

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
        // Never link this into an App Store build: see README.md.
        .library(name: "MoonLive", targets: ["MoonLive"]),
    ],
    targets: [
        .target(
            name: "CLuau",
            path: "\(sources)/CLuau",
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
        .target(name: "MoonKit", dependencies: ["CLuau"], path: "\(sources)/MoonKit", swiftSettings: isolated),
        .target(name: "MoonUI", dependencies: ["MoonKit"], path: "\(sources)/MoonUI", swiftSettings: isolated),
        .target(name: "MoonLive", dependencies: ["MoonKit", "MoonUI"], path: "\(sources)/MoonLive", swiftSettings: isolated),
    ],
    cxxLanguageStandard: .cxx17
)
