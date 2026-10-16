// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Still",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Still", targets: ["Still"])],
    targets: [
        .target(name: "WritingCore"),
        .executableTarget(name: "Still", dependencies: ["WritingCore"]),
        .testTarget(name: "WritingCoreTests", dependencies: ["WritingCore"]),
        .testTarget(name: "StillTests", dependencies: ["Still", "WritingCore"])
    ],
    swiftLanguageModes: [.v5]
)
