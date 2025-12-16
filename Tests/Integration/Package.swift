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
                .product(name: "TOML", package: "swift-toml")
            ],
            path: "Sources/toml-decoder",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "toml-encoder",
            dependencies: [
                .product(name: "TOML", package: "swift-toml")
            ],
            path: "Sources/toml-encoder",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
