import AVFoundation
import CoreAudioTypes
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// Generates real synthetic QuickTime `.mov` video fixtures on disk using `AVAssetWriter`
/// so video merging, transitions, orientation normalization, auto-trim, and Share Extension
/// loading can be verified end-to-end without external binary assets.
enum TestVideoFixtureFactory {
  struct RGBAColor: Sendable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    static let red = RGBAColor(r: 220, g: 50, b: 50, a: 255)
    static let blue = RGBAColor(r: 50, g: 100, b: 230, a: 255)
    static let green = RGBAColor(r: 45, g: 190, b: 90, a: 255)
  }

  enum FixtureError: Error {
    case pixelBufferCreationFailed
    case writerFailed(String)
    case audioFormatFailed
  }

  static func makeVideo(
    in directory: URL,
    filename: String = "\(UUID().uuidString).mov",
    size: CGSize = CGSize(width: 160, height: 90),
    duration: TimeInterval = 2.0,
    fps: Int32 = 15,
    color: RGBAColor = .blue,
    transform: CGAffineTransform = .identity,
    includeAudio: Bool = false,
    creationDate: Date? = nil,
    locationISO6709: String? = nil
  ) async throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let outputURL = directory.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: outputURL)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

    var metadataItems: [AVMetadataItem] = []
    if let creationDate {
      let dateItem = AVMutableMetadataItem()
      dateItem.identifier = .commonIdentifierCreationDate
      dateItem.value = ISO8601DateFormatter().string(from: creationDate) as NSString
      metadataItems.append(dateItem)
    }
    if let locationISO6709 {
      let locItem = AVMutableMetadataItem()
      locItem.identifier = .commonIdentifierLocation
      locItem.value = locationISO6709 as NSString
      metadataItems.append(locItem)
    }
    if !metadataItems.isEmpty {
      writer.metadata = metadataItems
    }

    let width = Int(size.width)
    let height = Int(size.height)

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ]
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.transform = transform

    let audioInput: AVAssetWriterInput?
    if includeAudio {
      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 44_100,
        AVEncoderBitRateKey: 64_000,
      ]
      audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
    } else {
      audioInput = nil
    }

    let pixelBuffer = try makeSolidPixelBuffer(width: width, height: height, color: color)
    let totalFrames = max(1, Int((duration * Double(fps)).rounded()))

    if #available(iOS 26, *) {
      try await writeModern(
        writer: writer,
        videoInput: videoInput,
        audioInput: audioInput,
        pixelBuffer: pixelBuffer,
        totalFrames: totalFrames,
        fps: fps,
        duration: duration
      )
    } else {
      try await writeLegacy(
        writer: writer,
        videoInput: videoInput,
        audioInput: audioInput,
        pixelBuffer: pixelBuffer,
        totalFrames: totalFrames,
        fps: fps,
        duration: duration
      )
    }

    await writer.finishWriting()
    if writer.status != .completed {
      throw FixtureError.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed")
    }

    return outputURL
  }

  @available(iOS 26, *)
  private static func writeModern(
    writer: AVAssetWriter,
    videoInput: AVAssetWriterInput,
    audioInput: AVAssetWriterInput?,
    pixelBuffer: CVPixelBuffer,
    totalFrames: Int,
    fps: Int32,
    duration: TimeInterval
  ) async throws {
    let videoReceiver = writer.inputPixelBufferReceiver(
      for: videoInput,
      pixelBufferAttributes: nil
    )
    let audioReceiver = audioInput.map { writer.inputReceiver(for: $0) }

    try writer.start()
    writer.startSession(atSourceTime: .zero)

    let readOnlyFrame = CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer)

    // Write video and audio concurrently so AVAssetWriter can interleave both tracks without blocking.
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for frameIndex in 0..<totalFrames {
          let pts = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
          try await videoReceiver.append(readOnlyFrame, with: pts)
        }
        videoReceiver.finish()
      }

      if let audioReceiver {
        group.addTask {
          let sampleRate: Double = 44_100
          let totalSamples = Int((duration * sampleRate).rounded())
          let chunkSize = 4_410  // 0.1s chunks
          let formatDescription = try makePCMFormatDescription(sampleRate: sampleRate)

          var offset = 0
          while offset < totalSamples {
            let count = min(chunkSize, totalSamples - offset)
            let pts = CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(sampleRate))
            let sampleBuffer = try makeSilentAudioSampleBuffer(
              formatDescription: formatDescription,
              sampleCount: count,
              presentationTimeStamp: pts
            )
            let readySample = CMReadySampleBuffer(unsafeBuffer: sampleBuffer)
            try await audioReceiver.append(readySample)
            offset += count
          }
          audioReceiver.finish()
        }
      }

      try await group.waitForAll()
    }
  }

  private static func writeLegacy(
    writer: AVAssetWriter,
    videoInput: AVAssetWriterInput,
    audioInput: AVAssetWriterInput?,
    pixelBuffer: CVPixelBuffer,
    totalFrames: Int,
    fps: Int32,
    duration: TimeInterval
  ) async throws {
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: nil
    )
    writer.add(videoInput)
    if let audioInput {
      writer.add(audioInput)
    }

    guard writer.startWriting() else {
      throw FixtureError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
    }
    writer.startSession(atSourceTime: .zero)

    let videoBox = LegacySendableBox(videoInput)
    let adaptorBox = LegacySendableBox(adaptor)
    let bufferBox = LegacySendableBox(pixelBuffer)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        let queue = DispatchQueue(label: "TestVideoFixtureFactory.video")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          var frameIndex = 0
          var finished = false
          videoBox.value.requestMediaDataWhenReady(on: queue) {
            while videoBox.value.isReadyForMoreMediaData && frameIndex < totalFrames {
              let pts = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
              _ = adaptorBox.value.append(bufferBox.value, withPresentationTime: pts)
              frameIndex += 1
            }
            if frameIndex >= totalFrames, !finished {
              finished = true
              videoBox.value.markAsFinished()
              continuation.resume()
            }
          }
        }
      }

      if let audioInput {
        let audioBox = LegacySendableBox(audioInput)
        group.addTask {
          let sampleRate: Double = 44_100
          let totalSamples = Int((duration * sampleRate).rounded())
          let chunkSize = 4_410
          let formatDescription = try makePCMFormatDescription(sampleRate: sampleRate)
          let queue = DispatchQueue(label: "TestVideoFixtureFactory.audio")

          try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            var offset = 0
            var finished = false
            audioBox.value.requestMediaDataWhenReady(on: queue) {
              do {
                while audioBox.value.isReadyForMoreMediaData && offset < totalSamples {
                  let count = min(chunkSize, totalSamples - offset)
                  let pts = CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(sampleRate))
                  let sampleBuffer = try makeSilentAudioSampleBuffer(
                    formatDescription: formatDescription,
                    sampleCount: count,
                    presentationTimeStamp: pts
                  )
                  _ = audioBox.value.append(sampleBuffer)
                  offset += count
                }
                if offset >= totalSamples, !finished {
                  finished = true
                  audioBox.value.markAsFinished()
                  continuation.resume()
                }
              } catch {
                if !finished {
                  finished = true
                  audioBox.value.markAsFinished()
                  continuation.resume(throwing: error)
                }
              }
            }
          }
        }
      }

      try await group.waitForAll()
    }
  }

  private final class LegacySendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
  }

  private static func makeSolidPixelBuffer(
    width: Int,
    height: Int,
    color: RGBAColor
  ) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      throw FixtureError.pixelBufferCreationFailed
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
      let rawPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
      for y in 0..<height {
        let row = rawPtr.advanced(by: y * bytesPerRow)
        for x in 0..<width {
          let pixel = x * 4
          row[pixel + 0] = color.b
          row[pixel + 1] = color.g
          row[pixel + 2] = color.r
          row[pixel + 3] = color.a
        }
      }
    }

    return buffer
  }

  private static func makePCMFormatDescription(sampleRate: Double) throws -> CMAudioFormatDescription {
    var asbd = AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    var formatDescription: CMAudioFormatDescription?
    let status = CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      asbd: &asbd,
      layoutSize: 0,
      layout: nil,
      magicCookieSize: 0,
      magicCookie: nil,
      extensions: nil,
      formatDescriptionOut: &formatDescription
    )
    guard status == noErr, let formatDescription else {
      throw FixtureError.audioFormatFailed
    }
    return formatDescription
  }

  private static func makeSilentAudioSampleBuffer(
    formatDescription: CMAudioFormatDescription,
    sampleCount: Int,
    presentationTimeStamp: CMTime
  ) throws -> CMSampleBuffer {
    let byteCount = sampleCount * MemoryLayout<Int16>.size
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: byteCount,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: byteCount,
      flags: 0,
      blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
      throw FixtureError.audioFormatFailed
    }

    let fillStatus = CMBlockBufferFillDataBytes(
      with: 0,
      blockBuffer: blockBuffer,
      offsetIntoDestination: 0,
      dataLength: byteCount
    )
    guard fillStatus == kCMBlockBufferNoErr else {
      throw FixtureError.audioFormatFailed
    }

    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: formatDescription,
      sampleCount: sampleCount,
      presentationTimeStamp: presentationTimeStamp,
      packetDescriptions: nil,
      sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
      throw FixtureError.audioFormatFailed
    }
    return sampleBuffer
  }
}
