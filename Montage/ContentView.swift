import Photos
import SwiftUI
import UIKit

/// A single step displayed in the host app's "How It Works" quick guide.
struct QuickGuideStep: Identifiable, Equatable {
  let id: String
  let symbolName: String
  let text: String
}

/// Presentation model mapping `PHAuthorizationStatus` to the Photo Access status section UI.
struct PhotoAccessPresentation {
  let status: PHAuthorizationStatus

  var needsFullAccessBanner: Bool {
    switch status {
    case .notDetermined, .limited, .denied, .restricted:
      return true
    case .authorized:
      return false
    @unknown default:
      return true
    }
  }

  var actionButtonSymbol: String {
    if status == .notDetermined {
      return SystemSymbolCompatibility.shared.photoAccessRequest
    } else {
      return "gearshape"
    }
  }

  var badgeSymbol: String {
    switch status {
    case .authorized:
      "checkmark.circle"
    case .limited:
      "exclamationmark.triangle"
    case .notDetermined:
      "photo.on.rectangle.angled"
    case .denied, .restricted:
      "lock"
    @unknown default:
      "photo.on.rectangle.angled"
    }
  }

  var badgeColor: Color {
    switch status {
    case .authorized:
      .green
    case .limited:
      .orange
    case .notDetermined:
      .accentColor
    case .denied, .restricted:
      .red
    @unknown default:
      .accentColor
    }
  }

  var title: String {
    switch status {
    case .authorized:
      "Full Photo Access Enabled"
    case .limited:
      "Limited Photo Access"
    case .notDetermined:
      "Photo Access Not Set"
    case .denied:
      "Photo Access Denied"
    case .restricted:
      "Photo Access Restricted"
    @unknown default:
      "Photo Access Required"
    }
  }

  var subtitle: String {
    switch status {
    case .authorized:
      "Ready to save montages with original dates, locations, and optional cleanup."
    case .limited:
      "Upgrade to Full Access to preserve dates, locations, and clean up source clips."
    case .notDetermined:
      "Grant access so Montage can save merged videos back to your library."
    case .denied:
      "Open iOS Settings to grant Montage access to your Photo Library."
    case .restricted:
      "Photo Library access is restricted on this device."
    @unknown default:
      "Grant Photo Library access to use Montage."
    }
  }
}

/// Static copy, quick guide steps, and external links displayed in the Montage host app.
enum HostAppContent {
  static let navigationTitle = "Montage"

  static let introText =
    "Montage is a video joiner. It is built for one job: joining video clips. There are no filters, audio overlays, or other editing clutter."

  static let statusSectionTitle = "Status"
  static let fullAccessButtonTitle = "Enable Full Photo Access"
  static let fullAccessExplanation =
    "Full Photo Library access lets Montage copy the original date and GPS location onto your montage and optionally clean up individual source clips."

  static let howItWorksSectionTitle = "How It Works"

  static var quickGuideSteps: [QuickGuideStep] {
    [
      QuickGuideStep(
        id: "select",
        symbolName: SystemSymbolCompatibility.shared.photoStack,
        text: "Select 2 or more clips in Photos"
      ),
      QuickGuideStep(
        id: "share",
        symbolName: "square.and.arrow.up",
        text: "Tap Share and pick Montage"
      ),
      QuickGuideStep(
        id: "merge",
        symbolName: "arrow.up.arrow.down.circle",
        text: "Reorder and Merge into one video"
      ),
    ]
  }

  static let transitionsSectionTitle = "Transitions"
  static let transitionStyleTitle = "Transition Style"

  static let hygieneSectionTitle = "Photo Library Hygiene"
  static let preserveMetadataTitle = "Preserve Metadata"
  static let preserveMetadataDescription =
    "Copy the capture date, time, and GPS location from the first clip onto the merged video."
  static let sourceCleanupTitle = "Post-Merge Source Cleanup"
  static let sourceCleanupDescription =
    "Prompt to delete the individual source clips from Photos after the merged montage is saved."

  static let uniformLengthSectionTitle = "Uniform Video Length"
  static let autoTrimTitle = "Auto-Trim to Fixed Intervals"
  static let autoTrimDescription =
    "Trim merged video down to the nearest fixed interval. Footage past the last completed interval is trimmed off. Videos shorter than one interval are untouched."
  static let trimIntervalTitle = "Trim Interval"

  static let aboutSectionTitle = "About"
  static let privacyPolicyTitle = "Privacy Policy"
  static let shareMontageTitle = "Share Montage"
  static let shareMontageMessage =
    "Check out Montage, the easiest way to merge clips from Photos!"
  static let reportBugTitle = "Report a Bug"
  static let sourceCodeTitle = "Source Code"
  static let sourceCodeSubtitle =
    "This app is fully open source. You can read the code on GitHub."

  static let otherAppsSectionTitle = "Other Apps from the Developer"

  static let githubURL = URL(string: "https://github.com/fsareshwala/montage")!
  static let issuesURL = URL(string: "https://github.com/fsareshwala/montage/issues")!

  /// Every user-facing string displayed by the host app's primary settings view.
  static var allUserFacingStrings: [String] {
    var strings = [
      navigationTitle,
      introText,
      statusSectionTitle,
      fullAccessButtonTitle,
      fullAccessExplanation,
      howItWorksSectionTitle,
      transitionsSectionTitle,
      transitionStyleTitle,
      hygieneSectionTitle,
      preserveMetadataTitle,
      preserveMetadataDescription,
      sourceCleanupTitle,
      sourceCleanupDescription,
      uniformLengthSectionTitle,
      autoTrimTitle,
      autoTrimDescription,
      trimIntervalTitle,
      aboutSectionTitle,
      privacyPolicyTitle,
      shareMontageTitle,
      shareMontageMessage,
      reportBugTitle,
      sourceCodeTitle,
      sourceCodeSubtitle,
      otherAppsSectionTitle,
    ]

    for step in quickGuideSteps {
      strings.append(step.text)
    }

    return strings
  }
}

/// Apple-Settings-style configuration view for the Montage host app.
/// All preferences persist immediately to the shared App Group `UserDefaults`
/// so the Share Extension reads them automatically.
struct ContentView: View {
  @StateObject private var settings = AppSettings()
  @State private var photoAuthStatus: PHAuthorizationStatus = Self.initialPhotoAuthStatus()
  @State private var isRequestingAccess = false

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL

  private static func initialPhotoAuthStatus() -> PHAuthorizationStatus {
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
      return .authorized
    } else {
      return PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
  }

  private var isRunningInPreviews: Bool {
    return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  private var photoAccessPresentation: PhotoAccessPresentation {
    PhotoAccessPresentation(status: photoAuthStatus)
  }

  var body: some View {
    CompatibleNavigationContainer {
      Form {
        introSection
        if photoAccessPresentation.needsFullAccessBanner {
          photoAccessSection
        }

        howItWorksSection
        transitionsSection
        hygieneSection
        uniformLengthSection
        aboutSection
        otherAppsSection
      }
      .navigationTitle(HostAppContent.navigationTitle)
      .navigationBarTitleDisplayMode(.large)
      .animation(
        AnimationCompatibility.shared.snappy(duration: 0.25),
        value: settings.autoTrimEnabled
      )
      .compatibleSensoryFeedback(.selection, trigger: settings.transitionStyle)
      .compatibleSensoryFeedback(.selection, trigger: settings.autoTrimInterval)
      .onAppear {
        refreshState()
      }
      .compatibleOnChange(of: scenePhase) { newPhase in
        if newPhase == .active {
          refreshState()
        }
      }
    }
  }

  // MARK: - Intro

  private var introSection: some View {
    Section {
    } header: {
      Text(HostAppContent.introText)
        .font(.subheadline)
        .fontWeight(.regular)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .fixedSize(horizontal: false, vertical: true)
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
  }

  // MARK: - Section 1: Photo Access Status

  private var photoAccessSection: some View {
    Section(HostAppContent.statusSectionTitle) {
      photoAccessStatusRow
      fullAccessBannerButton
    }
  }

  private var photoAccessStatusRow: some View {
    HStack(spacing: 12) {
      SettingIcon(
        systemImage: photoAccessPresentation.badgeSymbol,
        color: photoAccessPresentation.badgeColor
      )

      VStack(alignment: .leading, spacing: 2) {
        Text(photoAccessPresentation.title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(photoAccessPresentation.subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 4)
  }

  private var fullAccessBannerButton: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        handlePhotoAccessAction()
      } label: {
        HStack(spacing: 8) {
          if isRequestingAccess {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: photoAccessPresentation.actionButtonSymbol)
          }

          Text(HostAppContent.fullAccessButtonTitle)
            .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
      }
      .compatibleButtonStyle(.prominent)
      .disabled(isRequestingAccess)

      Text(HostAppContent.fullAccessExplanation)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Section 2: How It Works

  private var howItWorksSection: some View {
    Section(HostAppContent.howItWorksSectionTitle) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(HostAppContent.quickGuideSteps) { step in
          QuickGuideStepRow(
            symbolName: step.symbolName,
            text: step.text
          )
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Section 3: Transitions

  private var transitionsSection: some View {
    Section(HostAppContent.transitionsSectionTitle) {
      SettingPickerRow(
        title: HostAppContent.transitionStyleTitle,
        systemImage: "sparkles.rectangle.stack",
        selection: $settings.transitionStyle
      )
    }
  }

  // MARK: - Section 4: Photo Library Hygiene

  private var hygieneSection: some View {
    Section(HostAppContent.hygieneSectionTitle) {
      SettingToggleRow(
        title: HostAppContent.preserveMetadataTitle,
        description: HostAppContent.preserveMetadataDescription,
        systemImage: "calendar.badge.clock",
        color: .accentColor,
        isOn: $settings.preserveMetadata
      )

      SettingToggleRow(
        title: HostAppContent.sourceCleanupTitle,
        description: HostAppContent.sourceCleanupDescription,
        systemImage: "trash",
        color: .red,
        isOn: $settings.deleteSourceClipsAfterMerge
      )
    }
  }

  // MARK: - Section 5: Uniform Video Length

  private var uniformLengthSection: some View {
    Section(HostAppContent.uniformLengthSectionTitle) {
      SettingToggleRow(
        title: HostAppContent.autoTrimTitle,
        description: HostAppContent.autoTrimDescription,
        systemImage: "scissors",
        color: .accentColor,
        isOn: $settings.autoTrimEnabled
      )

      if settings.autoTrimEnabled {
        SettingPickerRow(
          title: HostAppContent.trimIntervalTitle,
          systemImage: "clock.arrow.2.circlepath",
          monospacedDigit: true,
          selection: $settings.autoTrimInterval
        )
      }
    }
  }

  // MARK: - Section 6: About

  private var aboutSection: some View {
    Section(HostAppContent.aboutSectionTitle) {
      NavigationLink {
        PrivacyPolicyView()
      } label: {
        Label {
          Text(HostAppContent.privacyPolicyTitle)
            .foregroundStyle(.primary)
        } icon: {
          SettingIcon(
            systemImage: SystemSymbolCompatibility.shared.privacyPolicy,
            color: .accentColor
          )
        }
      }

      CompatibleShareLink(
        item: HostAppContent.githubURL,
        message: HostAppContent.shareMontageMessage
      ) {
        Label {
          Text(HostAppContent.shareMontageTitle)
            .foregroundStyle(.primary)
        } icon: {
          SettingIcon(
            systemImage: "square.and.arrow.up",
            color: .accentColor
          )
        }
      }

      Link(destination: HostAppContent.issuesURL) {
        Label {
          Text(HostAppContent.reportBugTitle)
            .foregroundStyle(.primary)
        } icon: {
          SettingIcon(
            systemImage: "exclamationmark.circle",
            color: .accentColor
          )
        }
      }

      Button {
        openURL(HostAppContent.githubURL)
      } label: {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(HostAppContent.sourceCodeTitle)
              .font(.body)
            Text(HostAppContent.sourceCodeSubtitle)
              .font(.subheadline)
              .foregroundStyle(Color.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          SettingIcon(
            systemImage: "curlybraces.square",
            color: .accentColor
          )
        }
      }
    }
  }

  // MARK: - Section 7: Other Apps from the Developer

  private var otherAppsSection: some View {
    Section(HostAppContent.otherAppsSectionTitle) {
      OtherAppsView()
    }
  }

  // MARK: - Actions

  private func refreshState() {
    settings.reload()
    guard !isRunningInPreviews else {
      return
    }

    photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
  }

  private func handlePhotoAccessAction() {
    if photoAuthStatus == .notDetermined {
      isRequestingAccess = true
      Task {
        let updated = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photoAuthStatus = updated
        isRequestingAccess = false
      }
    } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
      openURL(settingsURL)
    }
  }
}

// MARK: - Setting Icon

/// Standalone SF Symbol icon tinted with the setting's semantic or accent color.
private struct SettingIcon: View {
  let systemImage: String
  let color: Color

  var body: some View {
    Image(systemName: systemImage)
      .font(.title3)
      .imageScale(.medium)
      .foregroundStyle(color)
      .frame(width: 28, height: 28)
      .accessibilityHidden(true)
  }
}

// MARK: - Setting Picker Row

private struct SettingPickerRow<Option: SettingOption>: View {
  let title: String
  let systemImage: String
  var color: Color = .accentColor
  var monospacedDigit: Bool = false
  @Binding var selection: Option

  var body: some View {
    Picker(selection: $selection) {
      ForEach(Array(Option.allCases)) { option in
        optionText(for: option)
          .tag(option)
      }
    } label: {
      Label {
        Text(title)
      } icon: {
        SettingIcon(
          systemImage: systemImage,
          color: color
        )
      }
    }
  }

  @ViewBuilder
  private func optionText(for option: Option) -> some View {
    if monospacedDigit {
      Text(option.displayName).monospacedDigit()
    } else {
      Text(option.displayName)
    }
  }
}

// MARK: - Setting Toggle Row

private struct SettingToggleRow: View {
  let title: String
  let description: String
  let systemImage: String
  let color: Color
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      SettingIcon(
        systemImage: systemImage,
        color: color
      )

      Toggle(isOn: $isOn) {
        Text(title)
        Text(description)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

// MARK: - Quick Guide Step Row

private struct QuickGuideStepRow: View {
  let symbolName: String
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbolName)
        .font(.callout)
        .foregroundStyle(Color.accentColor)
        .frame(width: 28)
        .accessibilityHidden(true)

      Text(text)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#Preview {
  ContentView()
}
