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
    // Log every UIApplication method containing "icon" so we can identify
    // the correct private selector for the running iOS version.
    logIconMethods()

    // Try known private selectors in priority order.
    // withUserNotification:false tells the OS to skip the system alert.
    // The selector name has changed across iOS versions — try all variants.
    let candidates: [String] = [
      "_setAlternateIconName:withUserNotification:withCompletion:",
      "setAlternateIconName:withUserNotification:withCompletion:",
      "_setAlternateIconName:completionHandler:",
    ]

    for candidate in candidates {
      let sel = NSSelectorFromString(candidate)
      guard UIApplication.shared.responds(to: sel),
            let imp = class_getMethodImplementation(
              object_getClass(UIApplication.shared), sel)
      else {
        print("[IconChanger] Not available: \(candidate)")
        continue
      }

      if candidate.hasSuffix(":withCompletion:") ||
         candidate.hasSuffix(":withUserNotification:withCompletion:") {
        // Signature: (self, _cmd, iconName?, withUserNotification: Bool, completion: Block?)
        typealias Block = @convention(block) (Error?) -> Void
        typealias Fn = @convention(c) (AnyObject, Selector, NSString?, Bool, Block?) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        let cb: Block = { error in
          DispatchQueue.main.async {
            if let e = error {
              print("[IconChanger] Private API error: \(e.localizedDescription)")
              result(FlutterError.iconChangeFailed(e.localizedDescription))
            } else {
              print("[IconChanger] Icon changed silently via \(candidate)")
              result(true)
            }
          }
        }
        print("[IconChanger] Calling private API: \(candidate)")
        fn(UIApplication.shared, sel, iconName as NSString?, false, cb)
        return
      } else {
        // Signature: (self, _cmd, iconName?, completion: Block?)
        typealias Block = @convention(block) (Error?) -> Void
        typealias Fn = @convention(c) (AnyObject, Selector, NSString?, Block?) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        let cb: Block = { error in
          DispatchQueue.main.async {
            if let e = error {
              print("[IconChanger] Private API error: \(e.localizedDescription)")
              result(FlutterError.iconChangeFailed(e.localizedDescription))
            } else {
              print("[IconChanger] Icon changed via \(candidate)")
              result(true)
            }
          }
        }
        print("[IconChanger] Calling private API: \(candidate)")
        fn(UIApplication.shared, sel, iconName as NSString?, cb)
        return
      }
    }

    // No private selector matched — fall back to public API (dialog will appear).
    print("[IconChanger] No private selector found — using public API (dialog will show)")
    UIApplication.shared.setAlternateIconName(iconName) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError.iconChangeFailed(error.localizedDescription))
        } else {
          result(true)
        }
      }
    }
  }

  // Logs all UIApplication instance methods whose names contain "icon".
  // Connect device to Xcode / Console.app and search for [IconChanger] to read.
  private func logIconMethods() {
    var count: UInt32 = 0
    guard let methods = class_copyMethodList(
      object_getClass(UIApplication.shared), &count) else { return }
    defer { free(methods) }
    print("[IconChanger] === UIApplication icon-related methods ===")
    for i in 0..<Int(count) {
      let name = String(cString: sel_getName(method_getName(methods[i])))
      if name.lowercased().contains("icon") {
        print("[IconChanger]   \(name)")
      }
    }
    print("[IconChanger] === end ===")
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
