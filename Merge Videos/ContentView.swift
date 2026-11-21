import Photos
import SwiftUI
import UIKit

/// Apple-Settings-style configuration view for the Merge Videos host app.
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
    NavigationStack {
      Form {
        statusAndGuideSection
        transitionsSection
        hygieneSection
        uniformLengthSection
      }
      .navigationTitle("Merge Videos")
      .navigationBarTitleDisplayMode(.large)
      .animation(.snappy(duration: 0.25), value: settings.transitionStyle)
      .animation(.snappy(duration: 0.25), value: settings.autoTrimEnabled)
      .sensoryFeedback(.selection, trigger: settings.transitionStyle)
      .sensoryFeedback(.selection, trigger: settings.transitionDuration)
      .sensoryFeedback(.selection, trigger: settings.autoTrimInterval)
      .onAppear {
        refreshState()
      }
      .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active {
          refreshState()
        }
      }
    }
  }

  // MARK: - Section 1: Status and Quick Guide Card

  private var statusAndGuideSection: some View {
    Section {
      photoAccessStatusRow

      if needsFullAccessBanner {
        fullAccessBannerButton
      }

      quickGuideView
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
      SettingIconBadge(
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
      Text(
        "Full Photo Library access lets Merge Videos copy the original date and GPS location onto your montage and optionally clean up individual source clips."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

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
                ? "photo.badge.checkmark" : "gearshape.fill")
          }
          Text("Enable Full Photo Access")
            .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.roundedRectangle(radius: 12))
      .disabled(isRequestingAccess)
    }
    .padding(.vertical, 4)
  }

  private var quickGuideView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("How It Works")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 10) {
        QuickGuideStepRow(
          stepNumber: 1,
          symbolName: "photo.stack.fill",
          tint: .blue,
          text: "Select 2 or more clips in Photos"
        )
        QuickGuideStepRow(
          stepNumber: 2,
          symbolName: "square.and.arrow.up",
          tint: .indigo,
          text: "Tap Share and pick Merge Videos"
        )
        QuickGuideStepRow(
          stepNumber: 3,
          symbolName: "arrow.up.arrow.down.circle.fill",
          tint: .green,
          text: "Reorder and Merge into one video"
        )
      }
    }
    .padding(.vertical, 4)
  }

  private var statusBadgeSymbol: String {
    switch photoAuthStatus {
    case .authorized:
      "checkmark.circle.fill"
    case .limited:
      "exclamationmark.triangle.fill"
    case .notDetermined:
      "photo.on.rectangle.angled"
    case .denied, .restricted:
      "lock.fill"
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
      .blue
    case .denied, .restricted:
      .red
    @unknown default:
      .blue
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
      "Grant access so Merge Videos can save merged videos back to your library."
    case .denied:
      "Open iOS Settings to grant Merge Videos access to your Photo Library."
    case .restricted:
      "Photo Library access is restricted on this device."
    @unknown default:
      "Grant Photo Library access to use Merge Videos."
    }
  }

  // MARK: - Section 2: Transitions

  private var transitionsSection: some View {
    Section("Transitions") {
      Picker(selection: $settings.transitionStyle) {
        ForEach(TransitionStyle.allCases) { style in
          Text(style.displayName).tag(style)
        }
      } label: {
        Label {
          Text("Transition Style")
        } icon: {
          SettingIconBadge(
            systemImage: "sparkles.rectangle.stack.fill",
            color: .indigo
          )
        }
      }
      .frame(minHeight: 44)

      if settings.transitionStyle != .none {
        VStack(alignment: .leading, spacing: 10) {
          Label {
            Text("Transition Duration")
          } icon: {
            SettingIconBadge(
              systemImage: "timer",
              color: .teal
            )
          }

          Picker("Transition Duration", selection: $settings.transitionDuration) {
            ForEach(TransitionDuration.allCases) { duration in
              Text(duration.displayName)
                .monospacedDigit()
                .tag(duration)
            }
          }
          .pickerStyle(.segmented)
          .frame(minHeight: 36)
        }
        .padding(.vertical, 4)
      }
    }
  }

  // MARK: - Section 3: Photo Library Hygiene

  private var hygieneSection: some View {
    Section("Photo Library Hygiene") {
      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: $settings.preserveMetadata) {
          Label {
            Text("Keep Original Date and Location")
          } icon: {
            SettingIconBadge(
              systemImage: "calendar.badge.clock",
              color: .blue
            )
          }
        }
        .frame(minHeight: 44)

        Text(
          "Copies the capture date, time, and GPS location from the first clip onto the merged video so it stays in chronological order in your library."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 2)

      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: $settings.deleteSourceClipsAfterMerge) {
          Label {
            Text("Post-Merge Source Cleanup")
          } icon: {
            SettingIconBadge(
              systemImage: "trash.fill",
              color: .red
            )
          }
        }
        .frame(minHeight: 44)

        Text(
          "Prompts you to delete the individual source clips from Photos right after the merged montage is safely saved."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 2)
    }
  }

  // MARK: - Section 4: Uniform Video Length

  private var uniformLengthSection: some View {
    Section {
      Toggle(isOn: $settings.autoTrimEnabled) {
        Label {
          Text("Auto-Trim to Fixed Intervals")
        } icon: {
          SettingIconBadge(
            systemImage: "scissors",
            color: .purple
          )
        }
      }
      .frame(minHeight: 44)

      if settings.autoTrimEnabled {
        Picker(selection: $settings.autoTrimInterval) {
          ForEach(TrimInterval.allCases) { interval in
            Text(interval.displayName)
              .monospacedDigit()
              .tag(interval)
          }
        } label: {
          Label {
            Text("Trim Interval")
          } icon: {
            SettingIconBadge(
              systemImage: "clock.arrow.2.circlepath",
              color: .purple
            )
          }
        }
        .frame(minHeight: 44)
      }
    } header: {
      Text("Uniform Video Length")
    } footer: {
      Text(autoTrimFooterText)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var autoTrimFooterText: String {
    switch settings.autoTrimInterval {
    case .thirtySeconds:
      "Automatically trims the end of the merged video down to the nearest 30-second mark (0:30, 1:00, 1:30, 2:00, etc.) so your montages have uniform lengths in your library. Footage past the last completed interval is trimmed off; videos under 30 seconds are untouched."
    case .oneMinute:
      "Automatically trims the end of the merged video down to the nearest 1-minute mark (1:00, 2:00, 3:00, etc.) so your montages have uniform lengths in your library. Footage past the last completed interval is trimmed off; videos under 1 minute are untouched."
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

// MARK: - Apple-Style Setting Icon Badge

/// 28x28pt rounded-square SF Symbol icon badge styled after Apple's iOS Settings app.
private struct SettingIconBadge: View {
  let systemImage: String
  let color: Color

  var body: some View {
    Image(systemName: systemImage)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 28, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(color.gradient)
      )
      .accessibilityHidden(true)
  }
}

// MARK: - Quick Guide Step Row

private struct QuickGuideStepRow: View {
  let stepNumber: Int
  let symbolName: String
  let tint: Color
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Text("\(stepNumber)")
        .font(.caption.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(tint)
        .frame(width: 22, height: 22)
        .background(
          Circle()
            .fill(tint.opacity(0.14))
        )

      Image(systemName: symbolName)
        .font(.subheadline)
        .foregroundStyle(tint)
        .frame(width: 20)
        .accessibilityHidden(true)

      Text(text)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#Preview {
  ContentView()
}
