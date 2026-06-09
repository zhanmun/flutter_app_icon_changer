import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/models.dart';
import 'flutter_app_icon_changer_method_channel.dart';

abstract class FlutterAppIconChangerPlatform extends PlatformInterface {
  FlutterAppIconChangerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAppIconChangerPlatform _instance =
      MethodChannelFlutterAppIconChanger();

  static FlutterAppIconChangerPlatform get instance => _instance;

  static set instance(FlutterAppIconChangerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool?> changeIcon(String? icon) {
    throw UnimplementedError('changeIcon() has not been implemented.');
  }

  Future<String?> getCurrentIcon() {
    throw UnimplementedError('getCurrentIcon() has not been implemented.');
  }

  Future<bool> isSupported() async {
    throw UnimplementedError('isSupported() has not been implemented.');
  }

  Future<void> setAvailableIcons(List<AppIcon> iconsSet) async {
    throw UnimplementedError('setAvailableIcons() has not been implemented.');
  }
}
