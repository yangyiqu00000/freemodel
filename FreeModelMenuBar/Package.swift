// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreeModelMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FreeModelMenuBar",
            targets: ["FreeModelMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FreeModelMenuBar",
            path: "FreeModelMenuBar"
        )
    ]
)
