import Foundation
import Testing
@testable import Clip_Combine

@Suite("AppSettings and Shared Preferences")
@MainActor
struct AppSettingsTests {
  private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "com.sareshwala.faraaz.clipcombine.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
  }

  @Test("Fresh store uses expected defaults")
  func defaultsOnFreshStore() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)

    #expect(settings.transitionStyle == .none)
    #expect(settings.transitionDuration == .medium)
    #expect(settings.preserveMetadata == true)
    #expect(settings.deleteSourceClipsAfterMerge == false)
    #expect(settings.autoTrimEnabled == false)
    #expect(settings.autoTrimInterval == .thirtySeconds)
  }

  @Test("Changes persist across separate AppSettings instances sharing UserDefaults")
  func persistenceAcrossInstances() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let hostSettings = AppSettings(defaults: defaults)
    hostSettings.transitionStyle = .crossDissolve
    hostSettings.transitionDuration = .long
    hostSettings.preserveMetadata = false
    hostSettings.deleteSourceClipsAfterMerge = true
    hostSettings.autoTrimEnabled = true
    hostSettings.autoTrimInterval = .oneMinute

    // Simulate the Share Extension loading preferences from the same shared suite.
    let extensionSettings = AppSettings(defaults: defaults)

    #expect(extensionSettings.transitionStyle == .crossDissolve)
    #expect(extensionSettings.transitionDuration == .long)
    #expect(extensionSettings.preserveMetadata == false)
    #expect(extensionSettings.deleteSourceClipsAfterMerge == true)
    #expect(extensionSettings.autoTrimEnabled == true)
    #expect(extensionSettings.autoTrimInterval == .oneMinute)
  }

  @Test("reload() picks up external UserDefaults updates")
  func reloadPicksUpExternalChanges() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.transitionStyle == .none)

    defaults.set(TransitionStyle.slide.rawValue, forKey: "transitionStyle")
    defaults.set(TransitionDuration.short.rawValue, forKey: "transitionDuration")
    defaults.set(false, forKey: "preserveMetadata")
    defaults.set(true, forKey: "deleteSourceClipsAfterMerge")
    defaults.set(true, forKey: "autoTrimEnabled")
    defaults.set(TrimInterval.oneMinute.rawValue, forKey: "autoTrimInterval")

    settings.reload()

    #expect(settings.transitionStyle == .slide)
    #expect(settings.transitionDuration == .short)
    #expect(settings.preserveMetadata == false)
    #expect(settings.deleteSourceClipsAfterMerge == true)
    #expect(settings.autoTrimEnabled == true)
    #expect(settings.autoTrimInterval == .oneMinute)
  }

  @Test("reload() safely falls back to defaults for invalid or missing raw values")
  func reloadFallsBackOnInvalidValues() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.transitionStyle = .dipToBlack
    settings.transitionDuration = .long
    settings.preserveMetadata = false
    settings.autoTrimInterval = .oneMinute

    defaults.set("unknown_style", forKey: "transitionStyle")
    defaults.set(-5.0, forKey: "transitionDuration")
    defaults.removeObject(forKey: "preserveMetadata")
    defaults.set(999, forKey: "autoTrimInterval")

    settings.reload()

    #expect(settings.transitionStyle == .none)
    #expect(settings.transitionDuration == .medium)
    #expect(settings.preserveMetadata == true)
    #expect(settings.autoTrimInterval == .thirtySeconds)
  }

  @Test("makeConfiguration() returns an immutable snapshot matching current settings")
  func makeConfigurationSnapshot() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.transitionStyle = .dipToBlack
    settings.transitionDuration = .short
    settings.preserveMetadata = true
    settings.deleteSourceClipsAfterMerge = true
    settings.autoTrimEnabled = true
    settings.autoTrimInterval = .oneMinute

    let snapshot = settings.makeConfiguration()

    // Mutating settings afterwards must not affect the captured snapshot.
    settings.transitionStyle = .none
    settings.autoTrimEnabled = false

    #expect(snapshot.transitionStyle == .dipToBlack)
    #expect(snapshot.transitionDuration == 0.3)
    #expect(snapshot.preserveMetadata == true)
    #expect(snapshot.deleteSourceClipsAfterMerge == true)
    #expect(snapshot.autoTrimEnabled == true)
    #expect(snapshot.autoTrimInterval == .oneMinute)
  }

  @Test("App Group identifier and shared container URL are valid")
  func appGroupConfiguration() {
    #expect(AppSettings.appGroupIdentifier == "group.com.sareshwala.faraaz.clipcombine")
    #expect(AppSettings.sharedContainerURL.isFileURL)
  }

  @Test("Setting option enums expose complete, clean display names and values")
  func optionEnumsMetadata() {
    #expect(TransitionStyle.allCases == [.none, .crossDissolve, .dipToBlack, .slide])
    for style in TransitionStyle.allCases {
      #expect(style.id == style.rawValue)
      #expect(!style.displayName.isEmpty)
      #expect(!style.displayName.contains("&"))
      #expect(!style.displayName.localizedCaseInsensitiveContains("outing"))
    }

    #expect(TransitionDuration.allCases == [.short, .medium, .long])
    #expect(TransitionDuration.short.rawValue == 0.3)
    #expect(TransitionDuration.medium.rawValue == 0.5)
    #expect(TransitionDuration.long.rawValue == 0.8)
    for duration in TransitionDuration.allCases {
      #expect(duration.id == duration.rawValue)
      #expect(!duration.displayName.isEmpty)
    }

    #expect(TrimInterval.allCases == [.thirtySeconds, .oneMinute])
    #expect(TrimInterval.thirtySeconds.seconds == 30)
    #expect(TrimInterval.oneMinute.seconds == 60)
    for interval in TrimInterval.allCases {
      #expect(interval.id == interval.rawValue)
      #expect(!interval.displayName.isEmpty)
      #expect(!interval.displayName.contains("&"))
    }
  }
}
