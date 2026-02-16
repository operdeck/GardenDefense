// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GardenDefense",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "GardenDefense", targets: ["GardenDefenseApp"])
    ],
    targets: [
        .executableTarget(
            name: "GardenDefenseApp",
            path: "Sources/GardenDefenseApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
