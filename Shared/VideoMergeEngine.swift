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
      "Photo Library access is needed to save your merged video. Enable access in the Montage app or Settings."
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

  private let assetExporter = VideoAssetExporter.shared
  private let thumbnailGenerator = VideoThumbnailGenerator.shared
  private let compositionBuilder = VideoCompositionBuilder.shared
  private let resourceCompatibility = PhotoAssetResourceCompatibility.shared

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
      .appendingPathComponent("MontageInput", isDirectory: true)
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
    if PHPhotoLibrary.authorizationStatus(for: .readWrite).allowsPhotoAccess {
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

    for dir in parentDirs where dir.path.contains("MontageInput") {
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
      .appendingPathComponent("MontageExports", isDirectory: true)
    try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

    let outputURL = exportDir.appendingPathComponent("Montage-\(UUID().uuidString).mov")
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
    guard !localIdentifiers.isEmpty else {
      return false
    }

    guard PHPhotoLibrary.authorizationStatus(for: .readWrite).allowsPhotoAccess else {
      return false
    }

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
    guard fetchResult.count > 0 else {
      return false
    }

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
    let trackInfos = try await loadTrackInfos(for: clips)

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

    let (videoInstructions, audioInputParameters):
      (
        [AVVideoCompositionInstruction], [AVMutableAudioMixInputParameters]
      ) =
        if configuration.transitionStyle == .none {
          try await buildSequentialTracks(
            in: composition,
            trackInfos: trackInfos,
            transforms: transforms,
            blackColor: blackColor
          )
        } else {
          try await buildTransitionTracks(
            in: composition,
            trackInfos: trackInfos,
            transforms: transforms,
            renderSize: renderSize,
            blackColor: blackColor,
            configuration: configuration
          )
        }

    // Apply optional auto-trim to fixed intervals with a smooth 0.3s audio fade-out at the cut.
    let trimResult = applyAutoTrim(
      fullDuration: composition.duration,
      configuration: configuration,
      audioInputParameters: audioInputParameters
    )
    let needsAudioMix =
      (configuration.transitionStyle != .none && !audioInputParameters.isEmpty)
      || trimResult.appliedAudioFade

    let videoComposition = compositionBuilder.makeVideoComposition(
      renderSize: renderSize,
      frameDuration: frameDuration,
      instructions: videoInstructions
    )

    let audioMix: AVMutableAudioMix?
    if needsAudioMix {
      let mix = AVMutableAudioMix()
      mix.inputParameters = audioInputParameters
      audioMix = mix
    } else {
      audioMix = nil
    }

    return PreparedComposition(
      composition: composition,
      videoComposition: videoComposition,
      audioMix: audioMix,
      exportTimeRange: trimResult.exportTimeRange,
      outputDuration: trimResult.outputDuration
    )
  }

  private func loadTrackInfos(for clips: [ClipItem]) async throws -> [LoadedTrackInfo] {
    var trackInfos: [LoadedTrackInfo] = []
    trackInfos.reserveCapacity(clips.count)

    for clip in clips {
      try Task.checkCancellation()

      let asset = AVURLAsset(url: clip.fileURL)
      guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
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

    return trackInfos
  }

  private func addTracks(
    to composition: AVMutableComposition,
    mediaType: AVMediaType,
    count: Int
  ) -> [AVMutableCompositionTrack] {
    var tracks: [AVMutableCompositionTrack] = []
    tracks.reserveCapacity(count)
    for _ in 0..<count {
      guard
        let track = composition.addMutableTrack(
          withMediaType: mediaType,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
      else {
        return []
      }

      tracks.append(track)
    }

    return tracks
  }

  private func insertClampedAudio(
    from sourceAudio: AVAssetTrack?,
    maxDuration: CMTime,
    into destinationTrack: AVMutableCompositionTrack?,
    at time: CMTime
  ) async throws {
    guard let sourceAudio, let destinationTrack else {
      return
    }

    let audioRange = try await clampedAudioRange(for: sourceAudio, maxDuration: maxDuration)
    try? destinationTrack.insertTimeRange(audioRange, of: sourceAudio, at: time)
  }

  private func buildSequentialTracks(
    in composition: AVMutableComposition,
    trackInfos: [LoadedTrackInfo],
    transforms: [CGAffineTransform],
    blackColor: CGColor
  ) async throws -> ([AVVideoCompositionInstruction], [AVMutableAudioMixInputParameters]) {
    guard let compVideoTrack = addTracks(to: composition, mediaType: .video, count: 1).first else {
      throw VideoMergeError.compositionFailed("Unable to create video track.")
    }

    let hasAnyAudio = trackInfos.contains { $0.audioTrack != nil }
    let compAudioTrack: AVMutableCompositionTrack?
    if hasAnyAudio {
      compAudioTrack = addTracks(to: composition, mediaType: .audio, count: 1).first
    } else {
      compAudioTrack = nil
    }

    var videoInstructions: [AVVideoCompositionInstruction] = []
    videoInstructions.reserveCapacity(trackInfos.count)
    var cursor = CMTime.zero

    for (index, info) in trackInfos.enumerated() {
      let sourceRange = CMTimeRange(start: .zero, duration: info.duration)
      try compVideoTrack.insertTimeRange(sourceRange, of: info.videoTrack, at: cursor)
      try await insertClampedAudio(
        from: info.audioTrack,
        maxDuration: info.duration,
        into: compAudioTrack,
        at: cursor
      )

      let layerInstruction = compositionBuilder.makeLayerInstruction(
        track: compVideoTrack,
        transform: transforms[index],
        at: cursor
      )
      videoInstructions.append(
        compositionBuilder.makeVideoInstruction(
          timeRange: CMTimeRange(start: cursor, duration: info.duration),
          backgroundColor: blackColor,
          layerInstructions: [layerInstruction]
        )
      )

      cursor = CMTimeAdd(cursor, info.duration)
    }

    let audioInputParameters =
      compAudioTrack.map { [AVMutableAudioMixInputParameters(track: $0)] } ?? []
    return (videoInstructions, audioInputParameters)
  }

  private func buildTransitionTracks(
    in composition: AVMutableComposition,
    trackInfos: [LoadedTrackInfo],
    transforms: [CGAffineTransform],
    renderSize: CGSize,
    blackColor: CGColor,
    configuration: MergeConfiguration
  ) async throws -> ([AVVideoCompositionInstruction], [AVMutableAudioMixInputParameters]) {
    let videoTracks = addTracks(to: composition, mediaType: .video, count: 2)
    guard videoTracks.count == 2 else {
      throw VideoMergeError.compositionFailed("Unable to create A/B video tracks.")
    }

    let hasAnyAudio = trackInfos.contains { $0.audioTrack != nil }
    let audioTracks: [AVMutableCompositionTrack]
    if hasAnyAudio {
      audioTracks = addTracks(to: composition, mediaType: .audio, count: 2)
    } else {
      audioTracks = []
    }

    let audioInputParameters = audioTracks.map(AVMutableAudioMixInputParameters.init(track:))

    // Compute clamped per-boundary transition durations.
    let transitionDurations: [CMTime] = (0..<max(0, trackInfos.count - 1)).map { index in
      let seconds = configuration.effectiveTransitionDuration(
        between: trackInfos[index].duration.seconds,
        and: trackInfos[index + 1].duration.seconds
      )
      return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // Compute timeline start/end for every clip and insert onto alternating A/B lanes.
    var clipStarts: [CMTime] = []
    var clipEnds: [CMTime] = []
    clipStarts.reserveCapacity(trackInfos.count)
    clipEnds.reserveCapacity(trackInfos.count)

    for (index, info) in trackInfos.enumerated() {
      let start: CMTime
      if index == 0 {
        start = .zero
      } else {
        start = CMTimeSubtract(clipEnds[index - 1], transitionDurations[index - 1])
      }

      let end = CMTimeAdd(start, info.duration)
      clipStarts.append(start)
      clipEnds.append(end)

      let lane = index % 2
      let sourceRange = CMTimeRange(start: .zero, duration: info.duration)
      try videoTracks[lane].insertTimeRange(sourceRange, of: info.videoTrack, at: start)

      let destinationAudioTrack: AVMutableCompositionTrack?
      if audioTracks.count == 2 {
        destinationAudioTrack = audioTracks[lane]
      } else {
        destinationAudioTrack = nil
      }

      try await insertClampedAudio(
        from: info.audioTrack,
        maxDuration: info.duration,
        into: destinationAudioTrack,
        at: start
      )
    }

    // Build contiguous pass-through and transition video instructions + audio crossfades.
    var videoInstructions: [AVVideoCompositionInstruction] = []
    for index in 0..<trackInfos.count {
      let lane = index % 2
      let passStart: CMTime
      if index == 0 {
        passStart = .zero
      } else {
        passStart = clipEnds[index - 1]
      }

      let passEnd: CMTime
      if index == trackInfos.count - 1 {
        passEnd = clipEnds[index]
      } else {
        passEnd = clipStarts[index + 1]
      }

      if CMTimeCompare(passEnd, passStart) > 0 {
        let passRange = CMTimeRange(start: passStart, end: passEnd)
        let layer = compositionBuilder.makeLayerInstruction(
          track: videoTracks[lane],
          transform: transforms[index],
          at: passStart,
          opacity: 1.0
        )
        videoInstructions.append(
          compositionBuilder.makeVideoInstruction(
            timeRange: passRange,
            backgroundColor: blackColor,
            layerInstructions: [layer]
          )
        )
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
      guard index < trackInfos.count - 1 else {
        continue
      }

      let transDuration = transitionDurations[index]
      guard CMTimeCompare(transDuration, .zero) > 0 else {
        continue
      }

      let transRange = CMTimeRange(start: clipStarts[index + 1], duration: transDuration)
      let nextLane = (index + 1) % 2
      videoInstructions.append(
        contentsOf: makeTransitionInstructions(
          style: configuration.transitionStyle,
          fromTrack: videoTracks[lane],
          toTrack: videoTracks[nextLane],
          fromTransform: transforms[index],
          toTransform: transforms[index + 1],
          renderSize: renderSize,
          timeRange: transRange,
          blackColor: blackColor
        )
      )

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

    return (videoInstructions, audioInputParameters)
  }

  private func makeTransitionInstructions(
    style: TransitionStyle,
    fromTrack: AVMutableCompositionTrack,
    toTrack: AVMutableCompositionTrack,
    fromTransform: CGAffineTransform,
    toTransform: CGAffineTransform,
    renderSize: CGSize,
    timeRange: CMTimeRange,
    blackColor: CGColor
  ) -> [AVVideoCompositionInstruction] {
    switch style {
    case .none:
      return []

    case .crossDissolve:
      let fromLayer = compositionBuilder.makeLayerInstruction(
        track: fromTrack,
        transform: fromTransform,
        at: timeRange.start,
        opacityRamp: (1.0, 0.0, timeRange)
      )
      let toLayer = compositionBuilder.makeLayerInstruction(
        track: toTrack,
        transform: toTransform,
        at: timeRange.start,
        opacityRamp: (0.0, 1.0, timeRange)
      )
      return [
        compositionBuilder.makeVideoInstruction(
          timeRange: timeRange,
          backgroundColor: blackColor,
          layerInstructions: [fromLayer, toLayer]
        )
      ]

    case .dipToBlack:
      let halfDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 0.5)
      let midTime = CMTimeAdd(timeRange.start, halfDuration)
      let halves: [(AVMutableCompositionTrack, CGAffineTransform, Float, Float, CMTimeRange)] = [
        (fromTrack, fromTransform, 1.0, 0.0, CMTimeRange(start: timeRange.start, end: midTime)),
        (toTrack, toTransform, 0.0, 1.0, CMTimeRange(start: midTime, end: timeRange.end)),
      ]
      return halves.compactMap { track, transform, startOpacity, endOpacity, range in
        guard CMTimeCompare(range.duration, .zero) > 0 else {
          return nil
        }

        let layer = compositionBuilder.makeLayerInstruction(
          track: track,
          transform: transform,
          at: range.start,
          opacityRamp: (startOpacity, endOpacity, range)
        )
        return compositionBuilder.makeVideoInstruction(
          timeRange: range,
          backgroundColor: blackColor,
          layerInstructions: [layer]
        )
      }

    case .slide:
      let fromEndTransform = fromTransform.concatenating(
        CGAffineTransform(translationX: -renderSize.width, y: 0)
      )
      let toStartTransform = toTransform.concatenating(
        CGAffineTransform(translationX: renderSize.width, y: 0)
      )
      let fromLayer = compositionBuilder.makeLayerInstruction(
        track: fromTrack,
        transformRamp: (fromTransform, fromEndTransform, timeRange)
      )
      let toLayer = compositionBuilder.makeLayerInstruction(
        track: toTrack,
        transformRamp: (toStartTransform, toTransform, timeRange)
      )
      return [
        compositionBuilder.makeVideoInstruction(
          timeRange: timeRange,
          backgroundColor: blackColor,
          layerInstructions: [toLayer, fromLayer]
        )
      ]
    }
  }

  private func applyAutoTrim(
    fullDuration: CMTime,
    configuration: MergeConfiguration,
    audioInputParameters: [AVMutableAudioMixInputParameters]
  ) -> (exportTimeRange: CMTimeRange?, outputDuration: TimeInterval, appliedAudioFade: Bool) {
    guard
      let targetSeconds = configuration.trimmedDuration(for: fullDuration.seconds),
      targetSeconds > 0,
      targetSeconds < fullDuration.seconds - 0.01
    else {
      return (nil, fullDuration.seconds, false)
    }

    let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
    let exportTimeRange = CMTimeRange(start: .zero, duration: targetTime)
    var appliedAudioFade = false

    if !audioInputParameters.isEmpty {
      let fadeLength = min(Self.autoTrimFadeOutSeconds, targetSeconds)
      let fadeStart = CMTime(seconds: targetSeconds - fadeLength, preferredTimescale: 600)
      let fadeRange = CMTimeRange(start: fadeStart, end: targetTime)
      for params in audioInputParameters {
        params.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: fadeRange)
      }

      appliedAudioFade = true
    }

    return (exportTimeRange, targetSeconds, appliedAudioFade)
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

      do {
        try await assetExporter.export(
          composition: composition,
          presetName: preset,
          videoComposition: videoComposition,
          audioMix: audioMix,
          timeRange: timeRange,
          outputURL: outputURL,
          fileType: .mov,
          onProgress: onProgress
        )
        return
      } catch is CancellationError {
        throw VideoMergeError.cancelled
      } catch {
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
    if current.allowsPhotoAccess {
      return true
    }

    guard current == .notDetermined else {
      return false
    }

    return await PHPhotoLibrary.requestAuthorization(for: .readWrite).allowsPhotoAccess
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
    guard !clips.isEmpty else {
      return clips
    }

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
    guard fetchResult.count > 0 else {
      return clips
    }

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
      guard durationDelta <= 0.6 else {
        continue
      }

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
          guard let rawName = resourceCompatibility.filename(for: resource), !rawName.isEmpty else {
            return false
          }

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
    if bestScore >= 40 {
      return bestAsset
    } else {
      return nil
    }
  }

  // MARK: - NSItemProvider Extraction Helpers

  private func extractMovieProviders(from extensionItems: [NSExtensionItem]) -> [NSItemProvider] {
    var providers: [NSItemProvider] = []
    for item in extensionItems {
      guard let attachments = item.attachments else {
        continue
      }

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
    let typeIdentifier: String
    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      typeIdentifier = UTType.movie.identifier
    } else {
      typeIdentifier = UTType.video.identifier
    }

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

        let fileExtension: String
        if sourceURL.pathExtension.isEmpty {
          fileExtension = "mov"
        } else {
          fileExtension = sourceURL.pathExtension
        }

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
    await thumbnailGenerator.generateThumbnail(
      for: asset,
      at: .zero,
      maximumSize: Self.thumbnailMaxSize
    )
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
    let oriented = ClipItem.orientedSize(
      naturalSize: firstTrack.naturalSize,
      preferredTransform: firstTrack.preferredTransform
    )

    guard oriented.width >= 2, oriented.height >= 2 else {
      return CGSize(width: 1080, height: 1920)
    }

    // Video encoders require even pixel dimensions.
    let evenWidth = max(2, Int(oriented.width.rounded()) & ~1)
    let evenHeight = max(2, Int(oriented.height.rounded()) & ~1)
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
}

extension PHAuthorizationStatus {
  fileprivate nonisolated var allowsPhotoAccess: Bool {
    return self == .authorized || self == .limited
  }
}
