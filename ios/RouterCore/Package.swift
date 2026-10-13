// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RouterCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RouterCore", targets: ["RouterCore"])
    ],
    targets: [
        .target(
            name: "RouterCore",
            path: "Sources/RouterCore"
        ),
        .testTarget(
            name: "RouterCoreTests",
            dependencies: ["RouterCore"],
            path: "Tests/RouterCoreTests"
        )
    ]
)
