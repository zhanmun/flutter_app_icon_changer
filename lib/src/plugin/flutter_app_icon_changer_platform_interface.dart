import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/models.dart';
import 'flutter_app_icon_changer_method_channel.dart';

abstract class FlutterAppIconChangerPlatform extends PlatformInterface {
  /// Constructs a FlutterAppIconChangerPlatform.
  FlutterAppIconChangerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAppIconChangerPlatform _instance =
      MethodChannelFlutterAppIconChanger();

  /// The default instance of [FlutterAppIconChangerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAppIconChanger].
  static FlutterAppIconChangerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterAppIconChangerPlatform] when
  /// they register themselves.
  static set instance(FlutterAppIconChangerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Changes the app icon to the specified [iconName].
  ///
  /// If [iconName] is `null`, the default icon is used.
  /// Returns `true` if the icon was successfully changed.
  Future<bool?> changeIcon(String? icon) {
    throw UnimplementedError('changeIcon() has not been implemented.');
  }

  /// Retrieves the name of the current app icon.
  ///
  /// May return `true` if a default icon is set.
  Future<String?> getCurrentIcon() {
    throw UnimplementedError('getCurrentIcon() has not been implemented.');
  }

  /// Checks if changing the app icon is supported on the current platform.
  Future<bool> isSupported() async {
    throw UnimplementedError('isSupported() has not been implemented.');
  }

  /// Sets the available icons for the plugin.
  Future<void> setAvailableIcons(List<AppIcon> iconsSet) async {
    throw UnimplementedError('setAvailableIcons() has not been implemented.');
  }

  /// iOS only: schedules the icon to change the next time the app enters
  /// background. The change uses the native background notification so no
  /// system dialog is shown.
  Future<bool?> scheduleIconChangeOnBackground(String iconName) {
    throw UnimplementedError('scheduleIconChangeOnBackground() has not been implemented.');
  }

  /// iOS only: returns a newline-separated list of UIApplication instance
  /// methods whose names contain "icon". Used to identify the correct private
  /// selector for the running iOS version.
  Future<String?> getIconMethods() {
    throw UnimplementedError('getIconMethods() has not been implemented.');
  }
}
