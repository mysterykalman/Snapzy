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

/// Starts the socket server and routes every registered message type:
/// the protocol's handshake types (ping/hello/version/status) go through
/// `BridgeInfrastructureRouter`; `accessibility.audit.result` and
/// `ecommerce.audit.result` are decoded via `AccessibilityAuditMapper`/
/// `EcommerceAuditMapper` and appended to `InspectionFindingsStore`.
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
      Self.route(message, appVersion: appVersion)
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

  /// Runs on `BridgeSocketServer`'s own background dispatch queue (never
  /// MainActor), so this is `nonisolated` and only ever hops onto
  /// MainActor for the actual `InspectionFindingsStore` mutation, fired
  /// off asynchronously -- the response the extension gets back
  /// acknowledges receipt, not that the store has been updated yet,
  /// which is fine since nothing round-trips a finding back to the
  /// extension.
  nonisolated static func route(_ message: BridgeMessage, appVersion: String?) -> BridgeResponse {
    switch message.type {
    case "accessibility.audit.result":
      guard case .object(let payload) = message.payload,
        case .string(let url)? = payload["url"],
        case .string(let json)? = payload["auditJSON"]
      else {
        return .failure(id: message.id, code: BridgeErrorCode.invalidMessage, message: "Missing url/auditJSON.")
      }
      let viewportWidth = payload["viewportWidth"]?.doubleValue
      let viewportHeight = payload["viewportHeight"]?.doubleValue
      Task { @MainActor in
        do {
          try InspectionFindingsStore.shared.addAccessibilityAudit(
            json: json, page: url, viewportWidth: viewportWidth, viewportHeight: viewportHeight
          )
        } catch {
          DiagnosticLogger.shared.log(
            .warning, .browserBridge, "Failed to decode accessibility audit result",
            context: ["error": error.localizedDescription]
          )
        }
      }
      return .success(id: message.id, payload: .object(["received": .bool(true)]))

    case "ecommerce.audit.result":
      guard case .object(let payload) = message.payload,
        case .string(let url)? = payload["url"],
        case .string(let json)? = payload["snapshotJSON"]
      else {
        return .failure(id: message.id, code: BridgeErrorCode.invalidMessage, message: "Missing url/snapshotJSON.")
      }
      let viewportWidth = payload["viewportWidth"]?.doubleValue
      let viewportHeight = payload["viewportHeight"]?.doubleValue
      Task { @MainActor in
        do {
          try InspectionFindingsStore.shared.addEcommerceAudit(
            json: json, page: url, viewportWidth: viewportWidth, viewportHeight: viewportHeight
          )
        } catch {
          DiagnosticLogger.shared.log(
            .warning, .browserBridge, "Failed to decode ecommerce audit result",
            context: ["error": error.localizedDescription]
          )
        }
      }
      return .success(id: message.id, payload: .object(["received": .bool(true)]))

    default:
      return BridgeInfrastructureRouter.route(message, appName: "Snapzy", appVersion: appVersion)
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

extension JSONValue {
  fileprivate var doubleValue: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
}
