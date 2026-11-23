import CoreGraphics
import CoreLocation
import Foundation
import UIKit

/// Visual orientation derived from a clip's oriented (post-transform) dimensions.
public nonisolated enum ClipOrientation: String, Sendable, Equatable, CaseIterable {
  case portrait
  case landscape
  case square

  /// Title-cased label for badges and accessibility descriptions.
  public var displayName: String {
    switch self {
    case .portrait:
      "Portrait"
    case .landscape:
      "Landscape"
    case .square:
      "Square"
    }
  }

  /// Lowercase label for inline warning prose.
  public var proseName: String {
    switch self {
    case .portrait:
      "portrait"
    case .landscape:
      "landscape"
    case .square:
      "square"
    }
  }

  /// SF Symbol name representing this frame orientation.
  public var symbolName: String {
    switch self {
    case .portrait:
      "rectangle.portrait"
    case .landscape:
      "rectangle"
    case .square:
      "square"
    }
  }
}

/// Evaluates orientation consistency across an ordered list of clips using the first clip
/// as the reference orientation that defines the merged video's output canvas.
public nonisolated struct ClipOrientationAudit: Sendable, Equatable {
  public let referenceOrientation: ClipOrientation
  public let mismatchedClipIDs: Set<UUID>

  public var hasMismatches: Bool {
    if mismatchedClipIDs.isEmpty {
      return false
    } else {
      return true
    }
  }

  public var mismatchCount: Int {
    mismatchedClipIDs.count
  }

  /// User-facing explanation shown when one or more clips differ from the first clip's
  /// orientation, or `nil` when all clips match.
  public var warningMessage: String? {
    guard hasMismatches else {
      return nil
    }

    let reference = referenceOrientation.proseName
    if mismatchCount == 1 {
      return
        "The first clip sets the output to \(reference). 1 clip has a different orientation and will appear with black bars."
    } else {
      return
        "The first clip sets the output to \(reference). \(mismatchCount) clips have a different orientation and will appear with black bars."
    }
  }

  public func isMismatched(_ clip: ClipItem) -> Bool {
    return mismatchedClipIDs.contains(clip.id)
  }

  public init?(clips: [ClipItem]) {
    guard clips.count >= 2, let referenceOrientation = clips[0].orientation else {
      return nil
    }

    var mismatched: Set<UUID> = []
    for clip in clips.dropFirst() {
      if let clipOrientation = clip.orientation, clipOrientation != referenceOrientation {
        mismatched.insert(clip.id)
      }
    }

    self.referenceOrientation = referenceOrientation
    self.mismatchedClipIDs = mismatched
  }
}

/// Lightweight representation of a video clip selected for merging.
public nonisolated struct ClipItem: Identifiable, Sendable {
  public let id: UUID
  public let fileURL: URL
  public let assetLocalIdentifier: String?
  public let duration: TimeInterval
  public let thumbnail: UIImage?
  public let naturalSize: CGSize
  public let preferredTransform: CGAffineTransform
  public let creationDate: Date?
  public let location: CLLocation?
  public let filename: String?

  public init(
    id: UUID = UUID(),
    fileURL: URL,
    assetLocalIdentifier: String? = nil,
    duration: TimeInterval,
    thumbnail: UIImage? = nil,
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform = .identity,
    creationDate: Date? = nil,
    location: CLLocation? = nil,
    filename: String? = nil
  ) {
    self.id = id
    self.fileURL = fileURL
    self.assetLocalIdentifier = assetLocalIdentifier
    self.duration = duration
    self.thumbnail = thumbnail
    self.naturalSize = naturalSize
    self.preferredTransform = preferredTransform
    self.creationDate = creationDate
    self.location = location
    self.filename = filename
  }

  /// Display dimensions after applying a video track's `preferredTransform`.
  public nonisolated static func orientedSize(
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform
  ) -> CGSize {
    let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    return CGSize(width: abs(rect.width), height: abs(rect.height))
  }

  /// Display dimensions after applying the video track's `preferredTransform`.
  public var orientedSize: CGSize {
    Self.orientedSize(naturalSize: naturalSize, preferredTransform: preferredTransform)
  }

  /// Visual orientation after applying the video track's `preferredTransform`, or `nil` for
  /// zero-dimension clips.
  public var orientation: ClipOrientation? {
    let size = orientedSize
    guard size.width > 0, size.height > 0 else {
      return nil
    }

    if abs(size.width - size.height) < 1 {
      return .square
    } else if size.width > size.height {
      return .landscape
    } else {
      return .portrait
    }
  }

  /// Human-readable duration string (e.g. `0:24`, `1:05`, `1:02:15`).
  public var formattedDuration: String {
    DurationFormatter.format(duration)
  }

  /// Short localized capture time string (e.g. `10:14 AM`), if available.
  public var formattedCaptureTime: String? {
    creationDate?.formatted(date: .omitted, time: .shortened)
  }
}

nonisolated extension ClipItem: Equatable {
  public static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
    return lhs.id == rhs.id
  }
}

/// Formats clip and montage durations consistently across the app and extension.
public nonisolated enum DurationFormatter {
  public static func format(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else {
      return "0:00"
    }

    let totalSeconds = Int(seconds.rounded())
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    } else {
      return String(format: "%d:%02d", minutes, remainingSeconds)
    }
  }
}
