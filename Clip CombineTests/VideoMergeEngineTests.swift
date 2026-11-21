import AVFoundation
import CoreGraphics
import CoreLocation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Clip_Combine

@Suite("VideoMergeEngine")
struct VideoMergeEngineTests {

  private func makeTempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ClipCombineEngineTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func makeClipItem(
    from url: URL,
    duration: TimeInterval,
    size: CGSize = CGSize(width: 160, height: 90),
    transform: CGAffineTransform = .identity
  ) -> ClipItem {
    ClipItem(
      fileURL: url,
      duration: duration,
      naturalSize: size,
      preferredTransform: transform
    )
  }

  // MARK: - Transform Normalization

  @Test("normalizedTransform preserves matching landscape dimensions exactly")
  func normalizedTransformMatchingLandscape() {
    let natural = CGSize(width: 1920, height: 1080)
    let render = CGSize(width: 1920, height: 1080)
    let transform = VideoMergeEngine.normalizedTransform(
      naturalSize: natural,
      preferredTransform: .identity,
      renderSize: render
    )

    let resultRect = CGRect(origin: .zero, size: natural).applying(transform)
    #expect(abs(resultRect.minX) < 0.5)
    #expect(abs(resultRect.minY) < 0.5)
    #expect(abs(resultRect.width - 1920) < 0.5)
    #expect(abs(resultRect.height - 1080) < 0.5)
  }

  @Test("normalizedTransform normalizes 90-degree rotated iPhone portrait video onto portrait canvas")
  func normalizedTransformPortraitRotation() {
    let natural = CGSize(width: 1920, height: 1080)
    let preferred = CGAffineTransform(rotationAngle: .pi / 2)
    let render = CGSize(width: 1080, height: 1920)

    let transform = VideoMergeEngine.normalizedTransform(
      naturalSize: natural,
      preferredTransform: preferred,
      renderSize: render
    )

    let resultRect = CGRect(origin: .zero, size: natural).applying(transform)
    #expect(abs(resultRect.minX) < 0.5)
    #expect(abs(resultRect.minY) < 0.5)
    #expect(abs(resultRect.width - 1080) < 0.5)
    #expect(abs(resultRect.height - 1920) < 0.5)
  }

  @Test("normalizedTransform letterboxes landscape clip centered inside portrait canvas")
  func normalizedTransformLandscapeInsidePortrait() {
    let natural = CGSize(width: 1920, height: 1080)
    let render = CGSize(width: 1080, height: 1920)

    let transform = VideoMergeEngine.normalizedTransform(
      naturalSize: natural,
      preferredTransform: .identity,
      renderSize: render
    )

    let resultRect = CGRect(origin: .zero, size: natural).applying(transform)
    let expectedHeight = 1080.0 * (1080.0 / 1920.0)  // 607.5
    let expectedMinY = (1920.0 - expectedHeight) / 2.0  // 656.25

    #expect(abs(resultRect.minX) < 0.5)
    #expect(abs(resultRect.minY - expectedMinY) < 0.5)
    #expect(abs(resultRect.width - 1080) < 0.5)
    #expect(abs(resultRect.height - expectedHeight) < 0.5)
  }

  @Test("normalizedTransform pillarboxes portrait clip centered inside landscape canvas")
  func normalizedTransformPortraitInsideLandscape() {
    let natural = CGSize(width: 1080, height: 1920)
    let render = CGSize(width: 1920, height: 1080)

    let transform = VideoMergeEngine.normalizedTransform(
      naturalSize: natural,
      preferredTransform: .identity,
      renderSize: render
    )

    let resultRect = CGRect(origin: .zero, size: natural).applying(transform)
    let expectedWidth = 1080.0 * (1080.0 / 1920.0)  // 607.5
    let expectedMinX = (1920.0 - expectedWidth) / 2.0  // 656.25

    #expect(abs(resultRect.minX - expectedMinX) < 0.5)
    #expect(abs(resultRect.minY) < 0.5)
    #expect(abs(resultRect.width - expectedWidth) < 0.5)
    #expect(abs(resultRect.height - 1080) < 0.5)
  }

  @Test("normalizedTransform handles 180-degree rotation and zero-size inputs safely")
  func normalizedTransform180AndZeroSize() {
    let natural = CGSize(width: 1280, height: 720)
    let render = CGSize(width: 1280, height: 720)
    let rotated = VideoMergeEngine.normalizedTransform(
      naturalSize: natural,
      preferredTransform: CGAffineTransform(rotationAngle: .pi),
      renderSize: render
    )
    let rect = CGRect(origin: .zero, size: natural).applying(rotated)
    #expect(abs(rect.minX) < 0.5)
    #expect(abs(rect.minY) < 0.5)
    #expect(abs(rect.width - 1280) < 0.5)
    #expect(abs(rect.height - 720) < 0.5)

    let zeroTransform = VideoMergeEngine.normalizedTransform(
      naturalSize: .zero,
      preferredTransform: .identity,
      renderSize: render
    )
    #expect(zeroTransform == .identity)
  }

  // MARK: - ISO 6709 GPS Location Parsing

  @Test("parseISO6709Location parses coordinates with and without altitude")
  func parseISO6709ValidCoordinates() throws {
    let withAltitude = try #require(
      VideoMergeEngine.parseISO6709Location("+37.7749-122.4194+015.500/")
    )
    #expect(abs(withAltitude.coordinate.latitude - 37.7749) < 0.0001)
    #expect(abs(withAltitude.coordinate.longitude - (-122.4194)) < 0.0001)
    #expect(abs(withAltitude.altitude - 15.5) < 0.01)

    let withoutAltitude = try #require(
      VideoMergeEngine.parseISO6709Location("-33.8688+151.2093/")
    )
    #expect(abs(withoutAltitude.coordinate.latitude - (-33.8688)) < 0.0001)
    #expect(abs(withoutAltitude.coordinate.longitude - 151.2093) < 0.0001)

    let withWhitespace = try #require(
      VideoMergeEngine.parseISO6709Location("  +40.7128-074.0060/ \n")
    )
    #expect(abs(withWhitespace.coordinate.latitude - 40.7128) < 0.0001)
    #expect(abs(withWhitespace.coordinate.longitude - (-74.0060)) < 0.0001)
  }

  @Test(
    "parseISO6709Location returns nil for invalid strings",
    arguments: ["", "invalid", "+37.7749", "37.7749, -122.4194"]
  )
  func parseISO6709InvalidStrings(input: String) {
    #expect(VideoMergeEngine.parseISO6709Location(input) == nil)
  }

  // MARK: - End-to-End Video Merging

  @Test("Instant cut merges two clips with audio into a single valid movie")
  func mergeInstantCutWithAudio() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let url1 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "clip1.mov", size: CGSize(width: 160, height: 90),
      duration: 2.0, color: .red, includeAudio: true
    )
    let url2 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "clip2.mov", size: CGSize(width: 160, height: 90),
      duration: 2.0, color: .blue, includeAudio: true
    )

    let engine = VideoMergeEngine()
    let clips = [makeClipItem(from: url1, duration: 2.0), makeClipItem(from: url2, duration: 2.0)]
    let config = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )

    let outputURL = dir.appendingPathComponent("merged_none.mov")
    let phaseRecorder = PhaseRecorder()

    let reportedDuration = try await engine.mergeToFile(
      clips: clips,
      configuration: config,
      outputURL: outputURL,
      onPhaseChange: { phase in
        phaseRecorder.record(phase)
      }
    )

    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect(abs(reportedDuration - 4.0) < 0.25)

    let exportedAsset = AVURLAsset(url: outputURL)
    let exportedDuration = try await exportedAsset.load(.duration).seconds
    let videoTracks = try await exportedAsset.loadTracks(withMediaType: .video)
    let audioTracks = try await exportedAsset.loadTracks(withMediaType: .audio)

    #expect(videoTracks.count == 1)
    #expect(audioTracks.count == 1)
    #expect(abs(exportedDuration - 4.0) < 0.25)

    let videoTrack = try #require(videoTracks.first)
    let naturalSize = try await videoTrack.load(.naturalSize)
    #expect(Int(naturalSize.width) % 2 == 0)
    #expect(Int(naturalSize.height) % 2 == 0)
    #expect(abs(naturalSize.width - 160) < 1)
    #expect(abs(naturalSize.height - 90) < 1)

    let phases = phaseRecorder.snapshot()
    #expect(phases.contains(.preparing))
    #expect(phases.contains(.merging(1.0)))
  }

  @Test(
    "All animated transition styles export with overlapped duration and audio crossfade",
    arguments: [TransitionStyle.crossDissolve, .dipToBlack, .slide]
  )
  func mergeAnimatedTransitions(style: TransitionStyle) async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let url1 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "clip1.mov", duration: 2.0, color: .red, includeAudio: true
    )
    let url2 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "clip2.mov", duration: 2.0, color: .blue, includeAudio: true
    )

    let engine = VideoMergeEngine()
    let clips = [makeClipItem(from: url1, duration: 2.0), makeClipItem(from: url2, duration: 2.0)]
    let config = MergeConfiguration(
      transitionStyle: style,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )

    let outputURL = dir.appendingPathComponent("merged_\(style.rawValue).mov")
    let reportedDuration = try await engine.mergeToFile(
      clips: clips,
      configuration: config,
      outputURL: outputURL
    )

    let expected = config.estimatedOutputDuration(for: [2.0, 2.0])  // 3.5s
    #expect(abs(reportedDuration - expected) < 0.25)

    let exportedAsset = AVURLAsset(url: outputURL)
    let exportedDuration = try await exportedAsset.load(.duration).seconds
    #expect(abs(exportedDuration - expected) < 0.25)
    #expect(try await exportedAsset.loadTracks(withMediaType: .video).count == 1)
    #expect(try await exportedAsset.loadTracks(withMediaType: .audio).count == 1)
  }

  @Test("Three-clip merge with cross dissolve handles alternating A/B lanes accurately")
  func mergeThreeClipsPingPongLanes() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let url1 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "c1.mov", duration: 2.0, color: .red
    )
    let url2 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "c2.mov", duration: 2.0, color: .green
    )
    let url3 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "c3.mov", duration: 2.0, color: .blue
    )

    let engine = VideoMergeEngine()
    let clips = [
      makeClipItem(from: url1, duration: 2.0),
      makeClipItem(from: url2, duration: 2.0),
      makeClipItem(from: url3, duration: 2.0),
    ]
    let config = MergeConfiguration(
      transitionStyle: .crossDissolve,
      transitionDuration: 0.5,
      preserveMetadata: false,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )

    let outputURL = dir.appendingPathComponent("merged_3clips.mov")
    let reportedDuration = try await engine.mergeToFile(
      clips: clips,
      configuration: config,
      outputURL: outputURL
    )

    // 2 + 2 + 2 - 0.5 - 0.5 = 5.0s
    #expect(abs(reportedDuration - 5.0) < 0.25)
    let exportedDuration = try await AVURLAsset(url: outputURL).load(.duration).seconds
    #expect(abs(exportedDuration - 5.0) < 0.25)
  }

  @Test("Mixed portrait and landscape clips adopt the first clip's oriented canvas size")
  func mergeMixedOrientationsFollowsClipOrder() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let portraitTransform = CGAffineTransform(rotationAngle: .pi / 2)
    let portraitURL = try await TestVideoFixtureFactory.makeVideo(
      in: dir,
      filename: "portrait.mov",
      size: CGSize(width: 160, height: 90),
      duration: 1.5,
      color: .red,
      transform: portraitTransform
    )
    let landscapeURL = try await TestVideoFixtureFactory.makeVideo(
      in: dir,
      filename: "landscape.mov",
      size: CGSize(width: 160, height: 90),
      duration: 1.5,
      color: .blue,
      transform: .identity
    )

    let portraitClip = makeClipItem(
      from: portraitURL, duration: 1.5, size: CGSize(width: 160, height: 90),
      transform: portraitTransform
    )
    let landscapeClip = makeClipItem(
      from: landscapeURL, duration: 1.5, size: CGSize(width: 160, height: 90),
      transform: .identity
    )

    let config = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )
    let engine = VideoMergeEngine()

    // Portrait first -> portrait output (90x160)
    let portraitFirstURL = dir.appendingPathComponent("portrait_first.mov")
    _ = try await engine.mergeToFile(
      clips: [portraitClip, landscapeClip],
      configuration: config,
      outputURL: portraitFirstURL
    )
    let pfTrack = try #require(
      try await AVURLAsset(url: portraitFirstURL).loadTracks(withMediaType: .video).first
    )
    let pfSize = try await pfTrack.load(.naturalSize)
    #expect(pfSize.height > pfSize.width)
    #expect(abs(pfSize.width - 90) < 1)
    #expect(abs(pfSize.height - 160) < 1)

    // Reordered landscape first -> landscape output (160x90)
    let landscapeFirstURL = dir.appendingPathComponent("landscape_first.mov")
    _ = try await engine.mergeToFile(
      clips: [landscapeClip, portraitClip],
      configuration: config,
      outputURL: landscapeFirstURL
    )
    let lfTrack = try #require(
      try await AVURLAsset(url: landscapeFirstURL).loadTracks(withMediaType: .video).first
    )
    let lfSize = try await lfTrack.load(.naturalSize)
    #expect(lfSize.width > lfSize.height)
    #expect(abs(lfSize.width - 160) < 1)
    #expect(abs(lfSize.height - 90) < 1)
  }

  @Test("Auto-trim cuts output over 30s down to 30.0s and leaves shorter outputs untouched")
  func mergeAutoTrimThirtySeconds() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let config = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: true,
      autoTrimInterval: .thirtySeconds
    )
    let engine = VideoMergeEngine()

    // Case 1: 16s + 16s = 32s -> trimmed to 30.0s (with audio fade-out)
    let long1 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "long1.mov", size: CGSize(width: 96, height: 64),
      duration: 16.0, fps: 10, color: .red, includeAudio: true
    )
    let long2 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "long2.mov", size: CGSize(width: 96, height: 64),
      duration: 16.0, fps: 10, color: .blue, includeAudio: true
    )
    let trimmedURL = dir.appendingPathComponent("trimmed_30s.mov")
    let trimmedReported = try await engine.mergeToFile(
      clips: [
        makeClipItem(from: long1, duration: 16.0, size: CGSize(width: 96, height: 64)),
        makeClipItem(from: long2, duration: 16.0, size: CGSize(width: 96, height: 64)),
      ],
      configuration: config,
      outputURL: trimmedURL
    )
    let trimmedActual = try await AVURLAsset(url: trimmedURL).load(.duration).seconds
    #expect(abs(trimmedReported - 30.0) < 0.1)
    #expect(abs(trimmedActual - 30.0) < 0.35)

    // Case 2: 2s + 2s = 4s (< 30s) -> left untouched at ~4.0s
    let short1 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "short1.mov", duration: 2.0, color: .green
    )
    let short2 = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "short2.mov", duration: 2.0, color: .blue
    )
    let untouchedURL = dir.appendingPathComponent("untouched_4s.mov")
    let untouchedReported = try await engine.mergeToFile(
      clips: [makeClipItem(from: short1, duration: 2.0), makeClipItem(from: short2, duration: 2.0)],
      configuration: config,
      outputURL: untouchedURL
    )
    let untouchedActual = try await AVURLAsset(url: untouchedURL).load(.duration).seconds
    #expect(abs(untouchedReported - 4.0) < 0.25)
    #expect(abs(untouchedActual - 4.0) < 0.25)
  }

  @Test("mergeToFile validates minimum clip count and rejects unreadable files")
  func mergeErrorHandling() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let engine = VideoMergeEngine()
    let config = MergeConfiguration(
      transitionStyle: .none,
      transitionDuration: 0.5,
      preserveMetadata: true,
      deleteSourceClipsAfterMerge: false,
      autoTrimEnabled: false,
      autoTrimInterval: .thirtySeconds
    )
    let outputURL = dir.appendingPathComponent("out.mov")

    // 0 clips -> insufficientClips
    await #expect(throws: VideoMergeError.self) {
      _ = try await engine.mergeToFile(clips: [], configuration: config, outputURL: outputURL)
    }

    // 1 clip -> insufficientClips
    let validURL = try await TestVideoFixtureFactory.makeVideo(
      in: dir, filename: "single.mov", duration: 1.0
    )
    do {
      _ = try await engine.mergeToFile(
        clips: [makeClipItem(from: validURL, duration: 1.0)],
        configuration: config,
        outputURL: outputURL
      )
      Issue.record("Expected insufficientClips error")
    } catch VideoMergeError.insufficientClips {
      // Expected
    }

    // Corrupt/non-video second file -> unreadableVideo
    let corruptURL = dir.appendingPathComponent("not_a_video.mov")
    try Data("not a valid quicktime file".utf8).write(to: corruptURL)
    do {
      _ = try await engine.mergeToFile(
        clips: [
          makeClipItem(from: validURL, duration: 1.0),
          makeClipItem(from: corruptURL, duration: 1.0),
        ],
        configuration: config,
        outputURL: outputURL
      )
      Issue.record("Expected unreadableVideo or AVFoundation error")
    } catch {
      // Expected failure on invalid movie file
    }
  }

  // MARK: - Share Extension Clip Loading and Cleanup

  @Test("loadClips extracts movie attachments, metadata, thumbnails, and cleans up temp files")
  func loadClipsFromSingleExtensionItemAndCleanup() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let captureDate = Date(timeIntervalSince1970: 1_735_689_600)  // 2025-01-01T00:00:00Z
    let url1 = try await TestVideoFixtureFactory.makeVideo(
      in: dir,
      filename: "IMG_0001.mov",
      duration: 1.5,
      color: .red,
      creationDate: captureDate,
      locationISO6709: "+37.7749-122.4194+015.000/"
    )
    let url2 = try await TestVideoFixtureFactory.makeVideo(
      in: dir,
      filename: "IMG_0002.mov",
      duration: 2.0,
      color: .blue
    )

    let provider1 = NSItemProvider()
    provider1.suggestedName = "IMG_0001"
    provider1.registerFileRepresentation(
      forTypeIdentifier: UTType.movie.identifier,
      fileOptions: [],
      visibility: .all
    ) { completion in
      completion(url1, false, nil)
      return nil
    }

    let provider2 = NSItemProvider()
    provider2.suggestedName = "IMG_0002"
    provider2.registerFileRepresentation(
      forTypeIdentifier: UTType.movie.identifier,
      fileOptions: [],
      visibility: .all
    ) { completion in
      completion(url2, false, nil)
      return nil
    }

    // Non-video attachment should be ignored cleanly.
    let textProvider = NSItemProvider(object: "ignored caption" as NSString)

    // Photos shares multiple selected videos as multiple attachments on one NSExtensionItem.
    let item = NSExtensionItem()
    item.attachments = [provider1, textProvider, provider2]

    let progressRecorder = ProgressRecorder()
    let engine = VideoMergeEngine()
    let loaded = try await engine.loadClips(from: [item]) { current, total in
      progressRecorder.record(current: current, total: total)
    }

    #expect(loaded.count == 2)
    #expect(abs(loaded[0].duration - 1.5) < 0.25)
    #expect(abs(loaded[1].duration - 2.0) < 0.25)
    #expect(loaded[0].thumbnail != nil)
    #expect(loaded[1].thumbnail != nil)

    // Verify metadata extracted from the first clip's QuickTime container.
    let loadedDate = try #require(loaded[0].creationDate)
    #expect(abs(loadedDate.timeIntervalSince(captureDate)) < 2.0)
    let loadedLocation = try #require(loaded[0].location)
    #expect(abs(loadedLocation.coordinate.latitude - 37.7749) < 0.001)
    #expect(abs(loadedLocation.coordinate.longitude - (-122.4194)) < 0.001)

    // Verify progress callbacks fired for (1, 2) and (2, 2).
    let recordedProgress = progressRecorder.snapshot()
    #expect(recordedProgress.count == 2)
    #expect(recordedProgress[0].0 == 1 && recordedProgress[0].1 == 2)
    #expect(recordedProgress[1].0 == 2 && recordedProgress[1].1 == 2)

    // Verify copied temp files exist and cleanupTemporaryFiles removes them and their session dir.
    let sessionDir = loaded[0].fileURL.deletingLastPathComponent()
    #expect(FileManager.default.fileExists(atPath: loaded[0].fileURL.path))
    #expect(FileManager.default.fileExists(atPath: loaded[1].fileURL.path))

    engine.cleanupTemporaryFiles(for: loaded)

    #expect(!FileManager.default.fileExists(atPath: loaded[0].fileURL.path))
    #expect(!FileManager.default.fileExists(atPath: loaded[1].fileURL.path))
    #expect(!FileManager.default.fileExists(atPath: sessionDir.path))
  }

  @Test("loadClips supports multiple NSExtensionItems and returns empty for non-video items")
  func loadClipsMultipleExtensionItemsAndEmpty() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let engine = VideoMergeEngine()

    let emptyItem = NSExtensionItem()
    emptyItem.attachments = [NSItemProvider(object: "just text" as NSString)]
    let emptyLoaded = try await engine.loadClips(from: [emptyItem])
    #expect(emptyLoaded.isEmpty)

    let url1 = try await TestVideoFixtureFactory.makeVideo(in: dir, filename: "a.mov", duration: 1.0)
    let url2 = try await TestVideoFixtureFactory.makeVideo(in: dir, filename: "b.mov", duration: 1.5)

    let item1 = NSExtensionItem()
    let p1 = NSItemProvider()
    p1.registerFileRepresentation(
      forTypeIdentifier: UTType.movie.identifier, fileOptions: [], visibility: .all
    ) { completion in
      completion(url1, false, nil)
      return nil
    }
    item1.attachments = [p1]

    let item2 = NSExtensionItem()
    let p2 = NSItemProvider()
    p2.registerFileRepresentation(
      forTypeIdentifier: UTType.movie.identifier, fileOptions: [], visibility: .all
    ) { completion in
      completion(url2, false, nil)
      return nil
    }
    item2.attachments = [p2]

    let loaded = try await engine.loadClips(from: [item1, item2])
    defer { engine.cleanupTemporaryFiles(for: loaded) }

    #expect(loaded.count == 2)
    #expect(abs(loaded[0].duration - 1.0) < 0.25)
    #expect(abs(loaded[1].duration - 1.5) < 0.25)
  }
}

// MARK: - Thread-Safe Test Recorders

private final class PhaseRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var phases: [MergePhase] = []

  func record(_ phase: MergePhase) {
    lock.lock()
    phases.append(phase)
    lock.unlock()
  }

  func snapshot() -> [MergePhase] {
    lock.lock()
    defer { lock.unlock() }
    return phases
  }
}

private final class ProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [(Int, Int)] = []

  func record(current: Int, total: Int) {
    lock.lock()
    events.append((current, total))
    lock.unlock()
  }

  func snapshot() -> [(Int, Int)] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}
