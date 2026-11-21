import Foundation
import Testing

@Suite("App and Share Extension Bundle Configuration")
struct ShareExtensionConfigurationTests {

  @Test("Host app Info.plist has valid Photo Library usage description without restricted copy")
  func hostAppPhotoUsageDescription() throws {
    let usage = try #require(
      Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") as? String
    )
    #expect(!usage.isEmpty)
    #expect(!usage.localizedCaseInsensitiveContains("outing"))
    #expect(!usage.contains("&"))
  }

  @Test("Embedded ShareExtension declares valid Photos Share Sheet activation rules")
  func shareExtensionActivationRuleAndMetadata() throws {
    let pluginsURL = try #require(Bundle.main.builtInPlugInsURL)
    let extensionURL = pluginsURL.appendingPathComponent("ShareExtension.appex", isDirectory: true)
    let extensionBundle = try #require(Bundle(url: extensionURL))
    let info = try #require(extensionBundle.infoDictionary)

    #expect(info["CFBundleDisplayName"] as? String == "Clip Combine")

    let usage = try #require(info["NSPhotoLibraryUsageDescription"] as? String)
    #expect(!usage.isEmpty)
    #expect(!usage.localizedCaseInsensitiveContains("outing"))
    #expect(!usage.contains("&"))

    let nsExtension = try #require(info["NSExtension"] as? [String: Any])
    #expect(nsExtension["NSExtensionPointIdentifier"] as? String == "com.apple.share-services")

    let attributes = try #require(nsExtension["NSExtensionAttributes"] as? [String: Any])

    // Must be a dictionary activation rule (not a predicate string) with movie support >= 2
    // and without NSExtensionActivationSupportsAttachmentsWithMinCount, which prevents the
    // extension from appearing in the iOS Photos Share Sheet.
    let activationRule = try #require(attributes["NSExtensionActivationRule"] as? [String: Any])
    let maxMovieCount = try #require(
      activationRule["NSExtensionActivationSupportsMovieWithMaxCount"] as? Int
    )
    #expect(maxMovieCount >= 2)
    #expect(activationRule["NSExtensionActivationSupportsAttachmentsWithMinCount"] == nil)
  }
}
