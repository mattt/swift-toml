// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "toml-test-harness",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "toml-decoder",
            dependencies: [
                .product(name: "TOML", package: "swift-toml-fork")
            ],
            path: "Sources/toml-decoder"
        ),
        .executableTarget(
            name: "toml-encoder",
            dependencies: [
                .product(name: "TOML", package: "swift-toml-fork")
            ],
            path: "Sources/toml-encoder"
        ),
    ]
)
