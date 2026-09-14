//
//  MetadataStripperTests.swift
//  SnapzyTests
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Snapzy

final class MetadataStripperTests: XCTestCase {

  /// Encodes a tiny solid-color image as JPEG with real EXIF metadata
  /// (a GPS location) attached, so stripping has something real to
  /// verify against rather than an already-empty properties dictionary.
  private func makeJPEGWithGPSMetadata() throws -> Data {
    let width = 4
    let height = 4
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let image = { () -> CGImage? in
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
      }()
    else {
      throw XCTSkip("Could not synthesize a test image on this platform.")
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw XCTSkip("Could not create a JPEG destination on this platform.")
    }
    let gpsMetadata: [CFString: Any] = [
      kCGImagePropertyGPSLatitude: 37.7749,
      kCGImagePropertyGPSLongitude: 122.4194,
    ]
    let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: gpsMetadata]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return output as Data
  }

  func testMetadataPropertiesFindsGPSDataBeforeStripping() throws {
    let jpegData = try makeJPEGWithGPSMetadata()
    let properties = MetadataStripper.metadataProperties(of: jpegData)
    XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary as String])
  }

  func testStripMetadataRemovesGPSData() throws {
    let jpegData = try makeJPEGWithGPSMetadata()
    let stripped = try MetadataStripper.stripMetadata(from: jpegData, outputType: .jpeg)
    let propertiesAfter = MetadataStripper.metadataProperties(of: stripped)
    XCTAssertNil(propertiesAfter[kCGImagePropertyGPSDictionary as String])
  }

  func testStripMetadataPreservesPixelDimensions() throws {
    let jpegData = try makeJPEGWithGPSMetadata()
    let stripped = try MetadataStripper.stripMetadata(from: jpegData, outputType: .jpeg)

    guard
      let originalSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
      let strippedSource = CGImageSourceCreateWithData(stripped as CFData, nil),
      let originalImage = CGImageSourceCreateImageAtIndex(originalSource, 0, nil),
      let strippedImage = CGImageSourceCreateImageAtIndex(strippedSource, 0, nil)
    else {
      return XCTFail("Expected both original and stripped data to decode as images")
    }

    XCTAssertEqual(originalImage.width, strippedImage.width)
    XCTAssertEqual(originalImage.height, strippedImage.height)
  }

  func testStripMetadataThrowsOnInvalidImageData() {
    XCTAssertThrowsError(try MetadataStripper.stripMetadata(from: Data("not an image".utf8)))
  }
}
