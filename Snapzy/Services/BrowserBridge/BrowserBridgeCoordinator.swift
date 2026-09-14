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

  /// Explicitly `nonisolated`: without this, the compiler synthesizes an
  /// *isolated* deinit for this `@MainActor` `ObservableObject` (to safely
  /// tear down the `@Published` property's Combine publisher on the main
  /// actor), which hops through
  /// `swift_task_deinitOnExecutorMainActorBackDeploy` at deallocation
  /// time. That back-deployment shim crashes with heap corruption
  /// ("pointer being freed was not allocated") on this project's CI
  /// toolchain/OS combination when a *non-singleton* instance of this
  /// class is deinitialized -- confirmed via a real symbolicated crash
  /// report (see docs/REFERENCE_PROVENANCE.md) whose faulting frame is
  /// exactly `BrowserBridgeCoordinator.__deallocating_deinit` calling
  /// into that shim. Nothing here actually needs actor-isolated cleanup
  /// (`server`/`isRunning`/`socketURL` are all safe to release from any
  /// thread), so forcing a plain, non-isolated deinit sidesteps the
  /// buggy runtime path entirely rather than working around it in tests.
  nonisolated deinit {}
}
