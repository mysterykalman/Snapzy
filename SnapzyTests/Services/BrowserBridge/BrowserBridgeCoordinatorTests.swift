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

  private func temporarySocketURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("browser-bridge-coordinator-test-\(UUID().uuidString)")
      .appendingPathComponent("socket")
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
