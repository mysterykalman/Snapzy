//
//  BrowserBridgeCoordinatorTests.swift
//  SnapzyTests
//
//  Verifies the app-side coordinator actually stands up a working socket
//  server and answers real infrastructure requests end-to-end, rather than
//  just compiling.
//
//  HISTORICAL NOTE: these tests used to crash the CI runner's hosted test
//  process with heap corruption ("pointer being freed was not allocated")
//  immediately on entry. Root-caused via a real symbolicated .ips crash
//  report gathered by a temporary diagnostic CI workflow: the faulting
//  frame was `BrowserBridgeCoordinator.__deallocating_deinit` calling into
//  `swift_task_deinitOnExecutorMainActorBackDeploy` -- the compiler
//  synthesizes an *isolated* deinit for a `@MainActor` `ObservableObject`
//  class (to safely tear down its `@Published` Combine publisher on the
//  main actor), and that back-deployment shim has a real bug on this
//  project's CI toolchain/OS combination. It was never triggered before
//  because every other `@MainActor` `ObservableObject` in this codebase is
//  a `.shared` singleton that's never actually deinitialized during a test
//  run -- these tests were the first code to create and release a
//  transient instance. Fixed with an explicit `nonisolated deinit {}` on
//  `BrowserBridgeCoordinator` (nothing there needs actor-isolated
//  teardown), which skips the buggy runtime path entirely. Verified via
//  the same diagnostic workflow before removing the CI skip.
//

import BrowserBridgeKit
import XCTest
@testable import Snapzy

@MainActor
final class BrowserBridgeCoordinatorTests: XCTestCase {

  /// A Unix domain socket path is limited to ~103 usable bytes
  /// (`sockaddr_un.sun_path`, 104 bytes including the null terminator).
  /// `NSTemporaryDirectory()` on a CI runner can already be long enough
  /// that a full UUID-suffixed path under it overflows that limit and
  /// `bind()` fails silently into `BridgeSocketServer.ServerError
  /// .pathTooLong` — caught by `BrowserBridgeCoordinator.start()`, which
  /// just logs it, leaving `isRunning` false. `/tmp` plus a short random
  /// suffix keeps well under the limit everywhere.
  private func temporarySocketURL() -> URL {
    URL(fileURLWithPath: "/tmp")
      .appendingPathComponent("bbc-test-\(UUID().uuidString.prefix(8))")
      .appendingPathComponent("s")
  }

  func testStartAnswersPingOverTheRealSocket() throws {
    let socketURL = temporarySocketURL()
    let coordinator = BrowserBridgeCoordinator(socketURL: socketURL)
    coordinator.start()
    defer { coordinator.stop() }

    XCTAssertTrue(coordinator.isRunning)

    let client = BridgeSocketClient(socketURL: socketURL)
    let response = try client.send(BridgeMessage(type: "ping"))
    XCTAssertTrue(response.ok)
    XCTAssertEqual(response.payload, .object(["pong": .bool(true)]))
  }

  func testStopRemovesTheSocketAndRejectsFurtherConnections() throws {
    let socketURL = temporarySocketURL()
    let coordinator = BrowserBridgeCoordinator(socketURL: socketURL)
    coordinator.start()
    coordinator.stop()

    XCTAssertFalse(coordinator.isRunning)
    XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))

    let client = BridgeSocketClient(socketURL: socketURL)
    XCTAssertThrowsError(try client.send(BridgeMessage(type: "ping")))
  }

  func testStartIsIdempotentWhileAlreadyRunning() throws {
    let socketURL = temporarySocketURL()
    let coordinator = BrowserBridgeCoordinator(socketURL: socketURL)
    coordinator.start()
    defer { coordinator.stop() }
    coordinator.start() // second call must be a no-op, not a crash/re-bind attempt

    let client = BridgeSocketClient(socketURL: socketURL)
    let response = try client.send(BridgeMessage(type: "ping"))
    XCTAssertTrue(response.ok)
  }
}
