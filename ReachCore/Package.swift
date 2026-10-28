// swift-tools-version:5.9
import PackageDescription

// Platform-independent logic for Reach. Nothing here imports CoreLocation,
// CoreMotion or UIKit, so the whole package builds and tests on macOS and Linux.
let package = Package(
    name: "ReachCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReachCore", targets: ["ReachCore"]),
    ],
    targets: [
        // Uber H3 v4.1.0 (Apache-2.0), vendored unmodified apart from generating h3api.h.
        .target(
            name: "CH3",
            path: "Sources/CH3",
            exclude: ["LICENSE", "NOTICE"],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src/internal")],
            linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]
        ),
        .target(name: "ReachCore", dependencies: ["CH3"]),
        .testTarget(
            name: "ReachCoreTests",
            dependencies: ["ReachCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
