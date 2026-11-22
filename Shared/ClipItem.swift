import CoreGraphics
import CoreLocation
import Foundation
import UIKit

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
