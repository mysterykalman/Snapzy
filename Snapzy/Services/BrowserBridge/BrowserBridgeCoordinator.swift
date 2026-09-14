//
//  BrowserBridgeCoordinator.swift
//  Snapzy
//
//  Owns the app-side Unix-domain-socket IPC server that a Chrome
//  Native Messaging host process relays browser-extension requests
//  through. See docs/REFERENCE_PROVENANCE.md — transport ported from
//  Capso-Capture's BrowserBridgeKit (BSL 1.1, personal-use permitted).
//

import BrowserBridgeKit
import Combine
import Foundation

/// Infrastructure-only for now: starts the socket server and answers the
/// protocol's handshake message types (ping/hello/version/status) via
/// `BridgeInfrastructureRouter`. Real inspection/accessibility/ecommerce
/// message types are registered in `BridgeMessageValidator.registeredTypes`
/// and routed here as the corresponding native host, Chrome extension, and
/// Swift-side inspection models are ported (see docs/STRUCTURE.md).
@MainActor
final class BrowserBridgeCoordinator: ObservableObject {

  static let shared = BrowserBridgeCoordinator()

  @Published private(set) var isRunning = false

  private var server: BridgeSocketServer?
  private let socketURL: URL

  /// `socketURL` is overridable so tests can bind to a temporary path
  /// instead of the real `~/Library/Application Support/Snapzy/IPC/socket`.
  init(socketURL: URL = BridgeConfiguration.socketURL) {
    self.socketURL = socketURL
  }

  func startIfEnabled() {
    guard UserDefaults.standard.bool(forKey: PreferencesKeys.browserBridgeEnabled) else { return }
    start()
  }

  func start() {
    guard server == nil else { return }

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let newServer = BridgeSocketServer(socketURL: socketURL) { message in
      BridgeInfrastructureRouter.route(message, appName: "Snapzy", appVersion: appVersion)
    }

    do {
      try newServer.start()
      server = newServer
      isRunning = true
      DiagnosticLogger.shared.log(
        .info,
        .browserBridge,
        "Browser bridge socket server started",
        context: ["socketPath": socketURL.path]
      )
    } catch {
      DiagnosticLogger.shared.log(
        .error,
        .browserBridge,
        "Failed to start browser bridge socket server",
        context: ["error": error.localizedDescription]
      )
    }
  }

  func stop() {
    server?.stop()
    server = nil
    isRunning = false
    DiagnosticLogger.shared.log(.info, .browserBridge, "Browser bridge socket server stopped")
  }
}
