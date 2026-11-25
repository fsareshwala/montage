import Foundation
import OtherApps
import Photos
import SwiftUI
import Testing
import UIKit

@testable import Montage

@Suite("Host App Presentation & Content")
struct HostAppPresentationTests {

  private static let allPhotoAuthorizationStatuses: [PHAuthorizationStatus] = [
    .authorized,
    .limited,
    .notDetermined,
    .denied,
    .restricted,
  ]

  @Test("PhotoAccessPresentation hides banner only when authorized")
  func photoAccessBannerVisibility() {
    #expect(!PhotoAccessPresentation(status: .authorized).needsFullAccessBanner)
    #expect(PhotoAccessPresentation(status: .limited).needsFullAccessBanner)
    #expect(PhotoAccessPresentation(status: .notDetermined).needsFullAccessBanner)
    #expect(PhotoAccessPresentation(status: .denied).needsFullAccessBanner)
    #expect(PhotoAccessPresentation(status: .restricted).needsFullAccessBanner)
  }

  @Test("PhotoAccessPresentation uses request symbol only when notDetermined")
  func photoAccessActionButtonSymbol() {
    let notDetermined = PhotoAccessPresentation(status: .notDetermined)
    #expect(notDetermined.actionButtonSymbol == SystemSymbolCompatibility.shared.photoAccessRequest)
    #expect(UIImage(systemName: notDetermined.actionButtonSymbol) != nil)

    for status in [PHAuthorizationStatus.authorized, .limited, .denied, .restricted] {
      let presentation = PhotoAccessPresentation(status: status)
      #expect(presentation.actionButtonSymbol == "gearshape")
      #expect(UIImage(systemName: presentation.actionButtonSymbol) != nil)
    }
  }

  @Test("PhotoAccessPresentation provides valid badges, colors, and copy for every status")
  func photoAccessMetadataForAllStatuses() {
    let authorized = PhotoAccessPresentation(status: .authorized)
    #expect(authorized.badgeSymbol == "checkmark.circle")
    #expect(authorized.badgeColor == .green)
    #expect(authorized.title == "Full Photo Access Enabled")

    let limited = PhotoAccessPresentation(status: .limited)
    #expect(limited.badgeSymbol == "exclamationmark.triangle")
    #expect(limited.badgeColor == .orange)
    #expect(limited.title == "Limited Photo Access")

    let notDetermined = PhotoAccessPresentation(status: .notDetermined)
    #expect(notDetermined.badgeSymbol == "photo.on.rectangle.angled")
    #expect(notDetermined.badgeColor == .accentColor)
    #expect(notDetermined.title == "Photo Access Not Set")

    let denied = PhotoAccessPresentation(status: .denied)
    #expect(denied.badgeSymbol == "lock")
    #expect(denied.badgeColor == .red)
    #expect(denied.title == "Photo Access Denied")

    let restricted = PhotoAccessPresentation(status: .restricted)
    #expect(restricted.badgeSymbol == "lock")
    #expect(restricted.badgeColor == .red)
    #expect(restricted.title == "Photo Access Restricted")

    for status in Self.allPhotoAuthorizationStatuses {
      let presentation = PhotoAccessPresentation(status: status)
      #expect(!presentation.title.isEmpty)
      #expect(!presentation.subtitle.isEmpty)
      #expect(UIImage(systemName: presentation.badgeSymbol) != nil)
    }
  }

  @Test("HostAppContent quick guide defines three ordered steps with valid SF Symbols")
  func quickGuideStepsAreValid() {
    let steps = HostAppContent.quickGuideSteps
    #expect(steps.count == 3)
    #expect(steps.map(\.text) == [
      "Select 2 or more clips in Photos",
      "Tap Share and pick Montage",
      "Reorder and Merge into one video",
    ])

    let uniqueIDs = Set(steps.map(\.id))
    #expect(uniqueIDs.count == steps.count)

    for step in steps {
      #expect(!step.symbolName.isEmpty)
      #expect(UIImage(systemName: step.symbolName) != nil)
    }
  }

  @Test("HostAppContent external links point to valid GitHub HTTPS URLs")
  func externalLinksAreValidHTTPS() {
    #expect(HostAppContent.githubURL.scheme == "https")
    #expect(HostAppContent.githubURL.host == "github.com")
    #expect(HostAppContent.issuesURL.scheme == "https")
    #expect(HostAppContent.issuesURL.host == "github.com")
    #expect(HostAppContent.issuesURL.absoluteString.hasPrefix(HostAppContent.githubURL.absoluteString))
  }

  @Test("OtherAppsView excludes Montage and lists Forecash and Clean Dial with valid icons and URLs")
  func otherAppsCatalogIsValid() throws {
    let view = OtherAppsView()
    let apps = view.apps
    #expect(apps.map(\.appName) == ["Forecash", "Clean Dial"])
    #expect(!apps.contains(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }))

    let uniqueIDs = Set(apps.map(\.id))
    #expect(uniqueIDs.count == apps.count)

    for app in apps {
      #expect(!app.description.isEmpty)
      let url = try #require(app.appStoreURL)
      #expect(url.scheme == "https")
      #expect(url.host == "apps.apple.com")
      #expect(app.iconUIImage != nil)
    }
  }

  @Test("PrivacyPolicyView describes local processing and links to source repository")
  func privacyPolicyContentIsComplete() {
    let text = PrivacyPolicyView.policyText
    #expect(!text.isEmpty)
    #expect(text.contains("Local Processing"))
    #expect(text.contains("Photo Library Access"))
    #expect(text.contains("No Data Collection or Third-Party Tracking"))
    #expect(text.contains(HostAppContent.githubURL.absoluteString))
  }

  @Test("All host app user-facing copy satisfies wording constraints")
  func userFacingCopySatisfiesConstraints() {
    var allCopy = HostAppContent.allUserFacingStrings
    allCopy.append(PrivacyPolicyView.title)
    allCopy.append(PrivacyPolicyView.policyText)

    for status in Self.allPhotoAuthorizationStatuses {
      let presentation = PhotoAccessPresentation(status: status)
      allCopy.append(presentation.title)
      allCopy.append(presentation.subtitle)
    }

    for app in OtherAppsView().apps {
      allCopy.append(app.appName)
      allCopy.append(app.description)
    }

    for copy in allCopy {
      #expect(!copy.isEmpty)
      #expect(!copy.contains("&"), "Unexpected '&' character found in copy: \(copy)")
      #expect(
        !copy.localizedCaseInsensitiveContains("outing"),
        "Unexpected 'outing' wording found in copy: \(copy)"
      )
    }
  }

  @Test("Host app views host cleanly in UIHostingController")
  @MainActor
  func hostAppViewsRenderSafely() {
    let contentController = UIHostingController(rootView: ContentView())
    contentController.loadViewIfNeeded()
    let contentSize = contentController.sizeThatFits(in: CGSize(width: 390, height: 844))
    #expect(contentSize.width > 0)
    #expect(contentSize.height > 0)

    let privacyController = UIHostingController(rootView: PrivacyPolicyView())
    privacyController.loadViewIfNeeded()
    let privacySize = privacyController.sizeThatFits(in: CGSize(width: 390, height: 844))
    #expect(privacySize.width > 0)
    #expect(privacySize.height > 0)

    let otherAppsController = UIHostingController(rootView: Form { OtherAppsView() })
    otherAppsController.loadViewIfNeeded()
    let otherAppsSize = otherAppsController.sizeThatFits(in: CGSize(width: 390, height: 400))
    #expect(otherAppsSize.width > 0)
    #expect(otherAppsSize.height > 0)
  }
}
