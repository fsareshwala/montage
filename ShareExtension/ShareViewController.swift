import SwiftUI
import UIKit

/// Root view controller for the Montage Share Extension.
/// Embeds the SwiftUI `ShareExtensionView` full-bleed inside the extension container.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .clear

    let inputItems = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

    let rootView = ShareExtensionView(
      extensionItems: inputItems,
      onCancel: { [weak self] in
        self?.dismissExtension(cancelled: true)
      },
      onComplete: { [weak self] in
        self?.dismissExtension(cancelled: false)
      }
    )

    let hostingController = UIHostingController(rootView: rootView)
    hostingController.view.backgroundColor = .clear
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false

    addChild(hostingController)
    view.addSubview(hostingController.view)
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    hostingController.didMove(toParent: self)
  }

  private func dismissExtension(cancelled: Bool) {
    if cancelled {
      let error = NSError(
        domain: NSCocoaErrorDomain,
        code: NSUserCancelledError,
        userInfo: nil
      )
      extensionContext?.cancelRequest(withError: error)
    } else {
      extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }
}
