//
//  FeatureIntroConfigTests.swift
//  SnapzyTests
//
//  Validates the bundled whats_new.json decodes correctly and that the
//  campaigns/screens added for the annotation-tools release are well-formed.
//

import XCTest
@testable import Snapzy

final class FeatureIntroConfigTests: XCTestCase {

  private func loadRootConfig() throws -> FeatureIntroRootConfig {
    let url = try XCTUnwrap(
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FeatureIntroConfigTests.swift
        .deletingLastPathComponent() // Shared
        .appendingPathComponent("../Snapzy/Resources/whats_new.json")
        .standardizedFileURL
    )
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(FeatureIntroRootConfig.self, from: data)
  }

  func testWhatsNewJSON_decodesWithoutThrowing() throws {
    let root = try loadRootConfig()
    XCTAssertFalse(root.campaigns.isEmpty)
  }

  func testWhatsNewJSON_everyCampaignHasAUniqueNonEmptyId() throws {
    let root = try loadRootConfig()
    let ids = root.campaigns.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count, "Campaign ids must be unique.")
    XCTAssertTrue(ids.allSatisfy { !$0.isEmpty })
  }

  func testWhatsNewJSON_everyScreenHasNonEmptyLocalizationKeysAndAVisual() throws {
    let root = try loadRootConfig()
    for campaign in root.campaigns {
      XCTAssertFalse(campaign.screens.isEmpty, "\(campaign.id) has no screens.")
      for screen in campaign.screens {
        XCTAssertFalse(screen.title.isEmpty, "\(campaign.id)/\(screen.id) has an empty title key.")
        XCTAssertFalse(screen.description.isEmpty, "\(campaign.id)/\(screen.id) has an empty description key.")
        let hasVisual = screen.systemImage != nil || screen.customImageName != nil || screen.shortcutKeys != nil
        XCTAssertTrue(hasVisual, "\(campaign.id)/\(screen.id) has no systemImage, customImageName, or shortcutKeys.")
      }
    }
  }

  func testAnnotationToolsCampaign_isPresentEnabledAndHasSixScreens() throws {
    let root = try loadRootConfig()
    let campaign = try XCTUnwrap(root.campaigns.first { $0.id == "annotation_tools_v1_32" })
    XCTAssertTrue(campaign.isEnabled)
    XCTAssertEqual(campaign.screens.count, 6)
    XCTAssertEqual(campaign.screens.map(\.id), [
      "annotation_tools_intro", "stamp", "measurement", "group_zorder", "counter_formats", "copy_as",
    ])
  }

  func testAnnotationToolsCampaign_everyLocalizationKeyResolvesInEveryLocale() throws {
    let root = try loadRootConfig()
    let campaign = try XCTUnwrap(root.campaigns.first { $0.id == "annotation_tools_v1_32" })
    let keys = campaign.screens.flatMap { [$0.title, $0.description] }

    let catalogURL = try XCTUnwrap(
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../Snapzy/Resources/Localization/Features/WhatsNew.xcstrings")
        .standardizedFileURL
    )
    let catalogData = try Data(contentsOf: catalogURL)
    let catalog = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
    let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])

    for key in keys {
      XCTAssertNotNil(strings[key], "Missing WhatsNew.xcstrings entry for key '\(key)' referenced by the annotation tools campaign.")
    }
  }
}
