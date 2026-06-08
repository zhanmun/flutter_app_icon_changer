import Flutter
import Foundation
import UIKit

public class FlutterAppIconChangerPlugin: NSObject, FlutterPlugin {
  private var availableIcons: [AppIcon] = []
  private var pendingIconName: String? = nil

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_app_icon_changer", binaryMessenger: registrar.messenger())
    let instance = FlutterAppIconChangerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "changeIcon":
      if let args = call.arguments as? [String: Any], let iconName = args["iconName"] as? String {
        self.changeIcon(to: iconName, result: result)
      } else {
        result(FlutterError.invalidArgs("Arguments are invalid"))
      }
    case "getCurrentIcon":
        let currentIcon = self.getCurrentIcon()
        result(currentIcon)
    case "isSupported":
        let isSupported = self.isSupported()
        result(isSupported)
    case "setAvailableIcons":
        if let args = call.arguments as? [String: Any], let iconsArray = args["icons"] as? [[String: Any]] {
            self.setAvailableIcons(iconsArray)
            result(nil)
        } else {
            result(FlutterError.invalidArgs("Arguments is invalid"))
        }

    case "scheduleIconChange":
        if let args = call.arguments as? [String: Any], let iconName = args["iconName"] as? String {
            self.scheduleIconChange(to: iconName, result: result)
        } else {
            result(FlutterError.invalidArgs("Arguments are invalid"))
        }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func changeIcon(to iconName: String?, result: @escaping FlutterResult) {
      guard UIApplication.shared.supportsAlternateIcons else {
          print("Changing the icon is not supported on this device.")
          result(FlutterError.iconChangeNotSupported())
          return
      }

      var defaultIcon: String? = nil

      guard let iconName = iconName else {
        setIcon(icon: defaultIcon, result: result)
        return
      }

      if let iconToChange = availableIcons.first(where: { $0.icon == iconName }) {
          if iconToChange.isDefaultIcon {
              setIcon(icon: defaultIcon, result: result)
          } else {
              setIcon(icon: iconToChange.icon, result: result)
          }
      } else {
          setIcon(icon: defaultIcon, result: result)
          result(FlutterError.iconNotFound("Icon \(iconName) not found"))
      }
  }

  // Stores the target icon and applies it silently when the app enters background.
  // The public setAlternateIconName cannot show a dialog when the app has no
  // active view hierarchy, so the change happens with no user-facing popup.
  private func scheduleIconChange(to iconName: String, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(FlutterError.iconChangeNotSupported())
      return
    }

    // Resolve to nil for default icon, or the actual icon name otherwise
    if let iconToChange = availableIcons.first(where: { $0.icon == iconName }) {
      pendingIconName = iconToChange.isDefaultIcon ? nil : iconToChange.icon
    } else {
      pendingIconName = nil
    }

    NotificationCenter.default.removeObserver(
      self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(applyPendingIconInBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)

    result(true)
  }

  @objc private func applyPendingIconInBackground() {
    NotificationCenter.default.removeObserver(
      self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    let target = pendingIconName
    pendingIconName = nil
    UIApplication.shared.setAlternateIconName(target) { error in
      if let error = error {
        print("[IconChanger] Background change error: \(error.localizedDescription)")
      } else {
        print("[IconChanger] Icon changed silently in background.")
      }
    }
  }

  private func setIcon(icon iconName: String?, result: @escaping FlutterResult) {
    // Find the topmost visible view controller to present on
    guard let keyWindow = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow }),
      let rootVC = keyWindow.rootViewController else {
        result(FlutterError.iconChangeFailed("No root view controller"))
        return
    }

    var topVC = rootVC
    while let presented = topVC.presentedViewController {
      topVC = presented
    }

    // Present a blank opaque VC with a zero-duration custom transition.
    // setAlternateIconName is called inside the presentation completion, so
    // the system alert (if shown) appears on top of the blank VC and is
    // dismissed along with it before the user can read it.
    let blankVC = UIViewController()
    blankVC.view.backgroundColor = topVC.view.backgroundColor ?? .systemBackground
    blankVC.modalPresentationStyle = .custom
    blankVC.transitioningDelegate = SilentTransitionDelegate.shared

    topVC.present(blankVC, animated: false) {
      UIApplication.shared.setAlternateIconName(iconName) { error in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          blankVC.dismiss(animated: false) {
            if let error = error {
              print("[IconChanger] Error: \(error.localizedDescription)")
              result(FlutterError.iconChangeFailed(error.localizedDescription))
            } else {
              print("[IconChanger] Icon changed silently via blank VC overlay.")
              result(true)
            }
          }
        }
      }
    }
  }

  private func getCurrentIcon() -> String? {
      if let alternateIconName = UIApplication.shared.alternateIconName {
          return alternateIconName
      } else {
          return nil
      }
  }

  private func isSupported() -> Bool {
    return UIApplication.shared.supportsAlternateIcons
  }

  private func setAvailableIcons(_ iconsArray: [[String: Any]]) {
    availableIcons = iconsArray.compactMap { AppIcon(from: $0) }
  }
}

struct AppIcon {
    let icon: String
    let isDefaultIcon: Bool

    init?(from dictionary: [String: Any]) {
        guard let icon = dictionary["icon"] as? String,
              let isDefaultIcon = dictionary["isDefaultIcon"] as? Bool else {
            return nil
        }
        self.icon = icon
        self.isDefaultIcon = isDefaultIcon
    }

    var description: String {
        return "AppIcon(icon: \(icon), isDefaultIcon: \(isDefaultIcon))"
    }
}

// Zero-duration animator so the blank VC appears and disappears instantly,
// giving the system alert no time window to render visibly to the user.
private class SilentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
  func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
    return 0
  }
  func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
    transitionContext.completeTransition(true)
  }
}

private class SilentTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
  static let shared = SilentTransitionDelegate()
  func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    return SilentAnimator()
  }
  func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    return SilentAnimator()
  }
}

extension FlutterError {
    static func invalidArgs(_ message: String, details: Any? = nil) -> FlutterError {
        return FlutterError(code: "INVALID_ARGS", message: message, details: details);
    }

    static func iconChangeNotSupported() -> FlutterError {
        return FlutterError(code: "IS_NOT_SUPPORTED", message: "Changing the icon is not supported on this device.", details: nil);
    }

    static func iconNotFound(_ message: String, details: Any? = nil) -> FlutterError {
        return FlutterError(code: "ICON_NOT_FOUND", message: message, details: details);
    }

    static func iconChangeFailed(_ message: String, details: Any? = nil) -> FlutterError {
        return FlutterError(code: "ICON_CHANGE_FAILED", message: message, details: details);
    }
}
