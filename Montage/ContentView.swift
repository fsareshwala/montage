import Photos
import SwiftUI
import UIKit

/// Apple-Settings-style configuration view for the Montage host app.
/// All preferences persist immediately to the shared App Group `UserDefaults`
/// so the Share Extension reads them automatically.
struct ContentView: View {
  @StateObject private var settings = AppSettings()
  @State private var photoAuthStatus: PHAuthorizationStatus = .notDetermined
  @State private var isRequestingAccess = false

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL

  private var isRunningInPreviews: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  var body: some View {
    CompatibleNavigationContainer {
      Form {
        photoAccessSection
        howItWorksSection
        transitionsSection
        hygieneSection
        uniformLengthSection
        aboutSection
        otherAppsSection
      }
      .navigationTitle("Montage")
      .navigationBarTitleDisplayMode(.large)
      .animation(
        AnimationCompatibility.shared.snappy(duration: 0.25),
        value: settings.transitionStyle
      )
      .animation(
        AnimationCompatibility.shared.snappy(duration: 0.25),
        value: settings.autoTrimEnabled
      )
      .compatibleSensoryFeedback(.selection, trigger: settings.transitionStyle)
      .compatibleSensoryFeedback(.selection, trigger: settings.transitionDuration)
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

  // MARK: - Section 1: Photo Access Status

  private var photoAccessSection: some View {
    Section("Status") {
      photoAccessStatusRow

      if needsFullAccessBanner {
        fullAccessBannerButton
      }
    }
  }

  private var needsFullAccessBanner: Bool {
    switch photoAuthStatus {
    case .notDetermined, .limited, .denied, .restricted:
      true
    case .authorized:
      false
    @unknown default:
      true
    }
  }

  private var photoAccessStatusRow: some View {
    HStack(spacing: 12) {
      SettingIcon(
        systemImage: statusBadgeSymbol,
        color: statusBadgeColor
      )

      VStack(alignment: .leading, spacing: 2) {
        Text(statusTitle)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(statusSubtitle)
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
            Image(
              systemName: photoAuthStatus == .notDetermined
                ? SystemSymbolCompatibility.shared.photoAccessRequest : "gearshape"
            )
          }
          Text("Enable Full Photo Access")
            .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
      }
      .compatibleButtonStyle(.prominent)
      .disabled(isRequestingAccess)

      Text(
        "Full Photo Library access lets Montage copy the original date and GPS location onto your montage and optionally clean up individual source clips."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Section 2: How It Works

  private var howItWorksSection: some View {
    Section("How It Works") {
      VStack(alignment: .leading, spacing: 10) {
        QuickGuideStepRow(
          symbolName: SystemSymbolCompatibility.shared.photoStack,
          text: "Select 2 or more clips in Photos"
        )
        QuickGuideStepRow(
          symbolName: "square.and.arrow.up",
          text: "Tap Share and pick Montage"
        )
        QuickGuideStepRow(
          symbolName: "arrow.up.arrow.down.circle",
          text: "Reorder and Merge into one video"
        )
      }
      .padding(.vertical, 4)
    }
  }

  private var statusBadgeSymbol: String {
    switch photoAuthStatus {
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

  private var statusBadgeColor: Color {
    switch photoAuthStatus {
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

  private var statusTitle: String {
    switch photoAuthStatus {
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

  private var statusSubtitle: String {
    switch photoAuthStatus {
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

  // MARK: - Section 3: Transitions

  private var transitionsSection: some View {
    Section("Transitions") {
      SettingPickerRow(
        title: "Transition Style",
        systemImage: "sparkles.rectangle.stack",
        selection: $settings.transitionStyle
      )

      if settings.transitionStyle != .none {
        SettingPickerRow(
          title: "Transition Duration",
          systemImage: "timer",
          monospacedDigit: true,
          selection: $settings.transitionDuration
        )
      }
    }
  }

  // MARK: - Section 4: Photo Library Hygiene

  private var hygieneSection: some View {
    Section("Photo Library Hygiene") {
      SettingToggleRow(
        title: "Preserve Metadata",
        description:
          "Copy the capture date, time, and GPS location from the first clip onto the merged video.",
        systemImage: "calendar.badge.clock",
        color: .accentColor,
        isOn: $settings.preserveMetadata
      )

      SettingToggleRow(
        title: "Post-Merge Source Cleanup",
        description:
          "Prompt to delete the individual source clips from Photos after the merged montage is saved.",
        systemImage: "trash",
        color: .red,
        isOn: $settings.deleteSourceClipsAfterMerge
      )
    }
  }

  // MARK: - Section 5: Uniform Video Length

  private var uniformLengthSection: some View {
    Section("Uniform Video Length") {
      SettingToggleRow(
        title: "Auto-Trim to Fixed Intervals",
        description: autoTrimDescriptionText,
        systemImage: "scissors",
        color: .accentColor,
        isOn: $settings.autoTrimEnabled
      )

      if settings.autoTrimEnabled {
        SettingPickerRow(
          title: "Trim Interval",
          systemImage: "clock.arrow.2.circlepath",
          monospacedDigit: true,
          selection: $settings.autoTrimInterval
        )
      }
    }
  }

  private var autoTrimDescriptionText: String {
    return
      "Trim merged video down to the nearest fixed interval. Footage past the last completed interval is trimmed off. Videos shorter than one interval are untouched."
  }

  // MARK: - Section 6: About

  private static let githubURL = URL(string: "https://github.com/fsareshwala/montage")!
  private static let issuesURL = URL(string: "https://github.com/fsareshwala/montage/issues")!

  private var aboutSection: some View {
    Section("About") {
      NavigationLink {
        PrivacyPolicyView()
      } label: {
        Label {
          Text("Privacy Policy")
            .foregroundStyle(.primary)
        } icon: {
          SettingIcon(
            systemImage: SystemSymbolCompatibility.shared.privacyPolicy,
            color: .accentColor
          )
        }
      }

      CompatibleShareLink(
        item: Self.githubURL,
        message: "Check out Montage, the easiest way to merge clips from Photos!"
      ) {
        Label {
          Text("Share Montage")
            .foregroundStyle(.primary)
        } icon: {
          SettingIcon(
            systemImage: "square.and.arrow.up",
            color: .accentColor
          )
        }
      }

      Link(destination: Self.issuesURL) {
        Label {
          Text("Report a Bug")
            .foregroundStyle(.primary)
        } icon: {
          SettingIcon(
            systemImage: "exclamationmark.circle",
            color: .accentColor
          )
        }
      }

      Link(destination: Self.githubURL) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("Source Code")
              .font(.body)
              .foregroundStyle(.primary)
            Text("This app is fully open source. You can read the code on GitHub.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
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
    Section("Other Apps from the Developer") {
      OtherAppsView()
    }
  }

  // MARK: - Actions

  private func refreshState() {
    settings.reload()
    guard !isRunningInPreviews else { return }
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
