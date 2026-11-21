import Foundation
import Testing
import UniformTypeIdentifiers

/// Thread-safe event recorder for verifying async progress and phase callbacks in tests.
final class LockedRecorder<Event: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [Event] = []

  func record(_ event: Event) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }

  func snapshot() -> [Event] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

extension Bundle {
  /// Returns the embedded `ShareExtension.appex` bundle inside the host app's `PlugIns` directory.
  static func embeddedShareExtension() throws -> Bundle {
    let pluginsURL = try #require(Bundle.main.builtInPlugInsURL)
    let extensionURL = pluginsURL.appendingPathComponent("ShareExtension.appex", isDirectory: true)
    return try #require(Bundle(url: extensionURL))
  }
}

/// Builds an `NSItemProvider` advertising a QuickTime movie file representation for Share Extension tests.
func makeMovieItemProvider(url: URL, suggestedName: String? = nil) -> NSItemProvider {
  let provider = NSItemProvider()
  provider.suggestedName = suggestedName
  provider.registerFileRepresentation(
    forTypeIdentifier: UTType.movie.identifier,
    fileOptions: [],
    visibility: .all
  ) { completion in
    completion(url, false, nil)
    return nil
  }
  return provider
}
