import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/l10n/app_strings.dart';
import 'package:safe_vault/core/l10n/strings_en.dart';
import 'package:safe_vault/core/l10n/strings_fa.dart';
import 'package:safe_vault/core/l10n/strings_ps.dart';
import 'package:safe_vault/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  for (final (code, table) in [('fa', stringsFa), ('ps', stringsPs)]) {
    test('$code has every English key with the same placeholders', () {
      expect(table.keys.toSet(), stringsEn.keys.toSet());
      for (final key in stringsEn.keys) {
        expect(_placeholders(table[key]!), _placeholders(stringsEn[key]!), reason: key);
      }
    });
  }

  test('placeholders are substituted', () {
    final s = AppStrings('en');
    expect(s.hidingProgress(done: 2, total: 5), 'Encrypting 2 of 5…');
    expect(AppStrings('fa').itemCount(n: 3), contains('3'));
  });

  test('RTL languages are flagged', () {
    expect(AppStrings('fa').isRtl, isTrue);
    expect(AppStrings('ps').isRtl, isTrue);
    expect(AppStrings('en').isRtl, isFalse);
  });

  test('settings persist across controller instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = SettingsController(prefs);
    await c.update(c.value.copyWith(themeMode: ThemeMode.dark, localeCode: 'ps', gridColumns: 4));
    final again = SettingsController(prefs);
    expect(again.value.themeMode, ThemeMode.dark);
    expect(again.value.localeCode, 'ps');
    expect(again.value.gridColumns, 4);
    await again.update(again.value.copyWith(clearLocale: true));
    expect(SettingsController(prefs).value.localeCode, isNull);
  });
}
