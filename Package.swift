// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatLedger",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChatLedger", targets: ["ChatLedger"])],
    targets: [
        .executableTarget(name: "ChatLedger")
    ]
)
