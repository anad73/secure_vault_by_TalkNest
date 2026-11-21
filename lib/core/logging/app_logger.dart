import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Centralised logger.
///
/// Never pass file names, PINs, keys or other user data to it: the vault's
/// privacy depends on logs being free of sensitive content. Logs are dropped
/// entirely in release builds.
abstract final class AppLogger {
  static void info(String tag, String message) => _log(tag, message, 800);

  static void warn(String tag, String message) => _log(tag, message, 900);

  static void error(String tag, String message,
      [Object? error, StackTrace? stack]) {
    _log(tag, message, 1000, error, stack);
  }

  static void _log(String tag, String message, int level,
      [Object? error, StackTrace? stack]) {
    if (kReleaseMode) return;
    developer.log(message,
        name: 'SafeVault.$tag', level: level, error: error, stackTrace: stack);
  }
}
