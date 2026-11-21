import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Immutable snapshot of user preferences.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.localeCode,
    this.autoLockSeconds = 0,
    this.haptics = true,
    this.blockScreenshots = true,
    this.deleteOriginals = true,
    this.hideThumbnails = false,
    this.slideshowSeconds = 3,
    this.gridColumns = 3,
  });

  final ThemeMode themeMode;

  /// `null` follows the system language.
  final String? localeCode;

  /// Seconds in background before the vault locks. 0 = immediately.
  final int autoLockSeconds;
  final bool haptics;
  final bool blockScreenshots;
  final bool deleteOriginals;
  final bool hideThumbnails;
  final int slideshowSeconds;
  final int gridColumns;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? localeCode,
    bool clearLocale = false,
    int? autoLockSeconds,
    bool? haptics,
    bool? blockScreenshots,
    bool? deleteOriginals,
    bool? hideThumbnails,
    int? slideshowSeconds,
    int? gridColumns,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
        autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
        haptics: haptics ?? this.haptics,
        blockScreenshots: blockScreenshots ?? this.blockScreenshots,
        deleteOriginals: deleteOriginals ?? this.deleteOriginals,
        hideThumbnails: hideThumbnails ?? this.hideThumbnails,
        slideshowSeconds: slideshowSeconds ?? this.slideshowSeconds,
        gridColumns: gridColumns ?? this.gridColumns,
      );
}

/// Loads and persists [AppSettings]. Widgets select only the fields they
/// need (`context.select`) so a change rebuilds as little as possible.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) : _value = _read(_prefs);

  final SharedPreferences _prefs;
  AppSettings _value;

  AppSettings get value => _value;

  static const _kTheme = 'theme_mode';
  static const _kLocale = 'locale';
  static const _kAutoLock = 'auto_lock_s';
  static const _kHaptics = 'haptics';
  static const _kSecure = 'block_screenshots';
  static const _kDeleteOriginals = 'delete_originals';
  static const _kHideThumbs = 'hide_thumbs';
  static const _kSlideshow = 'slideshow_s';
  static const _kGrid = 'grid_cols';

  static AppSettings _read(SharedPreferences p) {
    const d = AppSettings();
    final themeIndex = p.getInt(_kTheme) ?? d.themeMode.index;
    return AppSettings(
      themeMode:
          ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)],
      localeCode: p.getString(_kLocale),
      autoLockSeconds: p.getInt(_kAutoLock) ?? d.autoLockSeconds,
      haptics: p.getBool(_kHaptics) ?? d.haptics,
      blockScreenshots: p.getBool(_kSecure) ?? d.blockScreenshots,
      deleteOriginals: p.getBool(_kDeleteOriginals) ?? d.deleteOriginals,
      hideThumbnails: p.getBool(_kHideThumbs) ?? d.hideThumbnails,
      slideshowSeconds: p.getInt(_kSlideshow) ?? d.slideshowSeconds,
      gridColumns: (p.getInt(_kGrid) ?? d.gridColumns).clamp(2, 5),
    );
  }

  Future<void> update(AppSettings next) async {
    if (identical(next, _value)) return;
    _value = next;
    notifyListeners();
    await _prefs.setInt(_kTheme, next.themeMode.index);
    if (next.localeCode == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, next.localeCode!);
    }
    await _prefs.setInt(_kAutoLock, next.autoLockSeconds);
    await _prefs.setBool(_kHaptics, next.haptics);
    await _prefs.setBool(_kSecure, next.blockScreenshots);
    await _prefs.setBool(_kDeleteOriginals, next.deleteOriginals);
    await _prefs.setBool(_kHideThumbs, next.hideThumbnails);
    await _prefs.setInt(_kSlideshow, next.slideshowSeconds);
    await _prefs.setInt(_kGrid, next.gridColumns);
  }
}
