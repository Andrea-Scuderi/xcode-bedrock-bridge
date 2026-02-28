// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "xcode-bedrock-bridge",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/andrea-scuderi/soto.git", branch: "fix-tool_use"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SotoBedrockRuntime", package: "soto"),
                .product(name: "SotoBedrock", package: "soto"),
                .product(name: "Configuration", package: "swift-configuration")
            ],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "Run",
            dependencies: ["App"],
            path: "Sources/Run"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "App",
                .product(name: "VaporTesting", package: "vapor"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
