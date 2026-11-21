import SwiftUI
import UIKit

// MARK: - Haptic / Sensory Feedback Compatibility

/// Unified haptic feedback styles exposed across iOS 15 through iOS 27+.
public nonisolated enum CompatibleFeedbackStyle: Sendable {
  case selection
  case success
}

/// Single-API haptic feedback controller backing iOS 15–16 fallbacks for `sensoryFeedback`.
@MainActor
public final class HapticFeedbackController {
  public static let shared = HapticFeedbackController()

  private let selectionGenerator = UISelectionFeedbackGenerator()
  private let notificationGenerator = UINotificationFeedbackGenerator()

  public init() {}

  public func trigger(_ style: CompatibleFeedbackStyle) {
    switch style {
    case .selection:
      selectionGenerator.selectionChanged()
    case .success:
      notificationGenerator.notificationOccurred(.success)
    }
  }
}

// MARK: - SF Symbol Compatibility

/// Single-API lookup for SF Symbols with guaranteed iOS 15 fallbacks.
public nonisolated final class SystemSymbolCompatibility: Sendable {
  public static let shared = SystemSymbolCompatibility()

  public init() {}

  public var photoAccessRequest: String {
    if #available(iOS 17, *) {
      "photo.badge.checkmark"
    } else {
      "checkmark.circle"
    }
  }

  public var photoStack: String {
    if #available(iOS 16, *) {
      "photo.stack"
    } else {
      "photo.on.rectangle.angled"
    }
  }

  public var videoStack: String {
    if #available(iOS 16, *) {
      "film.stack"
    } else {
      "film"
    }
  }

  public var videoStackFill: String {
    if #available(iOS 16, *) {
      "film.stack.fill"
    } else {
      "film.fill"
    }
  }
}

// MARK: - Animation and Toolbar Placement Compatibility

/// Single-API animation helpers hiding iOS 17+ preset availability.
public nonisolated final class AnimationCompatibility: Sendable {
  public static let shared = AnimationCompatibility()

  public init() {}

  public func snappy(duration: TimeInterval = 0.25) -> Animation {
    if #available(iOS 17, *) {
      .snappy(duration: duration)
    } else {
      .spring(response: duration, dampingFraction: 0.85)
    }
  }
}

/// Single-API toolbar placement helpers hiding iOS 17+ placement names.
public nonisolated final class ToolbarPlacementCompatibility: Sendable {
  public static let shared = ToolbarPlacementCompatibility()

  public init() {}

  public var topBarTrailing: ToolbarItemPlacement {
    if #available(iOS 17, *) {
      .topBarTrailing
    } else {
      .navigationBarTrailing
    }
  }
}

// MARK: - Navigation Container Compatibility

/// Uses `NavigationStack` on iOS 16+ and falls back to stack-styled `NavigationView` on iOS 15.
public struct CompatibleNavigationContainer<Content: View>: View {
  private let content: () -> Content

  public init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  public var body: some View {
    if #available(iOS 16, *) {
      NavigationStack {
        content()
      }
    } else {
      NavigationView {
        content()
      }
      .navigationViewStyle(.stack)
    }
  }
}

// MARK: - Content Unavailable Compatibility

/// Uses native `ContentUnavailableView` on iOS 17+ and a visually matched fallback on iOS 15–16.
public struct CompatibleContentUnavailableView: View {
  private let title: String
  private let systemImage: String
  private let description: String
  private let actionTitle: String
  private let action: () -> Void

  public init(
    title: String,
    systemImage: String,
    description: String,
    actionTitle: String,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.description = description
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    if #available(iOS 17, *) {
      ContentUnavailableView {
        Label(title, systemImage: systemImage)
      } description: {
        Text(description)
      } actions: {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .frame(minHeight: 44)
      }
    } else {
      VStack(spacing: 14) {
        Image(systemName: systemImage)
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        Text(title)
          .font(.title2.weight(.bold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)

        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .frame(minHeight: 44)
          .padding(.top, 4)
      }
      .padding(24)
    }
  }
}

// MARK: - Gradient Badge Background Compatibility

/// Renders a rounded badge background using `Color.gradient` on iOS 16+ and a subtle
/// `LinearGradient` fallback on iOS 15.
public struct CompatibleGradientBadgeBackground: View {
  private let color: Color
  private let cornerRadius: CGFloat

  public init(color: Color, cornerRadius: CGFloat = 6) {
    self.color = color
    self.cornerRadius = cornerRadius
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(iOS 16, *) {
      shape.fill(color.gradient)
    } else {
      shape.fill(
        LinearGradient(
          colors: [color.opacity(0.85), color],
          startPoint: .top,
          endPoint: .bottom
        )
      )
    }
  }
}

// MARK: - View Modifier Compatibility Extensions

public extension View {
  /// Uses SwiftUI's `sensoryFeedback` on iOS 17+ and UIKit feedback generators on iOS 15–16.
  func compatibleSensoryFeedback<Trigger: Equatable>(
    _ style: CompatibleFeedbackStyle,
    trigger: Trigger
  ) -> some View {
    modifier(CompatibleSensoryFeedbackModifier(style: style, trigger: trigger))
  }

  /// Uses the two-parameter `onChange(of:)` on iOS 17+ and the single-parameter form on iOS 15–16.
  func compatibleOnChange<Value: Equatable>(
    of value: Value,
    perform action: @escaping (Value) -> Void
  ) -> some View {
    modifier(CompatibleOnChangeModifier(value: value, action: action))
  }

  /// Applies `.scrollDisabled` on iOS 16+ and leaves scrolling unmodified on iOS 15.
  func compatibleScrollDisabled(_ disabled: Bool) -> some View {
    modifier(CompatibleScrollDisabledModifier(disabled: disabled))
  }

  /// Applies `.symbolEffect(.bounce, value:)` on iOS 17+ and a spring scale bounce on iOS 15–16.
  func compatibleSymbolBounce<Value: Equatable>(value: Value) -> some View {
    modifier(CompatibleSymbolBounceModifier(value: value))
  }

  /// Applies iOS 26+ Liquid Glass (`glassEffect`) with an `.ultraThinMaterial` fallback on iOS 15–25.
  func compatibleFloatingBar(cornerRadius: CGFloat = 24) -> some View {
    modifier(CompatibleFloatingBarModifier(cornerRadius: cornerRadius))
  }
}

// MARK: - Private Modifier Implementations

private struct CompatibleSensoryFeedbackModifier<Trigger: Equatable>: ViewModifier {
  let style: CompatibleFeedbackStyle
  let trigger: Trigger

  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      switch style {
      case .selection:
        content.sensoryFeedback(.selection, trigger: trigger)
      case .success:
        content.sensoryFeedback(.success, trigger: trigger)
      }
    } else {
      content.compatibleOnChange(of: trigger) { _ in
        HapticFeedbackController.shared.trigger(style)
      }
    }
  }
}

private struct CompatibleOnChangeModifier<Value: Equatable>: ViewModifier {
  let value: Value
  let action: (Value) -> Void

  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.onChange(of: value) { _, newValue in
        action(newValue)
      }
    } else {
      content.onChange(of: value, perform: action)
    }
  }
}

private struct CompatibleScrollDisabledModifier: ViewModifier {
  let disabled: Bool

  func body(content: Content) -> some View {
    if #available(iOS 16, *) {
      content.scrollDisabled(disabled)
    } else {
      content
    }
  }
}

private struct CompatibleSymbolBounceModifier<Value: Equatable>: ViewModifier {
  let value: Value
  @State private var isPulsing = false

  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.symbolEffect(.bounce, value: value)
    } else {
      content
        .scaleEffect(isPulsing ? 1.18 : 1.0)
        .animation(AnimationCompatibility.shared.snappy(duration: 0.25), value: isPulsing)
        .compatibleOnChange(of: value) { _ in
          isPulsing = true
          Task { @MainActor in
            try? await TaskSleepCompatibility.shared.sleep(milliseconds: 180)
            isPulsing = false
          }
        }
    }
  }
}

private struct CompatibleFloatingBarModifier: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(iOS 26, *) {
      content
        .glassEffect(.regular, in: shape)
    } else {
      content
        .background(.ultraThinMaterial, in: shape)
        .overlay(
          shape
            .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
  }
}
