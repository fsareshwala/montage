import Foundation
import Observation

/// Transition styles available between merged video clips.
public nonisolated enum TransitionStyle: String, CaseIterable, Identifiable, Sendable {
  case none
  case crossDissolve
  case dipToBlack
  case slide

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .none:
      "None (Instant Cut)"
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
public nonisolated enum TransitionDuration: Double, CaseIterable, Identifiable, Sendable {
  case short = 0.3
  case medium = 0.5
  case long = 0.7

  public var id: Double { rawValue }

  public var displayName: String {
    switch self {
    case .short:
      "0.3s"
    case .medium:
      "0.5s"
    case .long:
      "0.7s"
    }
  }
}

/// Fixed duration intervals for optional uniform video length trimming.
public nonisolated enum TrimInterval: Int, CaseIterable, Identifiable, Sendable {
  case thirtySeconds = 30
  case oneMinute = 60

  public var id: Int { rawValue }

  public var seconds: TimeInterval {
    TimeInterval(rawValue)
  }

  public var displayName: String {
    switch self {
    case .thirtySeconds:
      "30 seconds (0:30, 1:00, 1:30...)"
    case .oneMinute:
      "1 minute (1:00, 2:00, 3:00...)"
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
    transitionStyle: TransitionStyle,
    transitionDuration: TimeInterval,
    preserveMetadata: Bool,
    deleteSourceClipsAfterMerge: Bool,
    autoTrimEnabled: Bool,
    autoTrimInterval: TrimInterval
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

    if autoTrimEnabled {
      let interval = autoTrimInterval.seconds
      if total >= interval {
        total = floor(total / interval) * interval
      }
    }

    return total
  }
}

/// Shared observable preferences synchronized between the host app and Share Extension
/// via the shared App Group UserDefaults suite.
@MainActor
@Observable
public final class AppSettings {
  /// App Group identifier matching both targets' entitlements.
  public nonisolated static let appGroupIdentifier = "group.com.sareshwala.faraaz.mergevideos"

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

  public var transitionStyle: TransitionStyle {
    didSet {
      defaults.set(transitionStyle.rawValue, forKey: Keys.transitionStyle)
    }
  }

  public var transitionDuration: TransitionDuration {
    didSet {
      defaults.set(transitionDuration.rawValue, forKey: Keys.transitionDuration)
    }
  }

  public var preserveMetadata: Bool {
    didSet {
      defaults.set(preserveMetadata, forKey: Keys.preserveMetadata)
    }
  }

  public var deleteSourceClipsAfterMerge: Bool {
    didSet {
      defaults.set(deleteSourceClipsAfterMerge, forKey: Keys.deleteSourceClipsAfterMerge)
    }
  }

  public var autoTrimEnabled: Bool {
    didSet {
      defaults.set(autoTrimEnabled, forKey: Keys.autoTrimEnabled)
    }
  }

  public var autoTrimInterval: TrimInterval {
    didSet {
      defaults.set(autoTrimInterval.rawValue, forKey: Keys.autoTrimInterval)
    }
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

    if let rawStyle = suite.string(forKey: Keys.transitionStyle),
      let style = TransitionStyle(rawValue: rawStyle)
    {
      self.transitionStyle = style
    } else {
      self.transitionStyle = .none
    }

    let storedDuration = suite.double(forKey: Keys.transitionDuration)
    if storedDuration > 0, let duration = TransitionDuration(rawValue: storedDuration) {
      self.transitionDuration = duration
    } else {
      self.transitionDuration = .medium
    }

    if suite.object(forKey: Keys.preserveMetadata) != nil {
      self.preserveMetadata = suite.bool(forKey: Keys.preserveMetadata)
    } else {
      self.preserveMetadata = true
    }

    self.deleteSourceClipsAfterMerge = suite.bool(forKey: Keys.deleteSourceClipsAfterMerge)
    self.autoTrimEnabled = suite.bool(forKey: Keys.autoTrimEnabled)

    let storedInterval = suite.integer(forKey: Keys.autoTrimInterval)
    if let interval = TrimInterval(rawValue: storedInterval) {
      self.autoTrimInterval = interval
    } else {
      self.autoTrimInterval = .thirtySeconds
    }
  }

  /// Re-reads all values from the shared App Group UserDefaults store.
  public func reload() {
    let newStyle: TransitionStyle
    if let rawStyle = defaults.string(forKey: Keys.transitionStyle),
      let style = TransitionStyle(rawValue: rawStyle)
    {
      newStyle = style
    } else {
      newStyle = .none
    }
    if transitionStyle != newStyle {
      transitionStyle = newStyle
    }

    let storedDuration = defaults.double(forKey: Keys.transitionDuration)
    let newDuration: TransitionDuration =
      (storedDuration > 0 ? TransitionDuration(rawValue: storedDuration) : nil) ?? .medium
    if transitionDuration != newDuration {
      transitionDuration = newDuration
    }

    let newPreserveMetadata =
      defaults.object(forKey: Keys.preserveMetadata) != nil
      ? defaults.bool(forKey: Keys.preserveMetadata)
      : true
    if preserveMetadata != newPreserveMetadata {
      preserveMetadata = newPreserveMetadata
    }

    let newDeleteSources = defaults.bool(forKey: Keys.deleteSourceClipsAfterMerge)
    if deleteSourceClipsAfterMerge != newDeleteSources {
      deleteSourceClipsAfterMerge = newDeleteSources
    }

    let newAutoTrim = defaults.bool(forKey: Keys.autoTrimEnabled)
    if autoTrimEnabled != newAutoTrim {
      autoTrimEnabled = newAutoTrim
    }

    let storedInterval = defaults.integer(forKey: Keys.autoTrimInterval)
    let newInterval = TrimInterval(rawValue: storedInterval) ?? .thirtySeconds
    if autoTrimInterval != newInterval {
      autoTrimInterval = newInterval
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
