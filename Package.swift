// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-open-llm-proxy",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SotoBedrockRuntime", package: "soto"),
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
