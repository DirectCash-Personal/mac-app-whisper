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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SuperWhisper",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
