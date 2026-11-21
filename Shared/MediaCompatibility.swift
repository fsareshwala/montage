import AVFoundation
import CoreGraphics
import Foundation
import Photos
import UIKit

// MARK: - Task Sleep Compatibility

/// Single-API task delay utility that uses `Duration` clocks on iOS 16+ and nanosecond sleep on iOS 15.
public nonisolated final class TaskSleepCompatibility: Sendable {
  public static let shared = TaskSleepCompatibility()

  public init() {}

  public func sleep(milliseconds: UInt64) async throws {
    if #available(iOS 16, *) {
      try await Task.sleep(for: .milliseconds(Int64(milliseconds)))
    } else {
      try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
  }
}

// MARK: - Video Asset Exporter Compatibility

/// Single-API exporter for `AVComposition` assets that hides the difference between
/// iOS 18+'s `states(updateInterval:)` / `export(to:as:)` API and iOS 15–17's `export()` API.
public nonisolated final class VideoAssetExporter: Sendable {
  public static let shared = VideoAssetExporter()

  public init() {}

  public func export(
    composition: AVComposition,
    presetName: String,
    videoComposition: AVVideoComposition,
    audioMix: AVAudioMix?,
    timeRange: CMTimeRange?,
    outputURL: URL,
    fileType: AVFileType,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
      throw VideoMergeError.exportFailed("Preset \(presetName) unavailable.")
    }

    session.videoComposition = videoComposition
    session.audioMix = audioMix
    session.shouldOptimizeForNetworkUse = false
    if let timeRange {
      session.timeRange = timeRange
    }

    if #available(iOS 18, *) {
      try await exportModern(
        session: session,
        outputURL: outputURL,
        fileType: fileType,
        onProgress: onProgress
      )
    } else {
      try await exportLegacy(
        session: session,
        outputURL: outputURL,
        fileType: fileType,
        onProgress: onProgress
      )
    }
  }

  @available(iOS 18, *)
  private func exportModern(
    session: AVAssetExportSession,
    outputURL: URL,
    fileType: AVFileType,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let progressTask = Task {
      for await state in session.states(updateInterval: 0.1) {
        if case .exporting(let progress) = state {
          onProgress(progress.fractionCompleted)
        }
      }
    }

    do {
      try await session.export(to: outputURL, as: fileType)
      progressTask.cancel()
      onProgress(1.0)
    } catch {
      progressTask.cancel()
      throw error
    }
  }

  private func exportLegacy(
    session: AVAssetExportSession,
    outputURL: URL,
    fileType: AVFileType,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    session.outputURL = outputURL
    session.outputFileType = fileType

    // `AVAssetExportSession`'s `progress` and `cancelExport()` are safe to access
    // concurrently while an export is running.
    let sessionBox = UncheckedSendableBox(session)
    let progressTask = Task {
      while !Task.isCancelled {
        let fraction = max(0, min(1, Double(sessionBox.value.progress)))
        onProgress(fraction)
        try? await TaskSleepCompatibility.shared.sleep(milliseconds: 100)
      }
    }

    await withTaskCancellationHandler {
      await sessionBox.value.export()
    } onCancel: {
      sessionBox.value.cancelExport()
    }
    progressTask.cancel()

    switch session.status {
    case .completed:
      onProgress(1.0)
    case .cancelled:
      throw CancellationError()
    case .failed:
      throw session.error ?? VideoMergeError.exportFailed("Unknown export error.")
    default:
      if Task.isCancelled {
        throw CancellationError()
      }
      throw session.error ?? VideoMergeError.exportFailed("Export did not complete.")
    }
  }
}

// MARK: - Video Thumbnail Generator Compatibility

/// Single-API thumbnail generator that uses `AVAssetImageGenerator.image(at:)` on iOS 16+
/// and `generateCGImagesAsynchronously(forTimes:)` on iOS 15.
public nonisolated final class VideoThumbnailGenerator: Sendable {
  public static let shared = VideoThumbnailGenerator()

  public init() {}

  public func generateThumbnail(
    for asset: AVAsset,
    at time: CMTime = .zero,
    maximumSize: CGSize
  ) async -> UIImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = maximumSize
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

    if #available(iOS 16, *) {
      guard let result = try? await generator.image(at: time) else {
        return nil
      }
      return UIImage(cgImage: result.image)
    } else {
      let generatorBox = UncheckedSendableBox(generator)
      let cgImage: CGImage? = await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          let once = OnceContinuation(continuation)
          generatorBox.value.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
            _, image, _, result, _ in
            if result == .succeeded, let image {
              once.resume(returning: image)
            } else {
              once.resume(returning: nil)
            }
          }
        }
      } onCancel: {
        generatorBox.value.cancelAllCGImageGeneration()
      }
      return cgImage.map(UIImage.init(cgImage:))
    }
  }
}

// MARK: - Video Composition Builder Compatibility

/// Single-API builder for `AVVideoComposition` and its instructions, using immutable
/// `.Configuration` APIs on iOS 26+ and `AVMutableVideoComposition*` on iOS 15–25.
public nonisolated final class VideoCompositionBuilder: Sendable {
  public static let shared = VideoCompositionBuilder()

  public init() {}

  public func makeLayerInstruction(
    track: AVAssetTrack,
    transform: CGAffineTransform? = nil,
    at time: CMTime = .zero,
    opacity: Float? = nil,
    opacityRamp: (start: Float, end: Float, range: CMTimeRange)? = nil,
    transformRamp: (start: CGAffineTransform, end: CGAffineTransform, range: CMTimeRange)? = nil
  ) -> AVVideoCompositionLayerInstruction {
    if #available(iOS 26, *) {
      var config = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
      if let transform {
        config.setTransform(transform, at: time)
      }
      if let opacity {
        config.setOpacity(opacity, at: time)
      }
      if let opacityRamp {
        config.addOpacityRamp(
          AVVideoCompositionLayerInstruction.OpacityRamp(
            timeRange: opacityRamp.range,
            start: opacityRamp.start,
            end: opacityRamp.end
          )
        )
      }
      if let transformRamp {
        config.addTransformRamp(
          AVVideoCompositionLayerInstruction.TransformRamp(
            timeRange: transformRamp.range,
            start: transformRamp.start,
            end: transformRamp.end
          )
        )
      }
      return AVVideoCompositionLayerInstruction(configuration: config)
    } else {
      let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
      if let transform {
        layer.setTransform(transform, at: time)
      }
      if let opacity {
        layer.setOpacity(opacity, at: time)
      }
      if let opacityRamp {
        layer.setOpacityRamp(
          fromStartOpacity: opacityRamp.start,
          toEndOpacity: opacityRamp.end,
          timeRange: opacityRamp.range
        )
      }
      if let transformRamp {
        layer.setTransformRamp(
          fromStart: transformRamp.start,
          toEnd: transformRamp.end,
          timeRange: transformRamp.range
        )
      }
      return layer
    }
  }

  public func makeVideoInstruction(
    timeRange: CMTimeRange,
    backgroundColor: CGColor,
    layerInstructions: [AVVideoCompositionLayerInstruction]
  ) -> AVVideoCompositionInstruction {
    if #available(iOS 26, *) {
      let config = AVVideoCompositionInstruction.Configuration(
        backgroundColor: backgroundColor,
        enablePostProcessing: true,
        layerInstructions: layerInstructions,
        requiredSourceSampleDataTrackIDs: [],
        timeRange: timeRange
      )
      return AVVideoCompositionInstruction(configuration: config)
    } else {
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = timeRange
      instruction.backgroundColor = backgroundColor
      instruction.layerInstructions = layerInstructions
      return instruction
    }
  }

  public func makeVideoComposition(
    renderSize: CGSize,
    frameDuration: CMTime,
    instructions: [AVVideoCompositionInstruction]
  ) -> AVVideoComposition {
    if #available(iOS 26, *) {
      let config = AVVideoComposition.Configuration(
        animationTool: nil,
        colorPrimaries: nil,
        colorTransferFunction: nil,
        colorYCbCrMatrix: nil,
        customVideoCompositorClass: nil,
        frameDuration: frameDuration,
        instructions: instructions,
        outputBufferDescription: nil,
        perFrameHDRDisplayMetadataPolicy: .propagate,
        renderScale: 1.0,
        renderSize: renderSize,
        sourceSampleDataTrackIDs: [],
        sourceTrackIDForFrameTiming: kCMPersistentTrackID_Invalid,
        spatialVideoConfigurations: []
      )
      return AVVideoComposition(configuration: config)
    } else {
      let videoComposition = AVMutableVideoComposition()
      videoComposition.renderSize = renderSize
      videoComposition.frameDuration = frameDuration
      videoComposition.instructions = instructions
      return videoComposition
    }
  }
}

// MARK: - PhotoKit Resource Compatibility

/// Single-API helper for reading `PHAssetResource` filenames across iOS 15–27+.
public nonisolated final class PhotoAssetResourceCompatibility: Sendable {
  public static let shared = PhotoAssetResourceCompatibility()

  public init() {}

  public func filename(for resource: PHAssetResource) -> String? {
    if #available(iOS 27, *) {
      resource.filename
    } else {
      resource.originalFilename
    }
  }
}

// MARK: - Internal Concurrency Helpers

private nonisolated final class UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }
}

private nonisolated final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, Never>?

  init(_ continuation: CheckedContinuation<Value, Never>) {
    self.continuation = continuation
  }

  func resume(returning value: Value) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: value)
  }
}
