// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mic-reminder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "mic-reminder",
            path: "Sources/mic-reminder"
        )
    ]
)
