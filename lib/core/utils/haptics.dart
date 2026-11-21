import 'package:flutter/services.dart';

/// Haptic feedback that respects the user's "Vibration feedback" setting.
abstract final class Haptics {
  static bool enabled = true;

  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void success() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void error() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
