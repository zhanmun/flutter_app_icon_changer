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

    case "getIconMethods":
        result(self.getIconMethods())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func changeIcon(to iconName: String?, result: @escaping FlutterResult) {
      guard UIApplication.shared.supportsAlternateIcons else {
          NSLog("[IconChanger] Changing the icon is not supported on this device.")
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
        NSLog("[IconChanger] Background change error: \(error.localizedDescription)")
      } else {
        NSLog("[IconChanger] Icon changed silently in background.")
      }
    }
  }

  private func setIcon(icon iconName: String?, result: @escaping FlutterResult) {
    // Log every UIApplication method containing "icon" so we can identify
    // the correct private selector for the running iOS version.
    logIconMethods()

    // On iOS 26, _setAlternateIconName:withUserNotification:withCompletion: no
    // longer exists. The only private variant is _setAlternateIconName:completionHandler:
    // which may skip the system dialog because it bypasses the public callsite.
    let privateSel = NSSelectorFromString("_setAlternateIconName:completionHandler:")
    if UIApplication.shared.responds(to: privateSel),
       let imp = class_getMethodImplementation(object_getClass(UIApplication.shared), privateSel) {
      typealias Block = @convention(block) (Error?) -> Void
      typealias Fn = @convention(c) (AnyObject, Selector, NSString?, Block?) -> Void
      let fn = unsafeBitCast(imp, to: Fn.self)
      let cb: Block = { error in
        DispatchQueue.main.async {
          if let e = error {
            result(FlutterError.iconChangeFailed(e.localizedDescription))
          } else {
            result(true)
          }
        }
      }
      fn(UIApplication.shared, privateSel, iconName as NSString?, cb)
      return
    }

    // Fall back to public API (system dialog will appear).
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

  // Traverses the full UIApplication class hierarchy and returns every method
  // whose name contains "icon" or "alternate" (case-insensitive).
  // Also reports the total method count per class so we know if enumeration works.
  private func getIconMethods() -> String {
    var lines: [String] = []
    var cls: AnyClass? = object_getClass(UIApplication.shared)
    while let c = cls {
      let className = String(cString: class_getName(c))
      var count: UInt32 = 0
      let methods = class_copyMethodList(c, &count)
      var found: [String] = []
      if let methods = methods {
        for i in 0..<Int(count) {
          let name = String(cString: sel_getName(method_getName(methods[i])))
          let lower = name.lowercased()
          if lower.contains("icon") || lower.contains("alternate") {
            found.append(name)
          }
        }
        free(methods)
      }
      lines.append("[\(className)] total=\(count) matched=\(found.count)")
      for m in found.sorted() { lines.append("  \(m)") }
      cls = class_getSuperclass(c)
    }
    return lines.isEmpty ? "(no classes found)" : lines.joined(separator: "\n")
  }

  private func logIconMethods() {
    NSLog("[IconChanger] icon methods:\n\(getIconMethods())")
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
