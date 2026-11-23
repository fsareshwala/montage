import SwiftUI
import UIKit

/// Focused, distraction-free Share Sheet UI for reordering and merging video clips.
/// Intentionally contains no settings controls — all preferences live in the host app.
struct ShareExtensionView: View {
  let extensionItems: [NSExtensionItem]
  let onCancel: () -> Void
  let onComplete: () -> Void

  @StateObject private var settings = AppSettings()
  @State private var clips: [ClipItem] = []
  @State private var isLoadingClips = true
  @State private var loadedCount = 0
  @State private var totalToLoad = 0

  @State private var mergePhase: MergePhase?
  @State private var errorMessage: String?
  @State private var reorderFeedbackTrigger = 0
  @State private var completionFeedbackTrigger = 0
  @State private var activeTask: Task<Void, Never>?

  private let engine = VideoMergeEngine()

  private var isMerging: Bool {
    guard let mergePhase else {
      return false
    }

    if mergePhase == .completed {
      return false
    } else {
      return true
    }
  }

  private var isCompleted: Bool {
    return mergePhase == .completed
  }

  private var configuration: MergeConfiguration {
    settings.makeConfiguration()
  }

  private var estimatedOutputDuration: TimeInterval {
    configuration.estimatedOutputDuration(for: clips.map(\.duration))
  }

  private var orientationAudit: ClipOrientationAudit? {
    ClipOrientationAudit(clips: clips)
  }

  private var hasOrientationMismatches: Bool {
    guard let orientationAudit else {
      return false
    }

    return orientationAudit.hasMismatches
  }

  private var clipCountLabel: String {
    if clips.count == 1 {
      return "\(clips.count) clip"
    } else {
      return "\(clips.count) clips"
    }
  }

  var body: some View {
    CompatibleNavigationContainer {
      Group {
        if isLoadingClips {
          loadingStateView
        } else if clips.isEmpty {
          emptyStateView
        } else {
          clipListView
        }
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Montage")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            cancelAndDismiss()
          }
          .disabled(isCompleted)
        }

        ToolbarItem(placement: ToolbarPlacementCompatibility.shared.topBarTrailing) {
          if !clips.isEmpty {
            summaryPill
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if !isLoadingClips && !clips.isEmpty {
          floatingBottomBar
        }
      }
    }
    .compatibleSensoryFeedback(.selection, trigger: reorderFeedbackTrigger)
    .compatibleSensoryFeedback(.success, trigger: completionFeedbackTrigger)
    .task {
      await loadSharedClips()
    }
    .onDisappear {
      activeTask?.cancel()
    }
  }

  // MARK: - Header Summary Pill

  private var summaryPill: some View {
    HStack(spacing: 5) {
      Text(clipCountLabel)
      Text("·")
        .foregroundStyle(.tertiary)
      Text(DurationFormatter.format(estimatedOutputDuration))
    }
    .font(.footnote.weight(.semibold))
    .monospacedDigit()
    .foregroundStyle(.secondary)
    .compatibleToolbarPill()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(clips.count) clips, total duration \(DurationFormatter.format(estimatedOutputDuration))"
    )
  }

  // MARK: - Loading and Empty States

  private var loadingStateView: some View {
    VStack(spacing: 14) {
      ProgressView()
        .controlSize(.large)

      Text(loadingProgressTitle)
        .font(.headline)
        .monospacedDigit()
        .foregroundStyle(.primary)

      Text("Preparing videos for quick reordering…")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  private var loadingProgressTitle: String {
    if totalToLoad > 0 {
      "Loading Clip \(loadedCount) of \(totalToLoad)…"
    } else {
      "Loading Clips…"
    }
  }

  private var emptyStateView: some View {
    CompatibleContentUnavailableView(
      title: "No Videos Found",
      systemImage: SystemSymbolCompatibility.shared.videoStack,
      description: errorMessage
        ?? "Select at least 2 videos from Photos to merge them into a single montage.",
      actionTitle: "Close",
      action: cancelAndDismiss
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Reorderable Clip List

  private var clipListView: some View {
    List {
      if let errorMessage {
        Section {
          HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 2)
        }
      }

      if let warningMessage = orientationAudit?.warningMessage {
        orientationWarningSection(message: warningMessage)
      }

      Section {
        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
          let isMismatched = isClipOrientationMismatched(clip)
          let showsReferenceOrientation = index == 0 && hasOrientationMismatches
          ClipRowView(
            orderIndex: index + 1,
            clip: clip,
            isOrientationMismatched: isMismatched,
            showsReferenceOrientation: showsReferenceOrientation
          )
          .moveDisabled(isMerging || isCompleted)
          .deleteDisabled(true)
          .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
          .listRowBackground(rowBackground(isMismatched: isMismatched))
        }
        .onMove(perform: moveClips)
      } header: {
        Text("Drag to Reorder")
      }
    }
    .listStyle(.insetGrouped)
    .environment(\.editMode, .constant(.active))
    .compatibleScrollDisabled(isMerging)
  }

  private func orientationWarningSection(message: String) -> some View {
    Section {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.orange)
          .padding(.top, 1)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text("Incompatible Orientations")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)

          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 2)
      .listRowBackground(Color.orange.opacity(0.10))
      .accessibilityElement(children: .combine)
    }
  }

  private func isClipOrientationMismatched(_ clip: ClipItem) -> Bool {
    guard let orientationAudit else {
      return false
    }

    return orientationAudit.isMismatched(clip)
  }

  private func rowBackground(isMismatched: Bool) -> Color? {
    if isMismatched {
      return Color.orange.opacity(0.10)
    } else {
      return nil
    }
  }

  // MARK: - Floating Bottom Action Bar

  private var floatingBottomBar: some View {
    Group {
      if isCompleted {
        completedContent
          .padding(16)
          .frame(maxWidth: .infinity)
          .compatibleFloatingBar(cornerRadius: 24)
      } else if let mergePhase {
        mergingProgressContent(phase: mergePhase)
          .padding(16)
          .frame(maxWidth: .infinity)
          .compatibleFloatingBar(cornerRadius: 24)
      } else {
        mergeActionButton
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
    .animation(AnimationCompatibility.shared.snappy(duration: 0.25), value: mergePhase)
  }

  private var mergeActionButton: some View {
    Button {
      startMerge()
    } label: {
      Label("Merge and Save", systemImage: SystemSymbolCompatibility.shared.videoStackFill)
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 50)
    }
    .compatibleButtonStyle(.prominent)
    .disabled(clips.count < 2)
  }

  private func mergingProgressContent(phase: MergePhase) -> some View {
    VStack(spacing: 10) {
      HStack {
        Text(phase.statusText)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)

        Spacer()

        Text("\(Int((phase.overallProgress * 100).rounded()))%")
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }

      ProgressView(value: phase.overallProgress, total: 1.0)
        .progressViewStyle(.linear)
        .tint(.accentColor)
    }
    .padding(.vertical, 6)
  }

  private var completedContent: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.title2)
        .foregroundStyle(.green)
        .compatibleSymbolBounce(value: completionFeedbackTrigger)

      Text("Saved to Photos")
        .font(.headline)
        .foregroundStyle(.primary)
    }
    .frame(maxWidth: .infinity, minHeight: 50)
  }

  // MARK: - Actions

  private func moveClips(from source: IndexSet, to destination: Int) {
    clips.move(fromOffsets: source, toOffset: destination)
    reorderFeedbackTrigger += 1
  }

  private func loadSharedClips() async {
    settings.reload()
    isLoadingClips = true
    errorMessage = nil

    do {
      let loaded = try await engine.loadClips(from: extensionItems) { current, total in
        Task { @MainActor in
          loadedCount = current
          totalToLoad = total
        }
      }
      clips = loaded
      if loaded.count < 2 {
        errorMessage = "Select at least 2 videos to merge into a montage."
      }
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoadingClips = false
  }

  private func startMerge() {
    guard clips.count >= 2, !isMerging, !isCompleted else {
      return
    }

    settings.reload()
    let currentClips = clips
    let config = settings.makeConfiguration()
    errorMessage = nil
    mergePhase = .preparing

    activeTask = Task {
      do {
        let result = try await engine.mergeAndSave(
          clips: currentClips,
          configuration: config
        ) { phase in
          Task { @MainActor in
            mergePhase = phase
          }
        }

        // Only prompt to delete source clips AFTER the merged montage is safely saved.
        if config.deleteSourceClipsAfterMerge, !result.sourceAssetIdentifiers.isEmpty {
          mergePhase = .cleaningUp
          _ = try? await engine.deleteSourceAssets(
            localIdentifiers: result.sourceAssetIdentifiers
          )
        }

        mergePhase = .completed
        completionFeedbackTrigger += 1

        try? await TaskSleepCompatibility.shared.sleep(milliseconds: 1100)
        engine.cleanupTemporaryFiles(for: currentClips)
        onComplete()
      } catch is CancellationError {
        mergePhase = nil
      } catch VideoMergeError.cancelled {
        mergePhase = nil
      } catch {
        mergePhase = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  private func cancelAndDismiss() {
    activeTask?.cancel()
    engine.cleanupTemporaryFiles(for: clips)
    onCancel()
  }
}

// MARK: - Clip Row

private struct ClipRowView: View {
  let orderIndex: Int
  let clip: ClipItem
  let isOrientationMismatched: Bool
  let showsReferenceOrientation: Bool

  private var orderBadgeForeground: Color {
    if isOrientationMismatched {
      return .orange
    } else {
      return .secondary
    }
  }

  private var orderBadgeBackground: Color {
    if isOrientationMismatched {
      return Color.orange.opacity(0.18)
    } else {
      return Color(.tertiarySystemFill)
    }
  }

  private var thumbnailBorderColor: Color {
    if isOrientationMismatched {
      return Color.orange.opacity(0.85)
    } else {
      return Color(.separator).opacity(0.35)
    }
  }

  private var thumbnailBorderWidth: CGFloat {
    if isOrientationMismatched {
      return 1.5
    } else {
      return 0.5
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      // Order badge (1, 2, 3...)
      Text("\(orderIndex)")
        .font(.footnote.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(orderBadgeForeground)
        .frame(width: 24, height: 24)
        .background(
          Circle()
            .fill(orderBadgeBackground)
        )

      // Crisp 16:9 thumbnail (80x45pt, continuous 8pt corner radius)
      thumbnailView
        .frame(width: 80, height: 45)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(thumbnailBorderColor, lineWidth: thumbnailBorderWidth)
        )

      // Duration, optional capture time, and orientation indicator when clips have mixed orientations
      VStack(alignment: .leading, spacing: 3) {
        Text(clip.formattedDuration)
          .font(.headline)
          .monospacedDigit()
          .foregroundStyle(.primary)

        if let captureTime = clip.formattedCaptureTime {
          Text(captureTime)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if isOrientationMismatched, let orientation = clip.orientation {
          HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.caption2)
            Text(orientation.displayName)
              .font(.caption.weight(.semibold))
          }
          .foregroundStyle(.orange)
        } else if showsReferenceOrientation, let orientation = clip.orientation {
          HStack(spacing: 4) {
            Image(systemName: orientation.symbolName)
              .font(.caption2)
            Text(orientation.displayName)
              .font(.caption)
          }
          .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 4)
    }
    .frame(minHeight: 48)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowAccessibilityLabel)
  }

  @ViewBuilder
  private var thumbnailView: some View {
    if let image = clip.thumbnail {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color(.secondarySystemFill)
        Image(systemName: "video.fill")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var rowAccessibilityLabel: String {
    var parts = [
      "Clip \(orderIndex)",
      "duration \(clip.formattedDuration)",
    ]
    if let captureTime = clip.formattedCaptureTime {
      parts.append("recorded at \(captureTime)")
    }

    if isOrientationMismatched, let orientation = clip.orientation {
      parts.append("\(orientation.displayName), different orientation from first clip")
    } else if showsReferenceOrientation, let orientation = clip.orientation {
      parts.append("\(orientation.displayName), sets output orientation")
    }

    return parts.joined(separator: ", ")
  }
}
