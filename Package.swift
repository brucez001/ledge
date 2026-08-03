// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ledge", targets: ["Ledge"])
    ],
    targets: [
        .executableTarget(
            name: "Ledge",
            path: "Sources/Ledge"
        ),
        .testTarget(
            name: "LedgeTests",
            dependencies: ["Ledge"],
            path: "Tests/LedgeTests"
        )
    ]
)
