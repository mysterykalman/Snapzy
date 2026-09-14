// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserBridgeKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "BrowserBridgeKit", targets: ["BrowserBridgeKit"])],
    dependencies: [],
    targets: [
        .target(name: "BrowserBridgeKit"),
        .testTarget(name: "BrowserBridgeKitTests", dependencies: ["BrowserBridgeKit"]),
    ]
)
