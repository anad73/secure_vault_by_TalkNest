import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Toggles Android's FLAG_SECURE (blocks screenshots/screen recording and
/// blanks the app in the recent-apps switcher). Implemented in
/// MainActivity.kt.
abstract final class SecureWindow {
  static const MethodChannel _channel = MethodChannel('safe_vault/window');

  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Non-Android platforms / tests.
    } on PlatformException catch (e) {
      AppLogger.warn('SecureWindow', 'setSecure failed: ${e.code}');
    }
  }
}
