// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DaikinCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DaikinCore", targets: ["DaikinCore"]),
    ],
    targets: [
        .target(name: "DaikinCore"),
        .testTarget(
            name: "DaikinCoreTests",
            dependencies: ["DaikinCore"],
            resources: [.copy("Resources/daikin280_message_construction.txt")]
        ),
    ]
)
