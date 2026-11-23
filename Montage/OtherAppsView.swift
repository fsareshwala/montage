import SwiftUI

/// Metadata describing another app published by the developer.
struct DeveloperAppInfo: Identifiable {
  let id: String
  let iconName: String
  let appName: String
  let description: String
  let appStoreURL: URL
}

/// Showcases other apps from the developer inside the host app's Form.
struct OtherAppsView: View {
  @Environment(\.openURL) private var openURL

  static let apps: [DeveloperAppInfo] = [
    DeveloperAppInfo(
      id: "forecash",
      iconName: "forecash",
      appName: "Forecash",
      description:
        "Plan bill pay dates, forecast your finances. Project future balances so you can plan ahead.",
      appStoreURL: URL(string: "https://apps.apple.com/us/app/forecash-bill-planner/id6747775439")!
    ),
    DeveloperAppInfo(
      id: "cleandial",
      iconName: "cleandial",
      appName: "Clean Dial",
      description:
        "Format contact phone numbers into clean, consistent international or national formats.",
      appStoreURL: URL(string: "https://apps.apple.com/us/app/clean-dial/id6745625133")!
    ),
  ]

  var body: some View {
    ForEach(Self.apps) { app in
      Button {
        openURL(app.appStoreURL)
      } label: {
        HStack(spacing: 15) {
          Image(app.iconName)
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

          VStack(alignment: .leading, spacing: 4) {
            Text(app.appName)
              .font(.headline)

            Text(app.description)
              .font(.caption)
              .foregroundStyle(Color.secondary)
              .lineLimit(2)
          }
        }
      }
    }
  }
}

#Preview {
  Form {
    Section("Other Apps from the Developer") {
      OtherAppsView()
    }
  }
}
