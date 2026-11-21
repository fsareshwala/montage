import SwiftUI

/// Displays the Montage privacy policy describing on-device processing and open-source transparency.
struct PrivacyPolicyView: View {
  var body: some View {
    ScrollView {
      Text(
        """
        **Effective Date:** November 21, 2026

        Your privacy is our priority. Montage is designed to combine your video clips locally on your device. Your personal videos, photos, capture dates, and GPS locations are never collected, stored remotely, or shared.

        **1. Local Processing**
        All video merging, transitions, orientation normalization, auto-trimming, and metadata preservation happen entirely on your device. None of your media or metadata is ever uploaded to a server or shared with third parties.

        **2. Photo Library Access**
        Photo Library access is used solely to read capture dates and GPS locations from your selected clips, save merged videos back to your library, and optionally prompt you to clean up the original source clips when enabled.

        **3. Open Source**
        To ensure total transparency, this app is fully open source. You can review its source code to verify these privacy claims and see exactly how your data is handled at: https://github.com/fsareshwala/montage.

        **4. No Data Collection or Third-Party Tracking**
        Montage does not collect personal information, usage analytics, or crash telemetry, and does not include third-party analytics or advertising SDKs.

        **5. Changes to This Policy**
        This policy may be updated from time to time. Any changes will be reflected by the "Effective Date" at the top of this page.
        """
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .navigationTitle("Privacy Policy")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  CompatibleNavigationContainer {
    PrivacyPolicyView()
  }
}
