import Foundation
import Testing

@Suite("App and Share Extension Bundle Configuration")
struct ShareExtensionConfigurationTests {

  @Test("Host app Info.plist has expected display name, bundle ID, and clean usage description")
  func hostAppPhotoUsageDescription() throws {
    #expect(Bundle.main.bundleIdentifier == "com.sareshwala.faraaz.montage")
    #expect(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Montage")

    let usage = try #require(
      Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") as? String
    )
    #expect(!usage.isEmpty)
    #expect(!usage.localizedCaseInsensitiveContains("outing"))
    #expect(!usage.contains("&"))
  }

  @Test("Embedded ShareExtension declares valid Photos Share Sheet activation rules")
  func shareExtensionActivationRuleAndMetadata() throws {
    let extensionBundle = try Bundle.embeddedShareExtension()
    let info = try #require(extensionBundle.infoDictionary)

    #expect(extensionBundle.bundleIdentifier == "com.sareshwala.faraaz.montage.share")
    #expect(info["CFBundleDisplayName"] as? String == "Montage")

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

  @Test("Both host app and ShareExtension bundle a valid PrivacyInfo.xcprivacy manifest")
  func privacyManifestsPresentAndValid() throws {
    let extensionBundle = try Bundle.embeddedShareExtension()

    for bundle in [Bundle.main, extensionBundle] {
      let manifestURL = try #require(
        bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
        "Missing PrivacyInfo.xcprivacy in \(bundle.bundleURL.lastPathComponent)"
      )
      let data = try Data(contentsOf: manifestURL)
      let plist = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
      )

      #expect(plist["NSPrivacyTracking"] as? Bool == false)
      #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
      #expect((plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.isEmpty == true)

      let apiTypes = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
      let userDefaultsEntry = try #require(
        apiTypes.first {
          $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
      )
      let reasons = try #require(userDefaultsEntry["NSPrivacyAccessedAPITypeReasons"] as? [String])
      #expect(reasons.contains("1C8F.1"))
      #expect(reasons.contains("CA92.1"))
    }
  }
}
