import Combine
import Foundation

/// Common interface for enumerable host-app picker options.
public nonisolated protocol SettingOption: CaseIterable, Identifiable, Hashable, Sendable {
  var displayName: String { get }
}

/// Transition styles available between merged video clips.
public nonisolated enum TransitionStyle: String, SettingOption {
  case none
  case crossDissolve
  case dipToBlack
  case slide

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .none:
      "None"
    case .crossDissolve:
      "Cross Dissolve"
    case .dipToBlack:
      "Dip to Black"
    case .slide:
      "Slide"
    }
  }
}

/// Supported transition durations in seconds.
public nonisolated enum TransitionDuration: Double, SettingOption {
  case short = 0.25
  case medium = 0.5
  case long = 0.75

  public var id: Double { rawValue }

  public var displayName: String {
    switch self {
    case .short:
      "0.25 seconds"
    case .medium:
      "0.5 seconds"
    case .long:
      "0.75 seconds"
    }
  }
}

/// Fixed duration intervals for optional uniform video length trimming.
public nonisolated enum TrimInterval: Int, SettingOption {
  case fifteenSeconds = 15
  case thirtySeconds = 30
  case oneMinute = 60

  public var id: Int { rawValue }

  public var seconds: TimeInterval {
    TimeInterval(rawValue)
  }

  public var displayName: String {
    switch self {
    case .fifteenSeconds:
      "15 seconds"
    case .thirtySeconds:
      "30 seconds"
    case .oneMinute:
      "1 minute"
    }
  }

  public var markLabel: String {
    switch self {
    case .fifteenSeconds:
      "15-second"
    case .thirtySeconds:
      "30-second"
    case .oneMinute:
      "1-minute"
    }
  }

  public var exampleMarks: String {
    switch self {
    case .fifteenSeconds:
      "0:15, 0:30, 0:45, 1:00, etc."
    case .thirtySeconds:
      "0:30, 1:00, 1:30, 2:00, etc."
    case .oneMinute:
      "1:00, 2:00, 3:00, etc."
    }
  }
}

/// Immutable, Sendable snapshot of merge preferences for off-main-actor video processing.
public nonisolated struct MergeConfiguration: Sendable, Equatable {
  public let transitionStyle: TransitionStyle
  public let transitionDuration: TimeInterval
  public let preserveMetadata: Bool
  public let deleteSourceClipsAfterMerge: Bool
  public let autoTrimEnabled: Bool
  public let autoTrimInterval: TrimInterval

  public init(
    transitionStyle: TransitionStyle = .none,
    transitionDuration: TimeInterval = TransitionDuration.medium.rawValue,
    preserveMetadata: Bool = true,
    deleteSourceClipsAfterMerge: Bool = false,
    autoTrimEnabled: Bool = false,
    autoTrimInterval: TrimInterval = .thirtySeconds
  ) {
    self.transitionStyle = transitionStyle
    self.transitionDuration = transitionDuration
    self.preserveMetadata = preserveMetadata
    self.deleteSourceClipsAfterMerge = deleteSourceClipsAfterMerge
    self.autoTrimEnabled = autoTrimEnabled
    self.autoTrimInterval = autoTrimInterval
  }

  /// Computes the effective overlap duration for a boundary between two adjacent clips,
  /// guarding against transitions longer than half of either clip's duration.
  public func effectiveTransitionDuration(
    between firstDuration: TimeInterval,
    and secondDuration: TimeInterval
  ) -> TimeInterval {
    guard transitionStyle != .none, transitionDuration > 0 else { return 0 }
    let maxAllowed = min(firstDuration, secondDuration) * 0.45
    return max(0, min(transitionDuration, maxAllowed))
  }

  /// Returns the floored auto-trim target duration when auto-trim is enabled and
  /// `duration` reaches at least one completed interval, or `nil` otherwise.
  public func trimmedDuration(for duration: TimeInterval) -> TimeInterval? {
    guard autoTrimEnabled else { return nil }
    let interval = autoTrimInterval.seconds
    guard interval > 0, duration >= interval else { return nil }
    return floor(duration / interval) * interval
  }

  /// Estimates the final output video duration given an ordered list of clip durations.
  public func estimatedOutputDuration(for clipDurations: [TimeInterval]) -> TimeInterval {
    guard !clipDurations.isEmpty else { return 0 }

    var total = clipDurations.reduce(0, +)

    if transitionStyle != .none, clipDurations.count > 1 {
      for index in 0..<(clipDurations.count - 1) {
        total -= effectiveTransitionDuration(
          between: clipDurations[index],
          and: clipDurations[index + 1]
        )
      }
    }

    total = max(0, total)

    if let trimmed = trimmedDuration(for: total) {
      total = trimmed
    }

    return total
  }
}

/// Shared observable preferences synchronized between the host app and Share Extension
/// via the shared App Group UserDefaults suite.
@MainActor
public final class AppSettings: ObservableObject {
  /// App Group identifier matching both targets' entitlements.
  public nonisolated static let appGroupIdentifier = "group.com.sareshwala.faraaz.montage"

  /// Shared container directory for temporary exports, falling back to temporaryDirectory.
  public nonisolated static var sharedContainerURL: URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
      ?? FileManager.default.temporaryDirectory
  }

  private enum Keys {
    static let transitionStyle = "transitionStyle"
    static let transitionDuration = "transitionDuration"
    static let preserveMetadata = "preserveMetadata"
    static let deleteSourceClipsAfterMerge = "deleteSourceClipsAfterMerge"
    static let autoTrimEnabled = "autoTrimEnabled"
    static let autoTrimInterval = "autoTrimInterval"
  }

  private let defaults: UserDefaults

  @Published public var transitionStyle: TransitionStyle {
    didSet {
      defaults.set(transitionStyle.rawValue, forKey: Keys.transitionStyle)
    }
  }

  @Published public var transitionDuration: TransitionDuration {
    didSet {
      defaults.set(transitionDuration.rawValue, forKey: Keys.transitionDuration)
    }
  }

  @Published public var preserveMetadata: Bool {
    didSet {
      defaults.set(preserveMetadata, forKey: Keys.preserveMetadata)
    }
  }

  @Published public var deleteSourceClipsAfterMerge: Bool {
    didSet {
      defaults.set(deleteSourceClipsAfterMerge, forKey: Keys.deleteSourceClipsAfterMerge)
    }
  }

  @Published public var autoTrimEnabled: Bool {
    didSet {
      defaults.set(autoTrimEnabled, forKey: Keys.autoTrimEnabled)
    }
  }

  @Published public var autoTrimInterval: TrimInterval {
    didSet {
      defaults.set(autoTrimInterval.rawValue, forKey: Keys.autoTrimInterval)
    }
  }

  private struct StoredValues {
    let transitionStyle: TransitionStyle
    let transitionDuration: TransitionDuration
    let preserveMetadata: Bool
    let deleteSourceClipsAfterMerge: Bool
    let autoTrimEnabled: Bool
    let autoTrimInterval: TrimInterval
  }

  private static func loadStoredValues(from defaults: UserDefaults) -> StoredValues {
    let transitionStyle =
      defaults.string(forKey: Keys.transitionStyle).flatMap(TransitionStyle.init(rawValue:))
      ?? .none

    let storedDuration = defaults.double(forKey: Keys.transitionDuration)
    let transitionDuration =
      (storedDuration > 0 ? TransitionDuration(rawValue: storedDuration) : nil) ?? .medium

    let preserveMetadata =
      defaults.object(forKey: Keys.preserveMetadata) != nil
      ? defaults.bool(forKey: Keys.preserveMetadata)
      : true

    let deleteSourceClipsAfterMerge = defaults.bool(forKey: Keys.deleteSourceClipsAfterMerge)
    let autoTrimEnabled = defaults.bool(forKey: Keys.autoTrimEnabled)
    let autoTrimInterval =
      TrimInterval(rawValue: defaults.integer(forKey: Keys.autoTrimInterval)) ?? .thirtySeconds

    return StoredValues(
      transitionStyle: transitionStyle,
      transitionDuration: transitionDuration,
      preserveMetadata: preserveMetadata,
      deleteSourceClipsAfterMerge: deleteSourceClipsAfterMerge,
      autoTrimEnabled: autoTrimEnabled,
      autoTrimInterval: autoTrimInterval
    )
  }

  public init(defaults: UserDefaults? = nil) {
    let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    let suite: UserDefaults
    if let defaults {
      suite = defaults
    } else if isPreview {
      suite = .standard
    } else {
      suite = UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
    }
    self.defaults = suite

    let stored = Self.loadStoredValues(from: suite)
    self.transitionStyle = stored.transitionStyle
    self.transitionDuration = stored.transitionDuration
    self.preserveMetadata = stored.preserveMetadata
    self.deleteSourceClipsAfterMerge = stored.deleteSourceClipsAfterMerge
    self.autoTrimEnabled = stored.autoTrimEnabled
    self.autoTrimInterval = stored.autoTrimInterval
  }

  /// Re-reads all values from the shared App Group UserDefaults store.
  public func reload() {
    let stored = Self.loadStoredValues(from: defaults)
    if transitionStyle != stored.transitionStyle {
      transitionStyle = stored.transitionStyle
    }
    if transitionDuration != stored.transitionDuration {
      transitionDuration = stored.transitionDuration
    }
    if preserveMetadata != stored.preserveMetadata {
      preserveMetadata = stored.preserveMetadata
    }
    if deleteSourceClipsAfterMerge != stored.deleteSourceClipsAfterMerge {
      deleteSourceClipsAfterMerge = stored.deleteSourceClipsAfterMerge
    }
    if autoTrimEnabled != stored.autoTrimEnabled {
      autoTrimEnabled = stored.autoTrimEnabled
    }
    if autoTrimInterval != stored.autoTrimInterval {
      autoTrimInterval = stored.autoTrimInterval
    }
  }

  /// Captures an immutable, Sendable configuration snapshot for the video merge engine.
  public func makeConfiguration() -> MergeConfiguration {
    MergeConfiguration(
      transitionStyle: transitionStyle,
      transitionDuration: transitionDuration.rawValue,
      preserveMetadata: preserveMetadata,
      deleteSourceClipsAfterMerge: deleteSourceClipsAfterMerge,
      autoTrimEnabled: autoTrimEnabled,
      autoTrimInterval: autoTrimInterval
    )
  }
}
