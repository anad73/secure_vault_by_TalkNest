import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/design/app_theme.dart';
import 'package:safe_vault/core/l10n/app_strings.dart';
import 'package:safe_vault/core/widgets/states.dart';
import 'package:safe_vault/features/auth/presentation/widgets/credential_pad.dart';
import 'package:safe_vault/features/auth/presentation/widgets/pin_pad.dart';

Widget _host(Widget child, {Locale locale = const Locale('en'), ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light(),
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Center(child: SingleChildScrollView(child: child))),
  );
}

void main() {
  testWidgets('PIN pad submits only after the minimum length', (tester) async {
    String? submitted;
    await tester.pumpWidget(_host(PinPad(onSubmit: (v) => submitted = v)));

    for (final d in ['1', '2', '3']) {
      await tester.tap(find.text(d));
    }
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();
    expect(submitted, isNull, reason: '3 digits is below the minimum');

    await tester.tap(find.text('4'));
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();
    expect(submitted, '1234');
  });

  testWidgets('PIN pad backspace removes the last digit', (tester) async {
    String? submitted;
    await tester.pumpWidget(_host(PinPad(onSubmit: (v) => submitted = v)));
    for (final d in ['9', '8', '7', '6', '5']) {
      await tester.tap(find.text(d));
    }
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();
    expect(submitted, '9876');
  });

  testWidgets('PIN keys meet the 48dp touch-target guideline', (tester) async {
    await tester.pumpWidget(_host(PinPad(onSubmit: (_) {})));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  test('credentials are domain-separated', () {
    expect(Credential.pin('1234'), isNot(Credential.pattern([1, 2, 3, 4])));
    expect(Credential.pattern([0, 4, 8, 5]), 'pat:0-4-8-5');
  });

  testWidgets('empty state renders in RTL (Pashto) without overflow', (tester) async {
    await tester.pumpWidget(_host(
      Builder(
        builder: (context) => EmptyState(
          icon: Icons.lock_outline_rounded,
          title: context.s.emptyVaultTitle,
          message: context.s.emptyVaultBody,
        ),
      ),
      locale: const Locale('ps'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ستاسو زېرمه تشه ده'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.byType(EmptyState)));
    expect(dir, TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme builds with Material 3', (tester) async {
    await tester.pumpWidget(_host(const Text('x'), theme: AppTheme.dark()));
    final theme = Theme.of(tester.element(find.text('x')));
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
  });
}
