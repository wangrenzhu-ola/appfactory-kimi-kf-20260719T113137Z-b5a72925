// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CarbLens",
    platforms: [
        .iOS(.v14),
        .macOS(.v12)
    ],
    products: [
        .library(name: "CarbLensCore", targets: ["CarbLensCore"])
    ],
    targets: [
        .target(
            name: "CarbLensCore",
            path: "Sources/CarbLensCore"
        ),
        .testTarget(
            name: "CarbLensCoreTests",
            dependencies: ["CarbLensCore"],
            path: "Tests/CarbLensCoreTests"
        )
    ]
)
