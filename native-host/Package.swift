// swift-tools-version: 6.0
import PackageDescription

// A standalone SwiftPM package, deliberately outside `Packages/` and the
// main Snapzy Xcode project: Chrome launches this as its own process per
// `chrome.runtime.connectNative` call, so it must build to a single
// self-contained binary rather than being linked into the app.
//
// Ported from Capso-Capture's `native-host/` (BSL 1.1, personal use
// permitted; see docs/REFERENCE_PROVENANCE.md), which itself improved on
// the original Capture app's equivalent by depending directly on
// `BrowserBridgeKit` via a relative path rather than duplicating the
// socket-path/protocol-envelope logic by hand. This package only adds the
// Chrome-facing stdio loop on top of it.
let package = Package(
  name: "SnapzyNativeHost",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "snapzy-native-host", targets: ["snapzy-native-host"]),
    .executable(name: "snapzy-bridge-verify", targets: ["snapzy-bridge-verify"]),
  ],
  dependencies: [
    .package(path: "../Packages/BrowserBridgeKit")
  ],
  targets: [
    .executableTarget(
      name: "snapzy-native-host",
      dependencies: ["BrowserBridgeKit"]
    ),
    // A committed, repeatable end-to-end check of the whole browser
    // bridge transport. Spawns the real, built snapzy-native-host binary
    // as a subprocess and drives it with Chrome's own native-messaging
    // stdio framing, while hosting the real
    // BrowserBridgeKit.BridgeSocketServer (with the same
    // BridgeInfrastructureRouter the app itself uses) to stand in for a
    // running Snapzy app. This is the closest possible verification of
    // the real path without Chrome itself.
    .executableTarget(
      name: "snapzy-bridge-verify",
      dependencies: ["BrowserBridgeKit"]
    ),
  ]
)
