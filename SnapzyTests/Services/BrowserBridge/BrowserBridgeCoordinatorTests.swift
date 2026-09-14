//
//  BrowserBridgeCoordinatorTests.swift
//  SnapzyTests
//
//  Verifies the app-side coordinator actually stands up a working socket
//  server and answers real infrastructure requests end-to-end, rather than
//  just compiling.
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
