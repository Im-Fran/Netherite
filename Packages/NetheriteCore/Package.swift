// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetheriteCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "NetheriteCore", targets: ["NetheriteCore"]),
        .executable(name: "netherite", targets: ["netherite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "NetheriteCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [.copy("Resources/Web"), .process("Resources/Localizable.xcstrings")]
        ),
        .executableTarget(
            name: "netherite",
            dependencies: [
                "NetheriteCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "NetheriteCoreTests", dependencies: ["NetheriteCore"]),
    ]
)
