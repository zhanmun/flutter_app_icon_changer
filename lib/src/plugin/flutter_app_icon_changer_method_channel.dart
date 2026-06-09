import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'flutter_app_icon_changer_platform_interface.dart';

class MethodChannelFlutterAppIconChanger extends FlutterAppIconChangerPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_app_icon_changer');

  @override
  Future<bool?> changeIcon(String? icon) {
    return methodChannel.invokeMethod<bool>('changeIcon', {'iconName': icon});
  }

  @override
  Future<String?> getCurrentIcon() {
    return methodChannel.invokeMethod<String>('getCurrentIcon');
  }

  @override
  Future<bool> isSupported() async {
    final isSupported = await methodChannel.invokeMethod<bool>('isSupported');
    return isSupported ?? false;
  }

  @override
  Future<void> setAvailableIcons(List<AppIcon> iconsSet) async {
    final dataSet = iconsSet.toDataSet();
    await methodChannel.invokeMethod('setAvailableIcons', {'icons': dataSet});
  }
}
