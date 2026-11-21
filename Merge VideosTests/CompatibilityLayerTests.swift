import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Merge_Videos

@Suite("iOS Compatibility Layers")
struct CompatibilityLayerTests {

  @Test("Host app and ShareExtension target iOS 15.0 minimum deployment")
  func minimumOSVersionIsIOS15() throws {
    let appMinOS = try #require(
      Bundle.main.object(forInfoDictionaryKey: "MinimumOSVersion") as? String
    )
    #expect(appMinOS == "15.0")

    let extensionBundle = try Bundle.embeddedShareExtension()
    let extMinOS = try #require(
      extensionBundle.object(forInfoDictionaryKey: "MinimumOSVersion") as? String
    )
    #expect(extMinOS == "15.0")
  }

  @Test("SystemSymbolCompatibility returns valid non-empty SF Symbols")
  func systemSymbolsResolveToValidImages() {
    let symbols = SystemSymbolCompatibility.shared
    let names = [
      symbols.photoAccessRequest,
      symbols.photoStack,
      symbols.videoStack,
      symbols.videoStackFill,
    ]
    for name in names {
      #expect(!name.isEmpty)
      #expect(UIImage(systemName: name) != nil)
    }
  }

  @Test("TaskSleepCompatibility completes short delays without throwing")
  func taskSleepCompletes() async throws {
    try await TaskSleepCompatibility.shared.sleep(milliseconds: 10)
  }

  @Test("VideoCompositionBuilder creates valid instructions and video composition")
  func videoCompositionBuilderCreatesValidComposition() async throws {
    let dir = try TestVideoFixtureFactory.makeTempDirectory(named: "CompatibilityLayerTests")
    defer { try? FileManager.default.removeItem(at: dir) }

    let videoURL = try await TestVideoFixtureFactory.makeVideo(
      in: dir,
      filename: "sample.mov",
      size: CGSize(width: 160, height: 90),
      duration: 1.0,
      color: .blue
    )

    let asset = AVURLAsset(url: videoURL)
    let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1.0, preferredTimescale: 600))
    let builder = VideoCompositionBuilder.shared

    let layer = builder.makeLayerInstruction(
      track: videoTrack,
      transform: .identity,
      at: .zero,
      opacity: 1.0
    )
    let instruction = builder.makeVideoInstruction(
      timeRange: range,
      backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
      layerInstructions: [layer]
    )
    let composition = builder.makeVideoComposition(
      renderSize: CGSize(width: 160, height: 90),
      frameDuration: CMTime(value: 1, timescale: 30),
      instructions: [instruction]
    )

    #expect(composition.renderSize == CGSize(width: 160, height: 90))
    #expect(composition.instructions.count == 1)
  }

  @Test("VideoThumbnailGenerator generates a non-nil thumbnail within requested bounds")
  func thumbnailGeneratorProducesImage() async throws {
    let dir = try TestVideoFixtureFactory.makeTempDirectory(named: "CompatibilityLayerTests")
    defer { try? FileManager.default.removeItem(at: dir) }

    let videoURL = try await TestVideoFixtureFactory.makeVideo(
      in: dir,
      filename: "thumb.mov",
      size: CGSize(width: 160, height: 90),
      duration: 1.0,
      color: .green
    )

    let asset = AVURLAsset(url: videoURL)
    let image = await VideoThumbnailGenerator.shared.generateThumbnail(
      for: asset,
      at: .zero,
      maximumSize: CGSize(width: 120, height: 120)
    )

    let thumbnail = try #require(image)
    #expect(thumbnail.size.width > 0)
    #expect(thumbnail.size.height > 0)
  }

  @Test("HapticFeedbackController triggers feedback styles safely on MainActor")
  @MainActor
  func hapticFeedbackControllerTriggersSafely() {
    let controller = HapticFeedbackController()
    controller.trigger(.selection)
    controller.trigger(.success)
  }

  @Test("compatibleButtonStyle hosts standard and prominent buttons safely on MainActor")
  @MainActor
  func compatibleButtonStyleHostsSafely() {
    let view = VStack {
      Button("Standard") {}
        .compatibleButtonStyle(.standard)
      Button("Prominent") {}
        .compatibleButtonStyle(.prominent)
    }
    let controller = UIHostingController(rootView: view)
    controller.loadViewIfNeeded()
    let fittedSize = controller.sizeThatFits(in: CGSize(width: 320, height: 200))
    #expect(fittedSize.width > 0)
    #expect(fittedSize.height > 0)
  }
}
