//
//  MetadataStripper.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureCore module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md). Strips EXIF/GPS/IPTC/TIFF
//  metadata from exported images ahead of external sharing.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Re-encodes image data through ImageIO with an explicit empty
/// properties dictionary — `CGImageDestinationAddImage` only carries over
/// metadata a caller *explicitly* passes as its properties argument, so
/// passing none at all (rather than trying to enumerate and delete every
/// possible EXIF/GPS/IPTC/TIFF key) is what actually guarantees nothing
/// survives, including tags this code has never heard of.
enum MetadataStripper {
  enum StripError: Error, LocalizedError {
    case invalidImageData
    case destinationCreationFailed
    case finalizeFailed

    var errorDescription: String? {
      switch self {
      case .invalidImageData: return "Could not read the image data to strip metadata from."
      case .destinationCreationFailed: return "Could not create an image destination for the stripped output."
      case .finalizeFailed: return "Could not finalize the stripped image write."
      }
    }
  }

  /// Returns real, human-inspectable metadata found in `imageData`
  /// (EXIF/GPS/IPTC/TIFF dictionaries, if present) — used both to
  /// confirm there's something to strip and, after stripping, to
  /// confirm nothing remains.
  static func metadataProperties(of imageData: Data) -> [String: Any] {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else {
      return [:]
    }
    return properties
  }

  /// Re-encodes `imageData` (any ImageIO-readable format) as `outputType`
  /// with zero metadata carried over — no EXIF, GPS, IPTC, TIFF, or any
  /// other properties dictionary at all, regardless of what keys the
  /// original format/camera/app happened to write. Pixel data itself is
  /// preserved exactly (a real decode-then-re-encode, not a lossy
  /// re-render) except for whatever precision loss the target format's
  /// own compression already implies (e.g. re-encoding as JPEG).
  static func stripMetadata(from imageData: Data, outputType: UTType = .png) throws -> Data {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw StripError.invalidImageData
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, outputType.identifier as CFString, 1, nil) else {
      throw StripError.destinationCreationFailed
    }
    // No properties dictionary passed at all — deliberately, not an
    // empty one filtering known keys, so nothing (including tags this
    // code doesn't know to look for) survives the re-encode.
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw StripError.finalizeFailed
    }
    return output as Data
  }
}
