import Foundation
import XCTest

@MainActor
final class HostAppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testHostAppLaunchesAndNavigatesToPrivacyPolicy() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(
      app.navigationBars["Montage"].waitForExistence(timeout: 5),
      "Host app should display the 'Montage' navigation bar."
    )

    let privacyRow = app.buttons["Privacy Policy"].firstMatch
    scrollIntoView(privacyRow, in: app)
    XCTAssertTrue(
      privacyRow.waitForExistence(timeout: 3),
      "'Privacy Policy' row should be visible in About section."
    )

    privacyRow.tap()
    XCTAssertTrue(
      app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5),
      "Tapping Privacy Policy should navigate to the Privacy Policy screen."
    )

    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(
      app.navigationBars["Montage"].waitForExistence(timeout: 5),
      "Tapping back should return to the 'Montage' navigation bar."
    )
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
    let autoTrimSwitch = toggleSwitch(titled: "Auto-Trim to Fixed Intervals", in: app)
    scrollIntoView(autoTrimSwitch, in: app)
    XCTAssertTrue(autoTrimSwitch.waitForExistence(timeout: 3))
    if (autoTrimSwitch.value as? String) == "0" {
      if autoTrimSwitch.switches.firstMatch.exists {
        autoTrimSwitch.switches.firstMatch.tap()
      } else {
        autoTrimSwitch.tap()
      }
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

    let resetAutoTrimSwitch = toggleSwitch(titled: "Auto-Trim to Fixed Intervals", in: app)
    scrollIntoView(resetAutoTrimSwitch, in: app)
    if resetAutoTrimSwitch.waitForExistence(timeout: 3),
      (resetAutoTrimSwitch.value as? String) == "1"
    {
      if resetAutoTrimSwitch.switches.firstMatch.exists {
        resetAutoTrimSwitch.switches.firstMatch.tap()
      } else {
        resetAutoTrimSwitch.tap()
      }
    }
  }

  // MARK: - Helpers

  private func pickerButton(titled title: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
  }

  private func toggleSwitch(titled title: String, in app: XCUIApplication) -> XCUIElement {
    app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
  }

  private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
    let startDown = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
    let endDown = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    for _ in 0..<8 where !element.exists || !element.isHittable {
      startDown.press(forDuration: 0.05, thenDragTo: endDown)
    }

    if !element.exists || !element.isHittable {
      let startUp = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
      let endUp = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
      for _ in 0..<8 where !element.exists || !element.isHittable {
        startUp.press(forDuration: 0.05, thenDragTo: endUp)
      }
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
