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
      app.navigationBars["Merge Videos"].waitForExistence(timeout: 5),
      "Host app should display the 'Merge Videos' navigation bar."
    )

    // Quick guide steps
    XCTAssertTrue(app.staticTexts["How It Works"].exists)
    XCTAssertTrue(app.staticTexts["Select 2 or more clips in Photos"].exists)
    XCTAssertTrue(app.staticTexts["Tap Share and pick Merge Videos"].exists)
    XCTAssertTrue(app.staticTexts["Reorder and Merge into one video"].exists)

    // Transitions section
    XCTAssertTrue(app.staticTexts["Transitions"].exists)

    // Scroll down to verify Photo Library Hygiene and Uniform Video Length sections
    let keepDateAndLocation = app.switches["Keep Original Date and Location"]
    if !keepDateAndLocation.exists || !keepDateAndLocation.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(
      keepDateAndLocation.waitForExistence(timeout: 3),
      "'Keep Original Date and Location' toggle should be visible."
    )

    let sourceCleanupToggle = app.switches["Post-Merge Source Cleanup"]
    if !sourceCleanupToggle.exists || !sourceCleanupToggle.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(
      sourceCleanupToggle.waitForExistence(timeout: 3),
      "'Post-Merge Source Cleanup' toggle should be visible."
    )

    let autoTrimToggle = app.switches["Auto-Trim to Fixed Intervals"]
    if !autoTrimToggle.exists || !autoTrimToggle.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(
      autoTrimToggle.waitForExistence(timeout: 3),
      "'Auto-Trim to Fixed Intervals' toggle should be visible."
    )

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
    XCTAssertTrue(app.navigationBars["Merge Videos"].waitForExistence(timeout: 5))

    // Open Transition Style picker and select Cross Dissolve
    let transitionPicker = app.buttons.matching(
      NSPredicate(format: "label CONTAINS 'Transition Style'")
    ).firstMatch
    if !transitionPicker.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(transitionPicker.waitForExistence(timeout: 3))
    transitionPicker.tap()

    let crossDissolveOption = app.buttons["Cross Dissolve"]
    XCTAssertTrue(crossDissolveOption.waitForExistence(timeout: 3))
    crossDissolveOption.tap()

    // Selecting an animated transition should reveal the duration segmented control
    let longDurationButton = app.buttons["0.7s"]
    XCTAssertTrue(
      longDurationButton.waitForExistence(timeout: 3),
      "Transition Duration segmented picker should appear when an animated transition is selected."
    )
    longDurationButton.tap()

    // Scroll to Auto-Trim toggle and turn it ON
    let autoTrimSwitch = app.switches["Auto-Trim to Fixed Intervals"]
    if !autoTrimSwitch.exists || !autoTrimSwitch.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(autoTrimSwitch.waitForExistence(timeout: 3))
    if (autoTrimSwitch.value as? String) == "0" {
      autoTrimSwitch.switches.firstMatch.exists
        ? autoTrimSwitch.switches.firstMatch.tap()
        : autoTrimSwitch.tap()
    }

    let trimIntervalPicker = app.buttons.matching(
      NSPredicate(format: "label CONTAINS 'Trim Interval'")
    ).firstMatch
    if !trimIntervalPicker.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(
      trimIntervalPicker.waitForExistence(timeout: 3),
      "Trim Interval picker should appear when Auto-Trim is enabled."
    )

    // Relaunch app and verify settings persisted via shared App Group UserDefaults
    app.terminate()
    app.launch()
    XCTAssertTrue(app.navigationBars["Merge Videos"].waitForExistence(timeout: 5))

    let persistedTransitionPicker = app.buttons.matching(
      NSPredicate(format: "label CONTAINS 'Transition Style'")
    ).firstMatch
    if !persistedTransitionPicker.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(persistedTransitionPicker.waitForExistence(timeout: 3))
    XCTAssertTrue(
      persistedTransitionPicker.label.contains("Cross Dissolve"),
      "Transition Style should persist as Cross Dissolve after relaunch, got: \(persistedTransitionPicker.label)"
    )
    XCTAssertTrue(app.buttons["0.7s"].waitForExistence(timeout: 3))

    // Restore clean defaults (Instant Cut + Auto-Trim OFF)
    persistedTransitionPicker.tap()
    let instantCutOption = app.buttons["None (Instant Cut)"]
    XCTAssertTrue(instantCutOption.waitForExistence(timeout: 3))
    instantCutOption.tap()

    let resetAutoTrimSwitch = app.switches["Auto-Trim to Fixed Intervals"]
    if !resetAutoTrimSwitch.isHittable {
      app.swipeUp()
    }
    if resetAutoTrimSwitch.waitForExistence(timeout: 3),
      (resetAutoTrimSwitch.value as? String) == "1"
    {
      resetAutoTrimSwitch.tap()
    }
  }
}
