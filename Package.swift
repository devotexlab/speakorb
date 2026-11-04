// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Speakorb",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Speakorb", targets: ["SpeakorbApp"]),
        .library(name: "SpeakorbCore", targets: ["SpeakorbCore"]),
    ],
    targets: [
        .target(name: "SpeakorbCore"),
        .target(name: "SpeakorbProviders", dependencies: ["SpeakorbCore"]),
        .target(
            name: "SpeakorbStorage",
            dependencies: ["SpeakorbCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "SpeakorbCapture",
            dependencies: ["SpeakorbCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "SpeakorbApp",
            dependencies: ["SpeakorbCore", "SpeakorbProviders", "SpeakorbStorage", "SpeakorbCapture"]
        ),
        .testTarget(name: "SpeakorbCoreTests", dependencies: ["SpeakorbCore"]),
        .testTarget(name: "SpeakorbProvidersTests", dependencies: ["SpeakorbProviders", "SpeakorbCore"]),
        .testTarget(name: "SpeakorbStorageTests", dependencies: ["SpeakorbStorage", "SpeakorbCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
