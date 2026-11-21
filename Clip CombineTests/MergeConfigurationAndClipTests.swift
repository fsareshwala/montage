import CoreGraphics
import Foundation
import Testing
@testable import Clip_Combine

@Suite("MergeConfiguration, ClipItem, and Formatting")
struct MergeConfigurationAndClipTests {

  // MARK: - MergeConfiguration.effectiveTransitionDuration

  @Test("Effective transition duration is zero for instant cut or non-positive duration")
  func effectiveTransitionDurationZeroCases() {
    let noneConfig = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )
    #expect(noneConfig.effectiveTransitionDuration(between: 5.0, and: 5.0) == 0)

    let zeroDurationConfig = MergeConfiguration(
      transitionStyle: .crossDissolve,
      transitionDuration: 0,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )
    #expect(zeroDurationConfig.effectiveTransitionDuration(between: 5.0, and: 5.0) == 0)
  }

  @Test("Effective transition duration uses configured value for normal clips and clamps to 45% for short clips")
  func effectiveTransitionDurationClamping() {
    let config = MergeConfiguration(
      transitionStyle: .crossDissolve,
      transitionDuration: 0.7,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )

    // Both clips plenty long -> full 0.7s
    #expect(abs(config.effectiveTransitionDuration(between: 5.0, and: 8.0) - 0.7) < 0.0001)

    // First clip 1.0s -> clamped to 0.45s
    #expect(abs(config.effectiveTransitionDuration(between: 1.0, and: 5.0) - 0.45) < 0.0001)

    // Second clip 0.4s -> clamped to 0.18s
    #expect(abs(config.effectiveTransitionDuration(between: 5.0, and: 0.4) - 0.18) < 0.0001)

    // Zero-length clip -> 0
    #expect(config.effectiveTransitionDuration(between: 0.0, and: 4.0) == 0)
  }

  // MARK: - MergeConfiguration.estimatedOutputDuration

  @Test("Estimated output duration handles empty, single clip, and instant cut")
  func estimatedOutputDurationBasic() {
    let config = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )

    #expect(config.estimatedOutputDuration(for: []) == 0)
    #expect(config.estimatedOutputDuration(for: [4.5]) == 4.5)
    #expect(config.estimatedOutputDuration(for: [3.0, 4.5, 2.5]) == 10.0)
  }

  @Test("Estimated output duration subtracts transition overlaps across multiple boundaries")
  func estimatedOutputDurationWithTransitions() {
    let config = MergeConfiguration(
      transitionStyle: .slide,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )

    // Single clip has no boundary overlap.
    #expect(config.estimatedOutputDuration(for: [3.0]) == 3.0)

    // 2 normal clips: 4 + 6 - 0.5 = 9.5
    #expect(abs(config.estimatedOutputDuration(for: [4.0, 6.0]) - 9.5) < 0.0001)

    // 3 clips where middle clip is 1.0s: each boundary clamps to 0.45s -> (4 + 1 + 5) - 0.45 - 0.45 = 9.1
    #expect(abs(config.estimatedOutputDuration(for: [4.0, 1.0, 5.0]) - 9.1) < 0.0001)
  }

  @Test("Auto-trim floors durations at or above the interval and leaves shorter videos untouched")
  func estimatedOutputDurationAutoTrim() {
    let trim30 = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: true,
      autoTrimInterval: .thirtySeconds
    )

    #expect(trim30.estimatedOutputDuration(for: [10, 14]) == 24)
    #expect(trim30.estimatedOutputDuration(for: [15, 15]) == 30)
    #expect(trim30.estimatedOutputDuration(for: [20, 27.5]) == 30)
    #expect(trim30.estimatedOutputDuration(for: [50, 45]) == 90)

    let trim60 = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: true,
      autoTrimInterval: .oneMinute
    )

    #expect(trim60.estimatedOutputDuration(for: [30, 29]) == 59)
    #expect(trim60.estimatedOutputDuration(for: [30, 30]) == 60)
    #expect(trim60.estimatedOutputDuration(for: [70, 55]) == 120)
  }

  @Test("Auto-trim applies after subtracting transition overlap")
  func estimatedOutputDurationTransitionsThenAutoTrim() {
    let config = MergeConfiguration(
      transitionStyle: .crossDissolve,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: true,
      autoTrimInterval: .thirtySeconds
    )

    // 16 + 15 - 0.5 = 30.5 -> trimmed to 30.0
    #expect(abs(config.estimatedOutputDuration(for: [16.0, 15.0]) - 30.0) < 0.0001)

    // 15 + 15.2 - 0.5 = 29.7 -> under 30s, untouched
    #expect(abs(config.estimatedOutputDuration(for: [15.0, 15.2]) - 29.7) < 0.0001)
  }

  // MARK: - DurationFormatter

  @Test(
    "DurationFormatter formats seconds, minutes, hours, and edge cases consistently",
    arguments: [
      (0.0, "0:00"),
      (5.0, "0:05"),
      (59.4, "0:59"),
      (59.6, "1:00"),
      (65.0, "1:05"),
      (3600.0, "1:00:00"),
      (3735.0, "1:02:15"),
      (-3.0, "0:00"),
      (Double.nan, "0:00"),
      (Double.infinity, "0:00"),
    ]
  )
  func durationFormatter(seconds: TimeInterval, expected: String) {
    #expect(DurationFormatter.format(seconds) == expected)
  }

  // MARK: - ClipItem

  @Test("ClipItem.orientedSize accounts for 90, -90, and 180 degree preferred transforms")
  func clipItemOrientedSize() {
    let baseURL = URL(fileURLWithPath: "/tmp/sample.mov")

    let landscape = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: .identity
    )
    #expect(abs(landscape.orientedSize.width - 1920) < 0.5)
    #expect(abs(landscape.orientedSize.height - 1080) < 0.5)

    let portraitCW = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
    )
    #expect(abs(portraitCW.orientedSize.width - 1080) < 0.5)
    #expect(abs(portraitCW.orientedSize.height - 1920) < 0.5)

    let portraitCCW = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: -.pi / 2)
    )
    #expect(abs(portraitCCW.orientedSize.width - 1080) < 0.5)
    #expect(abs(portraitCCW.orientedSize.height - 1920) < 0.5)

    let rotated180 = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: .pi)
    )
    #expect(abs(rotated180.orientedSize.width - 1920) < 0.5)
    #expect(abs(rotated180.orientedSize.height - 1080) < 0.5)
  }

  @Test("ClipItem formatting and identity-based equality")
  func clipItemFormattingAndEquality() {
    let sharedID = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    let first = ClipItem(
      id: sharedID,
      fileURL: URL(fileURLWithPath: "/tmp/a.mov"),
      duration: 65,
      naturalSize: CGSize(width: 1920, height: 1080),
      creationDate: date
    )
    let secondSameID = ClipItem(
      id: sharedID,
      fileURL: URL(fileURLWithPath: "/tmp/b.mov"),
      duration: 12,
      naturalSize: CGSize(width: 1280, height: 720),
      creationDate: nil
    )
    let thirdDifferentID = ClipItem(
      fileURL: URL(fileURLWithPath: "/tmp/a.mov"),
      duration: 65,
      naturalSize: CGSize(width: 1920, height: 1080)
    )

    #expect(first == secondSameID)
    #expect(first != thirdDifferentID)
    #expect(first.formattedDuration == "1:05")
    #expect(first.formattedCaptureTime != nil)
    #expect(!(first.formattedCaptureTime ?? "").isEmpty)
    #expect(secondSameID.formattedCaptureTime == nil)
  }

  // MARK: - MergePhase and VideoMergeError

  @Test("MergePhase progress is monotonic and clamps export fractions to [0, 1]")
  func mergePhaseProgressAndLabels() {
    let phases: [MergePhase] = [
      .preparing,
      .merging(0.0),
      .merging(0.5),
      .merging(1.0),
      .saving,
      .cleaningUp,
      .completed,
    ]

    for phase in phases {
      #expect(!phase.statusText.isEmpty)
      #expect(!phase.statusText.contains("&"))
    }

    #expect(MergePhase.preparing.overallProgress == 0.05)
    #expect(MergePhase.merging(-1.0).overallProgress == 0.05)
    #expect(abs(MergePhase.merging(0.5).overallProgress - 0.475) < 0.0001)
    #expect(abs(MergePhase.merging(1.0).overallProgress - 0.90) < 0.0001)
    #expect(abs(MergePhase.merging(2.0).overallProgress - 0.90) < 0.0001)
    #expect(MergePhase.saving.overallProgress == 0.94)
    #expect(MergePhase.cleaningUp.overallProgress == 0.98)
    #expect(MergePhase.completed.overallProgress == 1.0)
  }

  @Test("All VideoMergeError cases provide non-empty user-facing descriptions")
  func videoMergeErrorDescriptions() {
    let errors: [VideoMergeError] = [
      .insufficientClips,
      .photoLibraryAccessDenied,
      .unreadableVideo,
      .compositionFailed("track error"),
      .exportFailed("disk full"),
      .cancelled,
    ]

    for error in errors {
      let description = error.errorDescription ?? ""
      #expect(!description.isEmpty)
      #expect(!description.contains("&"))
    }
  }
}
