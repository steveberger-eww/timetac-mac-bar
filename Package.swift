// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTacBar",
    platforms: [.macOS(.v14)],
    targets: [
        // All logic lives here so it can be unit tested. The executable is a thin shell.
        .target(
            name: "TimeTacKit",
            path: "Sources/TimeTacKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "TimeTacBar",
            dependencies: ["TimeTacKit"],
            path: "Sources/TimeTacBar",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TimeTacKitTests",
            dependencies: ["TimeTacKit"],
            path: "Tests/TimeTacKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
