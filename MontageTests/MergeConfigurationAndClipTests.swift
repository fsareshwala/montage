import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Montage

@Suite("MergeConfiguration, ClipItem, and Formatting")
struct MergeConfigurationAndClipTests {

  // MARK: - MergeConfiguration.effectiveTransitionDuration

  @Test("Effective transition duration is zero for instant cut")
  func effectiveTransitionDurationZeroCases() {
    let noneConfig = MergeConfiguration(transitionStyle: .none)
    #expect(noneConfig.effectiveTransitionDuration(between: 5.0, and: 5.0) == 0)
  }

  @Test(
    "Effective transition duration uses 0.5s for normal clips and clamps to 45% for short clips"
  )
  func effectiveTransitionDurationClamping() {
    let config = MergeConfiguration(transitionStyle: .crossDissolve)

    // Both clips plenty long -> fixed 0.5s
    #expect(abs(config.effectiveTransitionDuration(between: 5.0, and: 8.0) - 0.5) < 0.0001)

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
    let config = MergeConfiguration()

    #expect(config.estimatedOutputDuration(for: []) == 0)
    #expect(config.estimatedOutputDuration(for: [4.5]) == 4.5)
    #expect(config.estimatedOutputDuration(for: [3.0, 4.5, 2.5]) == 10.0)
  }

  @Test("Estimated output duration subtracts transition overlaps across multiple boundaries")
  func estimatedOutputDurationWithTransitions() {
    let config = MergeConfiguration(transitionStyle: .slide)

    // Single clip has no boundary overlap.
    #expect(config.estimatedOutputDuration(for: [3.0]) == 3.0)

    // 2 normal clips: 4 + 6 - 0.5 = 9.5
    #expect(abs(config.estimatedOutputDuration(for: [4.0, 6.0]) - 9.5) < 0.0001)

    // 3 clips where middle clip is 1.0s: each boundary clamps to 0.45s -> (4 + 1 + 5) - 0.45 - 0.45 = 9.1
    #expect(abs(config.estimatedOutputDuration(for: [4.0, 1.0, 5.0]) - 9.1) < 0.0001)
  }

  @Test("Auto-trim floors durations at or above the interval and leaves shorter videos untouched")
  func estimatedOutputDurationAutoTrim() {
    let trim15 = MergeConfiguration(autoTrimEnabled: true, autoTrimInterval: .fifteenSeconds)
    #expect(trim15.estimatedOutputDuration(for: [7, 7]) == 14)
    #expect(trim15.estimatedOutputDuration(for: [7, 8]) == 15)
    #expect(trim15.estimatedOutputDuration(for: [10, 14]) == 15)
    #expect(trim15.estimatedOutputDuration(for: [20, 27]) == 45)

    let trim30 = MergeConfiguration(autoTrimEnabled: true, autoTrimInterval: .thirtySeconds)
    #expect(trim30.estimatedOutputDuration(for: [10, 14]) == 24)
    #expect(trim30.estimatedOutputDuration(for: [15, 15]) == 30)
    #expect(trim30.estimatedOutputDuration(for: [20, 27.5]) == 30)
    #expect(trim30.estimatedOutputDuration(for: [50, 45]) == 90)

    let trim60 = MergeConfiguration(autoTrimEnabled: true, autoTrimInterval: .oneMinute)
    #expect(trim60.estimatedOutputDuration(for: [30, 29]) == 59)
    #expect(trim60.estimatedOutputDuration(for: [30, 30]) == 60)
    #expect(trim60.estimatedOutputDuration(for: [70, 55]) == 120)
  }

  @Test("Auto-trim applies after subtracting transition overlap")
  func estimatedOutputDurationTransitionsThenAutoTrim() {
    let config = MergeConfiguration(
      transitionStyle: .crossDissolve,
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

  @Test("ClipItem.orientation resolves portrait, landscape, square, and zero-size clips")
  func clipItemOrientation() {
    let baseURL = URL(fileURLWithPath: "/tmp/sample.mov")

    let landscape = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: .identity
    )
    #expect(landscape.orientation == .landscape)

    let rotatedLandscape = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: .pi)
    )
    #expect(rotatedLandscape.orientation == .landscape)

    let portraitCW = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
    )
    #expect(portraitCW.orientation == .portrait)

    let portraitCCW = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: -.pi / 2)
    )
    #expect(portraitCCW.orientation == .portrait)

    let nativePortrait = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1080, height: 1920),
      preferredTransform: .identity
    )
    #expect(nativePortrait.orientation == .portrait)

    let square = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1080, height: 1080),
      preferredTransform: .identity
    )
    #expect(square.orientation == .square)

    let nearSquare = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1080.4, height: 1080.0),
      preferredTransform: .identity
    )
    #expect(nearSquare.orientation == .square)

    let zeroSize = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: .zero,
      preferredTransform: .identity
    )
    #expect(zeroSize.orientation == nil)

    let zeroHeight = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1920, height: 0),
      preferredTransform: .identity
    )
    #expect(zeroHeight.orientation == nil)

    for orientation in ClipOrientation.allCases {
      #expect(!orientation.displayName.isEmpty)
      #expect(!orientation.proseName.isEmpty)
      #expect(!orientation.displayName.contains("&"))
      #expect(!orientation.displayName.localizedCaseInsensitiveContains("outing"))
      #expect(UIImage(systemName: orientation.symbolName) != nil)
    }
  }

  @Test("ClipOrientationAudit uses the first clip as reference and tracks reordered mismatches")
  func clipOrientationAudit() throws {
    let baseURL = URL(fileURLWithPath: "/tmp/sample.mov")

    let portrait1 = ClipItem(
      fileURL: baseURL,
      duration: 4.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
    )
    let portrait2 = ClipItem(
      fileURL: baseURL,
      duration: 5.0,
      naturalSize: CGSize(width: 1080, height: 1920),
      preferredTransform: .identity
    )
    let landscape1 = ClipItem(
      fileURL: baseURL,
      duration: 6.0,
      naturalSize: CGSize(width: 1920, height: 1080),
      preferredTransform: .identity
    )
    let square1 = ClipItem(
      fileURL: baseURL,
      duration: 3.0,
      naturalSize: CGSize(width: 1080, height: 1080),
      preferredTransform: .identity
    )
    let zeroClip = ClipItem(
      fileURL: baseURL,
      duration: 2.0,
      naturalSize: .zero,
      preferredTransform: .identity
    )

    // Fewer than 2 clips or unknown first orientation returns nil.
    #expect(ClipOrientationAudit(clips: []) == nil)
    #expect(ClipOrientationAudit(clips: [portrait1]) == nil)
    #expect(ClipOrientationAudit(clips: [zeroClip, portrait1]) == nil)

    // All matching orientations report no mismatches and no warning message.
    let allPortrait = try #require(ClipOrientationAudit(clips: [portrait1, portrait2]))
    #expect(allPortrait.referenceOrientation == .portrait)
    #expect(allPortrait.hasMismatches == false)
    #expect(allPortrait.mismatchCount == 0)
    #expect(allPortrait.warningMessage == nil)
    #expect(allPortrait.isMismatched(portrait1) == false)
    #expect(allPortrait.isMismatched(portrait2) == false)

    // Subsequent clip with unknown dimensions is ignored safely.
    let trailingZero = try #require(ClipOrientationAudit(clips: [portrait1, zeroClip]))
    #expect(trailingZero.hasMismatches == false)
    #expect(trailingZero.isMismatched(zeroClip) == false)
    #expect(trailingZero.warningMessage == nil)

    // Portrait first flags only the landscape clip with singular warning copy.
    let portraitFirst = try #require(
      ClipOrientationAudit(clips: [portrait1, landscape1, portrait2])
    )
    #expect(portraitFirst.referenceOrientation == .portrait)
    #expect(portraitFirst.hasMismatches == true)
    #expect(portraitFirst.mismatchCount == 1)
    #expect(portraitFirst.isMismatched(portrait1) == false)
    #expect(portraitFirst.isMismatched(landscape1) == true)
    #expect(portraitFirst.isMismatched(portrait2) == false)
    let singularWarning = try #require(portraitFirst.warningMessage)
    #expect(
      singularWarning
        == "The first clip sets the output to portrait. 1 clip has a different orientation and will appear with black bars."
    )
    #expect(!singularWarning.contains("&"))
    #expect(!singularWarning.localizedCaseInsensitiveContains("outing"))

    // Reordering so landscape is first flags both portrait clips with plural warning copy.
    let landscapeFirst = try #require(
      ClipOrientationAudit(clips: [landscape1, portrait1, portrait2])
    )
    #expect(landscapeFirst.referenceOrientation == .landscape)
    #expect(landscapeFirst.hasMismatches == true)
    #expect(landscapeFirst.mismatchCount == 2)
    #expect(landscapeFirst.isMismatched(landscape1) == false)
    #expect(landscapeFirst.isMismatched(portrait1) == true)
    #expect(landscapeFirst.isMismatched(portrait2) == true)
    let pluralWarning = try #require(landscapeFirst.warningMessage)
    #expect(
      pluralWarning
        == "The first clip sets the output to landscape. 2 clips have a different orientation and will appear with black bars."
    )
    #expect(!pluralWarning.contains("&"))
    #expect(!pluralWarning.localizedCaseInsensitiveContains("outing"))

    // Square clips also mismatch against landscape/portrait and vice versa.
    let squareFirst = try #require(ClipOrientationAudit(clips: [square1, landscape1]))
    #expect(squareFirst.referenceOrientation == .square)
    #expect(squareFirst.hasMismatches == true)
    #expect(squareFirst.mismatchCount == 1)
    #expect(squareFirst.isMismatched(square1) == false)
    #expect(squareFirst.isMismatched(landscape1) == true)
    #expect(
      squareFirst.warningMessage
        == "The first clip sets the output to square. 1 clip has a different orientation and will appear with black bars."
    )
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
