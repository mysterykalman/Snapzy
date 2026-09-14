//
//  ContactSheetGeneratorTests.swift
//  SnapzyTests
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ContactSheetGeneratorTests: XCTestCase {

  private func makeSolidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  func testReturnsNilForEmptyImageList() {
    XCTAssertNil(ContactSheetGenerator.generate(images: [], layout: .grid(columns: 2)))
  }

  func testGridLayoutSizesToRowsAndColumns() throws {
    let images = (0..<5).map { _ in makeSolidImage(width: 100, height: 50) }
    let sheet = try XCTUnwrap(ContactSheetGenerator.generate(images: images, layout: .grid(columns: 2), spacing: 10))

    // 5 images at 2 columns -> 3 rows. Width: 2 cols * 100 + 3 * spacing.
    // Height: 3 rows * 50 + 4 * spacing.
    XCTAssertEqual(sheet.width, Int((2 * 100 + 3 * 10)))
    XCTAssertEqual(sheet.height, Int((3 * 50 + 4 * 10)))
  }

  func testHorizontalStackPlacesAllImagesInOneRow() throws {
    let images = [makeSolidImage(width: 40, height: 40), makeSolidImage(width: 40, height: 40)]
    let sheet = try XCTUnwrap(ContactSheetGenerator.generate(images: images, layout: .horizontalStack, spacing: 5))
    XCTAssertEqual(sheet.height, Int(40 + 2 * 5))
    XCTAssertEqual(sheet.width, Int(2 * 40 + 3 * 5))
  }

  func testMismatchedLabelCountReservesNoLabelSpace() throws {
    let images = [makeSolidImage(width: 40, height: 40)]
    let withoutLabels = try XCTUnwrap(ContactSheetGenerator.generate(images: images, layout: .verticalStack, spacing: 0, labels: ["a", "b"]))
    let noLabelsAtAll = try XCTUnwrap(ContactSheetGenerator.generate(images: images, layout: .verticalStack, spacing: 0))
    XCTAssertEqual(withoutLabels.height, noLabelsAtAll.height)
  }

  func testLabelCountMatchingImagesReservesLabelSpace() throws {
    let images = [makeSolidImage(width: 40, height: 40)]
    let withLabels = try XCTUnwrap(ContactSheetGenerator.generate(images: images, layout: .verticalStack, spacing: 0, labels: ["a"], labelHeight: 24))
    let withoutLabels = try XCTUnwrap(ContactSheetGenerator.generate(images: images, layout: .verticalStack, spacing: 0))
    XCTAssertEqual(withLabels.height, withoutLabels.height + 24)
  }
}
