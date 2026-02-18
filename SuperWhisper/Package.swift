// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SuperWhisper", targets: ["SuperWhisper"]),
    ],
    targets: [
        .executableTarget(
            name: "SuperWhisper",
            path: "SuperWhisper",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SuperWhisperTests",
            dependencies: ["SuperWhisper"],
            path: "SuperWhisperTests"
        )
    ]
)
