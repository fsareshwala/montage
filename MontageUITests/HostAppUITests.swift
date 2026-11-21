import Foundation
import XCTest

@MainActor
final class HostAppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testHostAppDisplaysAllSectionsQuickGuideAndCleanCopy() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(
      app.navigationBars["Montage"].waitForExistence(timeout: 5),
      "Host app should display the 'Montage' navigation bar."
    )

    // Status and Quick guide sections
    XCTAssertTrue(app.staticTexts["Status"].exists)
    XCTAssertTrue(app.staticTexts["How It Works"].exists)
    XCTAssertTrue(app.staticTexts["Select 2 or more clips in Photos"].exists)
    XCTAssertTrue(app.staticTexts["Tap Share and pick Montage"].exists)
    XCTAssertTrue(app.staticTexts["Reorder and Merge into one video"].exists)

    // Transitions section
    XCTAssertTrue(app.staticTexts["Transitions"].exists)

    // Scroll down to verify Photo Library Hygiene and Uniform Video Length sections
    for toggleTitle in [
      "Preserve Metadata",
      "Post-Merge Source Cleanup",
      "Auto-Trim to Fixed Intervals",
    ] {
      let toggle = app.switches[toggleTitle]
      scrollIntoView(toggle, in: app)
      XCTAssertTrue(
        toggle.waitForExistence(timeout: 3),
        "'\(toggleTitle)' toggle should be visible."
      )
    }

    // Scroll down to verify About and Other Apps sections
    let privacyRow = app.buttons["Privacy Policy"].firstMatch
    scrollIntoView(privacyRow, in: app)
    XCTAssertTrue(
      privacyRow.waitForExistence(timeout: 3),
      "'Privacy Policy' row should be visible in About section."
    )

    // Verify Privacy Policy navigation pushes PrivacyPolicyView cleanly
    privacyRow.tap()
    XCTAssertTrue(
      app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5),
      "Tapping Privacy Policy should navigate to the Privacy Policy screen."
    )
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Montage"].waitForExistence(timeout: 5))

    for expectedText in [
      "Share Montage",
      "Report a Bug",
      "Source Code",
      "This app is fully open source. You can read the code on GitHub.",
      "Other Apps from the Developer",
      "Forecash",
      "Clean Dial",
    ] {
      let text = app.staticTexts[expectedText]
      scrollIntoView(text, in: app)
      XCTAssertTrue(
        text.waitForExistence(timeout: 3),
        "'\(expectedText)' should be visible in About or Other Apps section."
      )
    }

    // Guard copy constraints across all rendered static texts: no "outing" and no "&".
    for textElement in app.staticTexts.allElementsBoundByIndex {
      let label = textElement.label
      XCTAssertFalse(
        label.localizedCaseInsensitiveContains("outing"),
        "Unexpected 'outing' wording found in UI: \(label)"
      )
      XCTAssertFalse(
        label.contains("&"),
        "Unexpected '&' character found in UI: \(label)"
      )
    }
  }

  func testTransitionAndAutoTrimControlsToggleAndPersistAcrossRelaunch() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.navigationBars["Montage"].waitForExistence(timeout: 5))

    // Open Transition Style picker and select Cross Dissolve
    selectPickerOption("Cross Dissolve", from: "Transition Style", in: app)

    // Selecting an animated transition should reveal the duration picker
    selectPickerOption("0.75 seconds", from: "Transition Duration", in: app)

    // Scroll to Auto-Trim toggle and turn it ON
    let autoTrimSwitch = app.switches["Auto-Trim to Fixed Intervals"]
    scrollIntoView(autoTrimSwitch, in: app)
    XCTAssertTrue(autoTrimSwitch.waitForExistence(timeout: 3))
    if (autoTrimSwitch.value as? String) == "0" {
      autoTrimSwitch.switches.firstMatch.exists
        ? autoTrimSwitch.switches.firstMatch.tap()
        : autoTrimSwitch.tap()
    }

    let trimIntervalPicker = pickerButton(titled: "Trim Interval", in: app)
    scrollIntoView(trimIntervalPicker, in: app)
    XCTAssertTrue(
      trimIntervalPicker.waitForExistence(timeout: 3),
      "Trim Interval picker should appear when Auto-Trim is enabled."
    )

    // Relaunch app and verify settings persisted via shared App Group UserDefaults
    app.terminate()
    app.launch()
    XCTAssertTrue(app.navigationBars["Montage"].waitForExistence(timeout: 5))

    let persistedTransitionPicker = pickerButton(titled: "Transition Style", in: app)
    scrollIntoView(persistedTransitionPicker, in: app)
    XCTAssertTrue(persistedTransitionPicker.waitForExistence(timeout: 3))
    XCTAssertTrue(
      persistedTransitionPicker.label.contains("Cross Dissolve"),
      "Transition Style should persist as Cross Dissolve after relaunch, got: \(persistedTransitionPicker.label)"
    )

    let persistedDurationPicker = pickerButton(titled: "Transition Duration", in: app)
    XCTAssertTrue(persistedDurationPicker.waitForExistence(timeout: 3))
    XCTAssertTrue(
      persistedDurationPicker.label.contains("0.75 seconds"),
      "Transition Duration should persist as 0.75 seconds after relaunch, got: \(persistedDurationPicker.label)"
    )

    // Restore clean defaults (None + Auto-Trim OFF)
    selectPickerOption("None", from: "Transition Style", in: app)

    let resetAutoTrimSwitch = app.switches["Auto-Trim to Fixed Intervals"]
    scrollIntoView(resetAutoTrimSwitch, in: app)
    if resetAutoTrimSwitch.waitForExistence(timeout: 3),
      (resetAutoTrimSwitch.value as? String) == "1"
    {
      resetAutoTrimSwitch.tap()
    }
  }

  // MARK: - Helpers

  private func pickerButton(titled title: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
  }

  private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<4 where !element.exists || !element.isHittable {
      app.swipeUp()
    }
  }

  private func selectPickerOption(
    _ option: String,
    from pickerTitle: String,
    in app: XCUIApplication
  ) {
    let picker = pickerButton(titled: pickerTitle, in: app)
    scrollIntoView(picker, in: app)
    XCTAssertTrue(picker.waitForExistence(timeout: 3), "\(pickerTitle) picker should exist.")
    picker.tap()

    let optionButton = app.buttons[option]
    XCTAssertTrue(
      optionButton.waitForExistence(timeout: 3),
      "Option '\(option)' should appear in \(pickerTitle) picker."
    )
    optionButton.tap()
  }
}
