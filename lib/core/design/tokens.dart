import 'package:flutter/material.dart';

/// Design tokens. Every screen reads spacing, radii, durations and sizes
/// from here so the whole app stays visually consistent.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

abstract final class IconSizes {
  static const double sm = 18;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 48;
  static const double hero = 72;
}

abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration shimmer = Duration(milliseconds: 1400);
}

abstract final class Dimens {
  /// Minimum accessible touch target.
  static const double minTouch = 48;
  static const double pinKey = 72;
  static const double maxContentWidth = 560;
  static const double gridSpacing = 3;
}

/// Brand palette. The ColorScheme is generated from [seed]; the accent
/// gradient is used sparingly (hero areas, primary FAB).
abstract final class Brand {
  static const Color seed = Color(0xFF3D5AFE);
  static const Color accentA = Color(0xFF4F6BFF);
  static const Color accentB = Color(0xFF8E54E9);

  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentA, accentB],
  );
}

/// Soft shadows tuned per brightness.
abstract final class Shadows {
  static List<BoxShadow> card(Brightness b) => [
        BoxShadow(
          color: Colors.black
              .withValues(alpha: b == Brightness.dark ? 0.35 : 0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}
