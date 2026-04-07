// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BADDADApp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "BADDADApp",
            targets: ["BADDADApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BADDADApp",
            path: "Sources/BADDADApp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)