import Foundation
import Photos
import XCTest

/// End-to-end UI tests exercising the real iOS Photos Share Sheet to ensure Montage's
/// Share Extension remains visible for multi-video selections and launches cleanly.
///
/// Regression guard: iOS `sharingd` hides Share Extensions whose `NSExtensionActivationRule`
/// includes `NSExtensionActivationSupportsAttachmentsWithMinCount` or unsupported `SUBQUERY`
/// predicates when sharing multiple videos from Photos.
@MainActor
final class PhotosShareSheetUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testMontageAppearsInPhotosShareSheetAndLoadsSelectedVideos() async throws {
    // 1. Launch Montage first so iOS installs and registers the host app and ShareExtension.
    let hostApp = XCUIApplication()
    hostApp.launch()
    XCTAssertTrue(
      hostApp.navigationBars["Montage"].waitForExistence(timeout: 5),
      "Montage host app should launch before opening Photos."
    )

    // 2. Ensure the simulator's Photos library contains at least 2 videos.
    try await ensureAtLeastTwoVideosInPhotosLibrary()

    // 3. Open the system Photos app.
    let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
    photos.terminate()
    photos.launch()

    dismissPhotosOnboardingIfNeeded(in: photos)

    // Ensure we can see the Select button in the Library view.
    let selectButton = photos.buttons["Select"].firstMatch
    if !selectButton.waitForExistence(timeout: 5) {
      let libraryTab = photos.buttons["Library"].firstMatch
      if libraryTab.exists {
        libraryTab.tap()
      }
    }

    XCTAssertTrue(
      selectButton.waitForExistence(timeout: 8),
      "Photos 'Select' button should be visible."
    )
    selectButton.tap()

    // 4. Select 2 videos from the Photos grid.
    let videoCells = photos.images.matching(NSPredicate(format: "label BEGINSWITH 'Video,'"))
    let altVideoCells = photos.cells.matching(NSPredicate(format: "label BEGINSWITH 'Video,'"))

    var selectedCount = 0
    let targetQuery: XCUIElementQuery
    if videoCells.firstMatch.waitForExistence(timeout: 4), videoCells.count >= 2 {
      targetQuery = videoCells
    } else {
      XCTAssertTrue(
        altVideoCells.firstMatch.waitForExistence(timeout: 5),
        "Expected at least 2 videos in Photos library."
      )
      targetQuery = altVideoCells
    }

    let totalVideos = targetQuery.count
    XCTAssertGreaterThanOrEqual(
      totalVideos, 2, "Need at least 2 videos in Photos to test Share Sheet.")

    // Pick the last 2 videos (typically at the bottom of the grid, immediately visible).
    for index in [totalVideos - 2, totalVideos - 1] {
      let cell = targetQuery.element(boundBy: index)
      if cell.exists {
        cell.tap()
        selectedCount += 1
      }
    }

    XCTAssertEqual(selectedCount, 2, "Should select 2 videos in Photos.")

    // 5. Open the Share Sheet.
    let shareButton = photos.buttons["Share"].firstMatch
    XCTAssertTrue(shareButton.waitForExistence(timeout: 5), "Photos Share button should exist.")
    shareButton.tap()

    // 6. Verify 'Montage' appears in the Share Sheet (either directly or under 'More').
    let montageInShareSheet = findMontageInShareSheet(in: photos)
    XCTAssertNotNil(
      montageInShareSheet,
      "Montage must appear in the iOS Photos Share Sheet when 2 videos are selected."
    )

    // 7. Tap 'Montage' and verify the Share Extension UI loads both clips.
    montageInShareSheet?.tap()

    let mergeTitle = photos.navigationBars["Montage"].firstMatch
    XCTAssertTrue(
      mergeTitle.waitForExistence(timeout: 12),
      "Montage Share Extension should present the 'Montage' view."
    )

    let dragHeader = photos.staticTexts["Drag to Reorder"].firstMatch
    XCTAssertTrue(
      dragHeader.waitForExistence(timeout: 12),
      "Share Extension should finish loading both videos and show the 'Drag to Reorder' list."
    )

    let twoClipsSummary = photos.staticTexts.matching(
      NSPredicate(format: "label CONTAINS '2 clips'")
    ).firstMatch
    XCTAssertTrue(
      twoClipsSummary.waitForExistence(timeout: 5),
      "Header summary pill should report '2 clips'."
    )

    let mergeButton = photos.buttons["Merge and Save"].firstMatch
    XCTAssertTrue(
      mergeButton.waitForExistence(timeout: 5), "'Merge and Save' button should appear.")
    XCTAssertTrue(mergeButton.isEnabled, "'Merge and Save' should be enabled for 2 loaded clips.")

    // 8. Cancel and verify the Share Extension dismisses cleanly.
    let cancelButton = mergeTitle.buttons["Cancel"].firstMatch
    XCTAssertTrue(
      cancelButton.waitForExistence(timeout: 3),
      "'Montage' navigation bar should contain a 'Cancel' button."
    )
    cancelButton.tap()

    XCTAssertTrue(
      mergeTitle.waitForNonExistence(timeout: 8),
      "Tapping Cancel should dismiss the Montage Share Extension."
    )
  }

  // MARK: - Share Sheet Lookup Helpers

  private func dismissPhotosOnboardingIfNeeded(in photos: XCUIApplication) {
    let continueButton = photos.buttons["Continue"].firstMatch
    if continueButton.waitForExistence(timeout: 2) {
      continueButton.tap()
    }

    let notNowButton = photos.buttons["Not Now"].firstMatch
    if notNowButton.waitForExistence(timeout: 1) {
      notNowButton.tap()
    }
  }

  /// Searches the iOS Share Sheet apps row (and the 'More' apps list if needed) for 'Montage'.
  private func findMontageInShareSheet(in photos: XCUIApplication) -> XCUIElement? {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let candidates: [XCUIElement] = [
      photos.cells["Montage"].firstMatch,
      photos.buttons["Montage"].firstMatch,
      photos.staticTexts["Montage"].firstMatch,
      springboard.cells["Montage"].firstMatch,
      springboard.buttons["Montage"].firstMatch,
    ]

    // Wait briefly for the Share Sheet apps row to populate.
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline {
      for element in candidates where element.exists {
        return element
      }

      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    // If Montage is further right in the apps row, open 'More' to inspect all Share Extensions.
    let moreCandidates: [XCUIElement] = [
      photos.cells["More"].firstMatch,
      photos.buttons["More"].firstMatch,
      springboard.cells["More"].firstMatch,
      springboard.buttons["More"].firstMatch,
    ]
    if let moreButton = moreCandidates.first(where: { $0.exists }) {
      moreButton.tap()
      let moreDeadline = Date().addingTimeInterval(5)
      while Date() < moreDeadline {
        for element in candidates where element.exists {
          return element
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }

    return nil
  }

  // MARK: - Self-Contained Sample Video Seeding

  /// Ensures the Simulator's Photos library has at least 2 videos so this UI test passes
  /// even on a freshly reset Simulator without manual setup.
  private func ensureAtLeastTwoVideosInPhotosLibrary() async throws {
    let status = await requestPhotoAuthorizationHandlingSystemAlert()
    guard status == .authorized || status == .limited else {
      return
    }

    let existingVideos = PHAsset.fetchAssets(with: .video, options: nil)
    if existingVideos.count >= 2 {
      return
    }

    let needed = 2 - existingVideos.count
    let tempDir = try TestVideoFixtureFactory.makeTempDirectory(named: "MontageUITestFixtures")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    for index in 0..<needed {
      let color: TestVideoFixtureFactory.RGBAColor
      if index % 2 == 0 {
        color = .red
      } else {
        color = .blue
      }

      let videoURL = try await TestVideoFixtureFactory.makeVideo(
        in: tempDir,
        filename: "ui_test_video_\(index)_\(UUID().uuidString).mov",
        color: color
      )
      try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
      }
    }
  }

  private func requestPhotoAuthorizationHandlingSystemAlert() async -> PHAuthorizationStatus {
    let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if current != .notDetermined {
      return current
    }

    let authTask = Task.detached {
      await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline {
      if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined {
        break
      }

      let allowFull = springboard.buttons["Allow Full Access"].firstMatch
      if allowFull.exists {
        allowFull.tap()
        break
      }

      let allowAll = springboard.buttons["Allow Access to All Photos"].firstMatch
      if allowAll.exists {
        allowAll.tap()
        break
      }

      if #available(iOS 16, *) {
        try? await Task.sleep(for: .milliseconds(200))
      } else {
        try? await Task.sleep(nanoseconds: 200_000_000)
      }
    }

    return await authTask.value
  }
}
