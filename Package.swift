// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ledge", targets: ["Ledge"])
    ],
    dependencies: [
        // The terminal emulator behind terminal tabs. Approved as Ledge's one
        // third-party runtime dependency; see AGENTS.md.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.20.0"))
    ],
    targets: [
        .executableTarget(
            name: "Ledge",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Ledge"
        ),
        .testTarget(
            name: "LedgeTests",
            dependencies: ["Ledge"],
            path: "Tests/LedgeTests"
        )
    ]
)
