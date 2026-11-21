import AVFoundation
import CoreGraphics
import CoreLocation
import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

/// Progress phases reported during a video merge and save operation.
public nonisolated enum MergePhase: Sendable, Equatable {
  case preparing
  case merging(Double)
  case saving
  case cleaningUp
  case completed

  public var statusText: String {
    switch self {
    case .preparing:
      "Preparing clips…"
    case .merging:
      "Merging clips…"
    case .saving:
      "Saving to Photos…"
    case .cleaningUp:
      "Cleaning up source clips…"
    case .completed:
      "Saved to Photos"
    }
  }

  public var overallProgress: Double {
    switch self {
    case .preparing:
      0.05
    case .merging(let exportProgress):
      0.05 + (max(0, min(1, exportProgress)) * 0.85)
    case .saving:
      0.94
    case .cleaningUp:
      0.98
    case .completed:
      1.0
    }
  }
}

/// Output summary returned after a merge finishes saving to the Photo Library.
public nonisolated struct MergeResult: Sendable {
  public let savedAssetIdentifier: String?
  public let outputDuration: TimeInterval
  public let sourceAssetIdentifiers: [String]
}

/// Errors produced by `VideoMergeEngine`.
public nonisolated enum VideoMergeError: LocalizedError, Sendable {
  case insufficientClips
  case photoLibraryAccessDenied
  case unreadableVideo
  case compositionFailed(String)
  case exportFailed(String)
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .insufficientClips:
      "Select at least 2 videos to merge."
    case .photoLibraryAccessDenied:
      "Photo Library access is needed to save your merged video. Enable access in the Clip Combine app or Settings."
    case .unreadableVideo:
      "One of the selected videos could not be loaded."
    case .compositionFailed(let reason):
      "Could not build video composition: \(reason)"
    case .exportFailed(let reason):
      "Export failed: \(reason)"
    case .cancelled:
      "Merge cancelled."
    }
  }
}

/// Handles loading shared videos, resolving PhotoKit metadata, normalizing mixed orientations,
/// applying transitions and auto-trimming, exporting safely within Share Extension memory limits,
/// saving to Photos, and optionally deleting source clips.
public actor VideoMergeEngine {
  /// Low-resolution thumbnail cap to keep Share Extension memory well under 120 MB.
  public nonisolated static let thumbnailMaxSize = CGSize(width: 240, height: 240)

  /// Brief fade-out applied at the cut point when auto-trim shortens the output.
  private static let autoTrimFadeOutSeconds: TimeInterval = 0.3

  public init() {}

  // MARK: - Loading Shared Clips

  /// Extracts movie attachments from `NSExtensionItem`s, copies them to a temporary directory,
  /// generates low-memory thumbnails, and resolves matching `PHAsset` metadata when authorized.
  public func loadClips(
    from extensionItems: [NSExtensionItem],
    onProgress: (@Sendable (Int, Int) -> Void)? = nil
  ) async throws -> [ClipItem] {
    let movieProviders = extractMovieProviders(from: extensionItems)
    guard !movieProviders.isEmpty else {
      return []
    }

    let sessionDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ClipCombineInput", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

    var loadedClips: [ClipItem] = []
    loadedClips.reserveCapacity(movieProviders.count)

    for (index, provider) in movieProviders.enumerated() {
      try Task.checkCancellation()
      onProgress?(index + 1, movieProviders.count)

      if let clip = try await loadSingleClip(
        from: provider,
        index: index,
        destinationDirectory: sessionDir
      ) {
        loadedClips.append(clip)
      }
    }

    // Match back to PHAssets when Photo Library access is granted so we can preserve
    // exact dates/locations and offer post-merge cleanup.
    let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if authStatus == .authorized || authStatus == .limited {
      loadedClips = resolvePhotoAssets(for: loadedClips)
    }

    return loadedClips
  }

  /// Removes temporary input video files copied for a Share Extension session.
  public nonisolated func cleanupTemporaryFiles(for clips: [ClipItem]) {
    var parentDirs: Set<URL> = []
    for clip in clips {
      parentDirs.insert(clip.fileURL.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: clip.fileURL)
    }
    for dir in parentDirs where dir.path.contains("ClipCombineInput") {
      try? FileManager.default.removeItem(at: dir)
    }
  }

  // MARK: - Merging and Saving

  /// Composes, transitions, optionally auto-trims, exports, and saves the ordered clips to Photos.
  public func mergeAndSave(
    clips: [ClipItem],
    configuration: MergeConfiguration,
    onPhaseChange: (@Sendable (MergePhase) -> Void)? = nil
  ) async throws -> MergeResult {
    guard clips.count >= 2 else {
      throw VideoMergeError.insufficientClips
    }

    onPhaseChange?(.preparing)

    // Ensure we have authorization to write to the Photo Library before spending time exporting.
    let authorized = await ensurePhotoLibraryWriteAccess()
    guard authorized else {
      throw VideoMergeError.photoLibraryAccessDenied
    }

    try Task.checkCancellation()

    // 1. Prepare temporary export destination inside the shared App Group container.
    let exportDir = AppSettings.sharedContainerURL
      .appendingPathComponent("ClipCombineExports", isDirectory: true)
    try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

    let outputURL = exportDir.appendingPathComponent("ClipCombine-\(UUID().uuidString).mov")
    defer {
      try? FileManager.default.removeItem(at: outputURL)
    }

    // 2. Build composition and export using highest quality with 1080p fallback.
    let outputDuration = try await mergeToFile(
      clips: clips,
      configuration: configuration,
      outputURL: outputURL,
      onPhaseChange: onPhaseChange
    )

    try Task.checkCancellation()

    // 3. Save merged video to Photo Library and attach first clip's metadata if enabled.
    onPhaseChange?(.saving)
    let firstClip = clips.first
    let savedID = try await saveVideoToPhotoLibrary(
      fileURL: outputURL,
      preserveMetadata: configuration.preserveMetadata,
      creationDate: firstClip?.creationDate,
      location: firstClip?.location
    )

    let sourceAssetIdentifiers = clips.compactMap(\.assetLocalIdentifier)

    return MergeResult(
      savedAssetIdentifier: savedID,
      outputDuration: outputDuration,
      sourceAssetIdentifiers: sourceAssetIdentifiers
    )
  }

  /// Composes, transitions, optionally auto-trims, and exports ordered clips directly to `outputURL`.
  /// Separated from Photo Library saving so the video processing pipeline can be verified end-to-end.
  func mergeToFile(
    clips: [ClipItem],
    configuration: MergeConfiguration,
    outputURL: URL,
    onPhaseChange: (@Sendable (MergePhase) -> Void)? = nil
  ) async throws -> TimeInterval {
    guard clips.count >= 2 else {
      throw VideoMergeError.insufficientClips
    }

    onPhaseChange?(.preparing)

    let prepared = try await buildComposition(clips: clips, configuration: configuration)

    try Task.checkCancellation()

    onPhaseChange?(.merging(0))
    try await exportComposition(
      prepared.composition,
      videoComposition: prepared.videoComposition,
      audioMix: prepared.audioMix,
      timeRange: prepared.exportTimeRange,
      to: outputURL,
      onProgress: { progress in
        onPhaseChange?(.merging(progress))
      }
    )

    return prepared.outputDuration
  }

  /// Prompts the user via PhotoKit to delete the individual source clips after a merge is saved.
  /// Returns `true` if deleted, or `false` if there were no matched assets or the user declined.
  public func deleteSourceAssets(localIdentifiers: [String]) async throws -> Bool {
    guard !localIdentifiers.isEmpty else { return false }

    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited else {
      return false
    }

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
    guard fetchResult.count > 0 else { return false }

    do {
      try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.deleteAssets(fetchResult)
      }
      return true
    } catch let error as PHPhotosError where error.code == .userCancelled {
      return false
    }
  }

  // MARK: - Orientation and Transform Normalization

  /// Computes an affine transform that applies `preferredTransform`, normalizes the origin
  /// back to `(0, 0)`, scales aspect-to-fit inside `renderSize`, and centers the video frame
  /// so mixed portrait and landscape clips never appear sideways, stretched, or cropped.
  public nonisolated static func normalizedTransform(
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform,
    renderSize: CGSize
  ) -> CGAffineTransform {
    let rawRect = CGRect(origin: .zero, size: naturalSize)
    let transformedRect = rawRect.applying(preferredTransform)
    let orientedWidth = abs(transformedRect.width)
    let orientedHeight = abs(transformedRect.height)

    guard orientedWidth > 0, orientedHeight > 0, renderSize.width > 0, renderSize.height > 0 else {
      return preferredTransform
    }

    let originFix = CGAffineTransform(
      translationX: -transformedRect.minX,
      y: -transformedRect.minY
    )

    let scale = min(renderSize.width / orientedWidth, renderSize.height / orientedHeight)
    let scaledWidth = orientedWidth * scale
    let scaledHeight = orientedHeight * scale

    let offsetX = (renderSize.width - scaledWidth) / 2.0
    let offsetY = (renderSize.height - scaledHeight) / 2.0

    return
      preferredTransform
      .concatenating(originFix)
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
  }

  // MARK: - Private Composition Builder

  private struct LoadedTrackInfo {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    let duration: CMTime
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let nominalFrameRate: Float
  }

  private struct PreparedComposition {
    let composition: AVMutableComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVMutableAudioMix?
    let exportTimeRange: CMTimeRange?
    let outputDuration: TimeInterval
  }

  private func buildComposition(
    clips: [ClipItem],
    configuration: MergeConfiguration
  ) async throws -> PreparedComposition {
    var trackInfos: [LoadedTrackInfo] = []
    trackInfos.reserveCapacity(clips.count)

    for clip in clips {
      try Task.checkCancellation()

      let asset = AVURLAsset(url: clip.fileURL)
      let videoTracks = try await asset.loadTracks(withMediaType: .video)
      guard let videoTrack = videoTracks.first else {
        throw VideoMergeError.unreadableVideo
      }

      let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
      let trackTimeRange = try await videoTrack.load(.timeRange)
      let assetDuration = try await asset.load(.duration)
      let naturalSize = try await videoTrack.load(.naturalSize)
      let preferredTransform = try await videoTrack.load(.preferredTransform)
      let frameRate = try await videoTrack.load(.nominalFrameRate)

      // Prefer the video track's valid duration when available to avoid trailing blank frames.
      let duration: CMTime
      if trackTimeRange.duration.isValid, trackTimeRange.duration.seconds > 0.05 {
        duration = CMTimeMinimum(trackTimeRange.duration, assetDuration)
      } else {
        duration = assetDuration
      }

      guard duration.isValid, duration.seconds > 0 else {
        throw VideoMergeError.unreadableVideo
      }

      trackInfos.append(
        LoadedTrackInfo(
          asset: asset,
          videoTrack: videoTrack,
          audioTrack: audioTrack,
          duration: duration,
          naturalSize: naturalSize,
          preferredTransform: preferredTransform,
          nominalFrameRate: frameRate
        )
      )
    }

    // Determine output canvas renderSize from the first clip's oriented dimensions.
    let renderSize = evenRenderSize(for: trackInfos[0])
    let frameDuration = bestFrameDuration(from: trackInfos)
    let transforms = trackInfos.map { info in
      Self.normalizedTransform(
        naturalSize: info.naturalSize,
        preferredTransform: info.preferredTransform,
        renderSize: renderSize
      )
    }

    let composition = AVMutableComposition()
    let blackColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    var videoInstructions: [AVVideoCompositionInstruction] = []
    var audioInputParameters: [AVMutableAudioMixInputParameters] = []

    if configuration.transitionStyle == .none {
      // Sequential single-lane append without overlap.
      guard
        let compVideoTrack = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
      else {
        throw VideoMergeError.compositionFailed("Unable to create video track.")
      }

      let hasAnyAudio = trackInfos.contains { $0.audioTrack != nil }
      let compAudioTrack: AVMutableCompositionTrack? =
        hasAnyAudio
        ? composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
        : nil

      var cursor = CMTime.zero

      for (index, info) in trackInfos.enumerated() {
        let sourceRange = CMTimeRange(start: .zero, duration: info.duration)
        try compVideoTrack.insertTimeRange(sourceRange, of: info.videoTrack, at: cursor)

        if let sourceAudio = info.audioTrack, let compAudioTrack {
          let audioTimeRange = try await clampedAudioRange(
            for: sourceAudio, maxDuration: info.duration)
          try? compAudioTrack.insertTimeRange(audioTimeRange, of: sourceAudio, at: cursor)
        }

        let layerInstruction = makeLayerInstruction(
          track: compVideoTrack,
          transform: transforms[index],
          at: cursor
        )
        let instruction = makeVideoInstruction(
          timeRange: CMTimeRange(start: cursor, duration: info.duration),
          backgroundColor: blackColor,
          layerInstructions: [layerInstruction]
        )
        videoInstructions.append(instruction)

        cursor = CMTimeAdd(cursor, info.duration)
      }

      if let compAudioTrack {
        let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
        audioInputParameters.append(params)
      }
    } else {
      // Dual A/B video and audio lanes for overlapping transitions.
      guard
        let videoTrackA = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let videoTrackB = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
      else {
        throw VideoMergeError.compositionFailed("Unable to create A/B video tracks.")
      }
      let videoTracks = [videoTrackA, videoTrackB]

      let hasAnyAudio = trackInfos.contains { $0.audioTrack != nil }
      var audioTracks: [AVMutableCompositionTrack] = []
      if hasAnyAudio,
        let audioTrackA = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let audioTrackB = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
      {
        audioTracks = [audioTrackA, audioTrackB]
        audioInputParameters = [
          AVMutableAudioMixInputParameters(track: audioTrackA),
          AVMutableAudioMixInputParameters(track: audioTrackB),
        ]
      }

      // Compute clamped per-boundary transition durations.
      var transitionDurations: [CMTime] = []
      transitionDurations.reserveCapacity(max(0, trackInfos.count - 1))
      for index in 0..<(trackInfos.count - 1) {
        let seconds = configuration.effectiveTransitionDuration(
          between: trackInfos[index].duration.seconds,
          and: trackInfos[index + 1].duration.seconds
        )
        transitionDurations.append(CMTime(seconds: seconds, preferredTimescale: 600))
      }

      // Compute timeline start/end for every clip.
      var clipStarts: [CMTime] = []
      var clipEnds: [CMTime] = []
      clipStarts.reserveCapacity(trackInfos.count)
      clipEnds.reserveCapacity(trackInfos.count)

      for index in 0..<trackInfos.count {
        let start: CMTime
        if index == 0 {
          start = .zero
        } else {
          start = CMTimeSubtract(clipEnds[index - 1], transitionDurations[index - 1])
        }
        let end = CMTimeAdd(start, trackInfos[index].duration)
        clipStarts.append(start)
        clipEnds.append(end)

        let lane = index % 2
        let sourceRange = CMTimeRange(start: .zero, duration: trackInfos[index].duration)
        try videoTracks[lane].insertTimeRange(
          sourceRange, of: trackInfos[index].videoTrack, at: start)

        if let sourceAudio = trackInfos[index].audioTrack, audioTracks.count == 2 {
          let audioRange = try await clampedAudioRange(
            for: sourceAudio,
            maxDuration: trackInfos[index].duration
          )
          try? audioTracks[lane].insertTimeRange(audioRange, of: sourceAudio, at: start)
        }
      }

      // Build contiguous pass-through and transition video instructions + audio crossfades.
      for index in 0..<trackInfos.count {
        let lane = index % 2
        let passStart = (index == 0) ? .zero : clipEnds[index - 1]
        let passEnd = (index == trackInfos.count - 1) ? clipEnds[index] : clipStarts[index + 1]

        if CMTimeCompare(passEnd, passStart) > 0 {
          let passRange = CMTimeRange(start: passStart, end: passEnd)
          let layer = makeLayerInstruction(
            track: videoTracks[lane],
            transform: transforms[index],
            at: passStart,
            opacity: 1.0
          )
          let instruction = makeVideoInstruction(
            timeRange: passRange,
            backgroundColor: blackColor,
            layerInstructions: [layer]
          )
          videoInstructions.append(instruction)
        }

        // Reset audio volume at the start of a clip if no incoming ramp handled it.
        if audioInputParameters.count == 2 {
          if index == 0 {
            audioInputParameters[0].setVolume(1.0, at: .zero)
          } else if CMTimeCompare(transitionDurations[index - 1], .zero) <= 0 {
            audioInputParameters[lane].setVolume(1.0, at: clipStarts[index])
          }
        }

        // Transition between clip `index` and clip `index + 1`.
        if index < trackInfos.count - 1 {
          let transDuration = transitionDurations[index]
          guard CMTimeCompare(transDuration, .zero) > 0 else { continue }

          let transRange = CMTimeRange(start: clipStarts[index + 1], duration: transDuration)
          let nextLane = (index + 1) % 2
          let fromTrack = videoTracks[lane]
          let toTrack = videoTracks[nextLane]
          let fromTransform = transforms[index]
          let toTransform = transforms[index + 1]

          switch configuration.transitionStyle {
          case .none:
            break

          case .crossDissolve:
            let fromLayer = makeLayerInstruction(
              track: fromTrack,
              transform: fromTransform,
              at: transRange.start,
              opacityRamp: (1.0, 0.0, transRange)
            )
            let toLayer = makeLayerInstruction(
              track: toTrack,
              transform: toTransform,
              at: transRange.start,
              opacityRamp: (0.0, 1.0, transRange)
            )
            let instruction = makeVideoInstruction(
              timeRange: transRange,
              backgroundColor: blackColor,
              layerInstructions: [fromLayer, toLayer]
            )
            videoInstructions.append(instruction)

          case .dipToBlack:
            let halfDuration = CMTimeMultiplyByFloat64(transDuration, multiplier: 0.5)
            let midTime = CMTimeAdd(transRange.start, halfDuration)
            let firstHalf = CMTimeRange(start: transRange.start, end: midTime)
            let secondHalf = CMTimeRange(start: midTime, end: transRange.end)

            if CMTimeCompare(firstHalf.duration, .zero) > 0 {
              let fromLayer = makeLayerInstruction(
                track: fromTrack,
                transform: fromTransform,
                at: firstHalf.start,
                opacityRamp: (1.0, 0.0, firstHalf)
              )
              let fadeOutInstruction = makeVideoInstruction(
                timeRange: firstHalf,
                backgroundColor: blackColor,
                layerInstructions: [fromLayer]
              )
              videoInstructions.append(fadeOutInstruction)
            }

            if CMTimeCompare(secondHalf.duration, .zero) > 0 {
              let toLayer = makeLayerInstruction(
                track: toTrack,
                transform: toTransform,
                at: secondHalf.start,
                opacityRamp: (0.0, 1.0, secondHalf)
              )
              let fadeInInstruction = makeVideoInstruction(
                timeRange: secondHalf,
                backgroundColor: blackColor,
                layerInstructions: [toLayer]
              )
              videoInstructions.append(fadeInInstruction)
            }

          case .slide:
            let fromEndTransform = fromTransform.concatenating(
              CGAffineTransform(translationX: -renderSize.width, y: 0)
            )
            let toStartTransform = toTransform.concatenating(
              CGAffineTransform(translationX: renderSize.width, y: 0)
            )

            let fromLayer = makeLayerInstruction(
              track: fromTrack,
              transformRamp: (fromTransform, fromEndTransform, transRange)
            )
            let toLayer = makeLayerInstruction(
              track: toTrack,
              transformRamp: (toStartTransform, toTransform, transRange)
            )
            let instruction = makeVideoInstruction(
              timeRange: transRange,
              backgroundColor: blackColor,
              layerInstructions: [toLayer, fromLayer]
            )
            videoInstructions.append(instruction)
          }

          // Audio crossfade across the transition window.
          if audioInputParameters.count == 2 {
            audioInputParameters[lane].setVolumeRamp(
              fromStartVolume: 1.0,
              toEndVolume: 0.0,
              timeRange: transRange
            )
            audioInputParameters[nextLane].setVolumeRamp(
              fromStartVolume: 0.0,
              toEndVolume: 1.0,
              timeRange: transRange
            )
          }
        }
      }
    }

    // Apply optional auto-trim to fixed intervals with a smooth 0.3s audio fade-out at the cut.
    let fullDuration = composition.duration
    var exportTimeRange: CMTimeRange?
    var finalOutputDuration = fullDuration.seconds
    var needsAudioMix = configuration.transitionStyle != .none && !audioInputParameters.isEmpty

    if configuration.autoTrimEnabled {
      let interval = configuration.autoTrimInterval.seconds
      if fullDuration.seconds >= interval {
        let targetSeconds = floor(fullDuration.seconds / interval) * interval
        if targetSeconds > 0, targetSeconds < fullDuration.seconds - 0.01 {
          let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
          exportTimeRange = CMTimeRange(start: .zero, duration: targetTime)
          finalOutputDuration = targetSeconds

          if !audioInputParameters.isEmpty {
            let fadeLength = min(Self.autoTrimFadeOutSeconds, targetSeconds)
            let fadeStart = CMTime(seconds: targetSeconds - fadeLength, preferredTimescale: 600)
            let fadeRange = CMTimeRange(start: fadeStart, end: targetTime)
            for params in audioInputParameters {
              params.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: fadeRange)
            }
            needsAudioMix = true
          }
        }
      }
    }

    let videoComposition = makeVideoComposition(
      renderSize: renderSize,
      frameDuration: frameDuration,
      instructions: videoInstructions
    )

    var audioMix: AVMutableAudioMix?
    if needsAudioMix {
      let mix = AVMutableAudioMix()
      mix.inputParameters = audioInputParameters
      audioMix = mix
    }

    return PreparedComposition(
      composition: composition,
      videoComposition: videoComposition,
      audioMix: audioMix,
      exportTimeRange: exportTimeRange,
      outputDuration: finalOutputDuration
    )
  }

  // MARK: - Exporting with Memory Safety

  private func exportComposition(
    _ composition: AVComposition,
    videoComposition: AVVideoComposition,
    audioMix: AVAudioMix?,
    timeRange: CMTimeRange?,
    to outputURL: URL,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let presets = [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080]
    var lastError: Error?

    for (attemptIndex, preset) in presets.enumerated() {
      try Task.checkCancellation()
      try? FileManager.default.removeItem(at: outputURL)

      guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
        lastError = VideoMergeError.exportFailed("Preset \(preset) unavailable.")
        continue
      }

      session.videoComposition = videoComposition
      session.audioMix = audioMix
      session.shouldOptimizeForNetworkUse = false
      if let timeRange {
        session.timeRange = timeRange
      }

      let progressTask = Task {
        for await state in session.states(updateInterval: 0.1) {
          if case .exporting(let progress) = state {
            onProgress(progress.fractionCompleted)
          }
        }
      }

      do {
        try await session.export(to: outputURL, as: .mov)
        progressTask.cancel()
        onProgress(1.0)
        return
      } catch is CancellationError {
        progressTask.cancel()
        throw VideoMergeError.cancelled
      } catch {
        progressTask.cancel()
        lastError = error
        // Retry with the lighter 1080p preset if the first high-quality attempt failed.
        if attemptIndex == presets.count - 1 {
          break
        }
      }
    }

    throw VideoMergeError.exportFailed(lastError?.localizedDescription ?? "Unknown export error.")
  }

  // MARK: - PhotoKit Saving and Metadata Matching

  private func ensurePhotoLibraryWriteAccess() async -> Bool {
    let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch current {
    case .authorized, .limited:
      return true
    case .notDetermined:
      let updated = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
      return updated == .authorized || updated == .limited
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  private func saveVideoToPhotoLibrary(
    fileURL: URL,
    preserveMetadata: Bool,
    creationDate: Date?,
    location: CLLocation?
  ) async throws -> String? {
    final class IdentifierBox: @unchecked Sendable {
      var value: String?
    }
    let identifierBox = IdentifierBox()

    try await PHPhotoLibrary.shared().performChanges {
      let creationRequest = PHAssetCreationRequest.forAsset()
      let resourceOptions = PHAssetResourceCreationOptions()
      resourceOptions.shouldMoveFile = false
      creationRequest.addResource(with: .video, fileURL: fileURL, options: resourceOptions)

      if preserveMetadata {
        if let creationDate {
          creationRequest.creationDate = creationDate
        }
        if let location {
          creationRequest.location = location
        }
      }

      identifierBox.value = creationRequest.placeholderForCreatedAsset?.localIdentifier
    }

    return identifierBox.value
  }

  /// Matches shared video files back to their `PHAsset`s in the Photo Library using capture timestamp,
  /// duration, pixel dimensions, and original filename when available.
  private func resolvePhotoAssets(for clips: [ClipItem]) -> [ClipItem] {
    guard !clips.isEmpty else { return clips }

    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    // Scope the PhotoKit query around the clips' capture dates when all clips have timestamps
    // so lookup remains instantaneous even on huge libraries.
    let clipDates = clips.compactMap(\.creationDate)
    if clipDates.count == clips.count, let minDate = clipDates.min(), let maxDate = clipDates.max()
    {
      let startBound = minDate.addingTimeInterval(-30) as NSDate
      let endBound = maxDate.addingTimeInterval(30) as NSDate
      fetchOptions.predicate = NSPredicate(
        format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
        PHAssetMediaType.video.rawValue,
        startBound,
        endBound
      )
    } else {
      fetchOptions.fetchLimit = 250
      fetchOptions.predicate = NSPredicate(
        format: "mediaType == %d", PHAssetMediaType.video.rawValue)
    }

    let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
    guard fetchResult.count > 0 else { return clips }

    var candidateAssets: [PHAsset] = []
    candidateAssets.reserveCapacity(fetchResult.count)
    fetchResult.enumerateObjects { asset, _, _ in
      candidateAssets.append(asset)
    }

    var claimedIdentifiers: Set<String> = []

    return clips.map { clip in
      if let existingID = clip.assetLocalIdentifier {
        claimedIdentifiers.insert(existingID)
        return clip
      }

      guard
        let matched = bestMatchingAsset(
          for: clip,
          candidates: candidateAssets,
          excluding: claimedIdentifiers
        )
      else {
        return clip
      }

      claimedIdentifiers.insert(matched.localIdentifier)

      return ClipItem(
        id: clip.id,
        fileURL: clip.fileURL,
        assetLocalIdentifier: matched.localIdentifier,
        duration: clip.duration,
        thumbnail: clip.thumbnail,
        naturalSize: clip.naturalSize,
        preferredTransform: clip.preferredTransform,
        creationDate: matched.creationDate ?? clip.creationDate,
        location: matched.location ?? clip.location,
        filename: clip.filename
      )
    }
  }

  private func bestMatchingAsset(
    for clip: ClipItem,
    candidates: [PHAsset],
    excluding claimed: Set<String>
  ) -> PHAsset? {
    let clipBaseName = clip.filename.map {
      URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased()
    }
    let oriented = clip.orientedSize

    var bestAsset: PHAsset?
    var bestScore = 0

    for asset in candidates where !claimed.contains(asset.localIdentifier) {
      let durationDelta = abs(asset.duration - clip.duration)
      guard durationDelta <= 0.6 else { continue }

      var score = 0

      // Strongest signal: matching creation timestamp within 3 seconds.
      if let clipDate = clip.creationDate, let assetDate = asset.creationDate {
        let dateDelta = abs(assetDate.timeIntervalSince(clipDate))
        if dateDelta <= 2.0 {
          score += 60
        } else if dateDelta <= 10.0 {
          score += 20
        } else {
          continue
        }
      }

      // Duration closeness bonus.
      if durationDelta <= 0.15 {
        score += 25
      } else if durationDelta <= 0.35 {
        score += 15
      } else {
        score += 5
      }

      // Pixel dimension match (accounting for orientation swap).
      let matchesDims =
        (abs(CGFloat(asset.pixelWidth) - oriented.width) <= 2
          && abs(CGFloat(asset.pixelHeight) - oriented.height) <= 2)
        || (abs(CGFloat(asset.pixelWidth) - oriented.height) <= 2
          && abs(CGFloat(asset.pixelHeight) - oriented.width) <= 2)
      if matchesDims {
        score += 15
      }

      // Filename match when provided by the Share Sheet.
      if let clipBaseName, !clipBaseName.isEmpty {
        let resources = PHAssetResource.assetResources(for: asset)
        let hasNameMatch = resources.contains { resource in
          let rawName: String?
          if #available(iOS 27, *) {
            rawName = resource.filename
          } else {
            rawName = resource.originalFilename
          }
          guard let rawName, !rawName.isEmpty else { return false }
          let candidateName = URL(fileURLWithPath: rawName)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
          return candidateName == clipBaseName
        }
        if hasNameMatch {
          score += 50
        }
      }

      if score > bestScore {
        bestScore = score
        bestAsset = asset
      }
    }

    // Require a reasonable confidence threshold to avoid mis-matching unrelated clips.
    return bestScore >= 40 ? bestAsset : nil
  }

  // MARK: - NSItemProvider Extraction Helpers

  private func extractMovieProviders(from extensionItems: [NSExtensionItem]) -> [NSItemProvider] {
    var providers: [NSItemProvider] = []
    for item in extensionItems {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
          || provider.hasItemConformingToTypeIdentifier(UTType.video.identifier)
        {
          providers.append(provider)
        }
      }
    }
    return providers
  }

  private func loadSingleClip(
    from provider: NSItemProvider,
    index: Int,
    destinationDirectory: URL
  ) async throws -> ClipItem? {
    let typeIdentifier =
      provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      ? UTType.movie.identifier
      : UTType.video.identifier

    let copiedURL = try await copyFileRepresentation(
      from: provider,
      typeIdentifier: typeIdentifier,
      index: index,
      destinationDirectory: destinationDirectory
    )

    let asset = AVURLAsset(url: copiedURL)
    let duration = try await asset.load(.duration)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
      try? FileManager.default.removeItem(at: copiedURL)
      return nil
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let preferredTransform = try await videoTrack.load(.preferredTransform)
    let creationDate = try? await asset.load(.creationDate)?.load(.dateValue)
    let location = await extractLocation(from: asset)
    let thumbnail = await generateThumbnail(for: asset)

    return ClipItem(
      fileURL: copiedURL,
      assetLocalIdentifier: nil,
      duration: max(0, duration.seconds),
      thumbnail: thumbnail,
      naturalSize: naturalSize,
      preferredTransform: preferredTransform,
      creationDate: creationDate,
      location: location,
      filename: provider.suggestedName ?? copiedURL.lastPathComponent
    )
  }

  private func copyFileRepresentation(
    from provider: NSItemProvider,
    typeIdentifier: String,
    index: Int,
    destinationDirectory: URL
  ) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let sourceURL else {
          continuation.resume(throwing: VideoMergeError.unreadableVideo)
          return
        }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL =
          destinationDirectory
          .appendingPathComponent(String(format: "%02d_%@.%@", index, baseName, fileExtension))

        do {
          if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
          }
          try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
          continuation.resume(returning: destinationURL)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func generateThumbnail(for asset: AVURLAsset) async -> UIImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = Self.thumbnailMaxSize
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

    guard let result = try? await generator.image(at: .zero) else {
      return nil
    }
    return UIImage(cgImage: result.image)
  }

  private func extractLocation(from asset: AVURLAsset) async -> CLLocation? {
    guard let metadata = try? await asset.load(.commonMetadata) else {
      return nil
    }
    let locationItems = AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierLocation
    )
    guard let isoString = try? await locationItems.first?.load(.stringValue) else {
      return nil
    }
    return Self.parseISO6709Location(isoString)
  }

  /// Parses QuickTime ISO 6709 GPS coordinates such as `+37.7749-122.4194+015.000/`.
  nonisolated static func parseISO6709Location(_ isoString: String) -> CLLocation? {
    let trimmed = isoString.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
    let pattern = #"([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: trimmed,
        range: NSRange(trimmed.startIndex..., in: trimmed)
      ),
      let latRange = Range(match.range(at: 1), in: trimmed),
      let lonRange = Range(match.range(at: 2), in: trimmed),
      let latitude = Double(trimmed[latRange]),
      let longitude = Double(trimmed[lonRange])
    else {
      return nil
    }

    if match.range(at: 3).location != NSNotFound,
      let altRange = Range(match.range(at: 3), in: trimmed),
      let altitude = Double(trimmed[altRange])
    {
      return CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: altitude,
        horizontalAccuracy: kCLLocationAccuracyBest,
        verticalAccuracy: kCLLocationAccuracyBest,
        timestamp: Date()
      )
    }

    return CLLocation(latitude: latitude, longitude: longitude)
  }

  // MARK: - Composition Utility Helpers

  private func evenRenderSize(for firstTrack: LoadedTrackInfo) -> CGSize {
    let transformed = CGRect(origin: .zero, size: firstTrack.naturalSize)
      .applying(firstTrack.preferredTransform)
    let rawWidth = abs(transformed.width)
    let rawHeight = abs(transformed.height)

    guard rawWidth >= 2, rawHeight >= 2 else {
      return CGSize(width: 1080, height: 1920)
    }

    // Video encoders require even pixel dimensions.
    let evenWidth = max(2, Int(rawWidth.rounded()) & ~1)
    let evenHeight = max(2, Int(rawHeight.rounded()) & ~1)
    return CGSize(width: evenWidth, height: evenHeight)
  }

  private func bestFrameDuration(from tracks: [LoadedTrackInfo]) -> CMTime {
    let maxFPS = tracks.map(\.nominalFrameRate).max() ?? 30
    let clampedFPS: Int32
    if maxFPS >= 55 {
      clampedFPS = 60
    } else if maxFPS >= 28 {
      clampedFPS = 30
    } else if maxFPS >= 22 {
      clampedFPS = 24
    } else {
      clampedFPS = 30
    }
    return CMTime(value: 1, timescale: clampedFPS)
  }

  private func clampedAudioRange(
    for audioTrack: AVAssetTrack,
    maxDuration: CMTime
  ) async throws -> CMTimeRange {
    let trackRange = try await audioTrack.load(.timeRange)
    let effectiveDuration = CMTimeMinimum(trackRange.duration, maxDuration)
    return CMTimeRange(start: .zero, duration: effectiveDuration)
  }

  // MARK: - iOS 26+ Configuration / iOS 18+ Fallback Builders

  private func makeLayerInstruction(
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

  private func makeVideoInstruction(
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

  private func makeVideoComposition(
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
