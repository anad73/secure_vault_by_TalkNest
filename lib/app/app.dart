import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/design/app_theme.dart';
import '../core/design/tokens.dart';
import '../core/l10n/app_strings.dart';
import '../core/platform/secure_window.dart';
import '../core/utils/haptics.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/credential_setup_screen.dart';
import '../features/auth/presentation/lock_screen.dart';
import '../features/auth/vault_session.dart';
import '../features/settings/settings_controller.dart';
import '../features/vault/presentation/home_screen.dart';
import 'dependencies.dart';

/// Root widget: provides dependencies and builds the themed MaterialApp.
class SafeVaultApp extends StatelessWidget {
  const SafeVaultApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: deps.paths),
        Provider.value(value: deps.auth),
        Provider.value(value: deps.biometrics),
        Provider.value(value: deps.albums),
        Provider.value(value: deps.items),
        Provider.value(value: deps.backup),
        ChangeNotifierProvider.value(value: deps.settings),
        ChangeNotifierProvider.value(value: deps.session),
        ChangeNotifierProvider.value(value: deps.vault),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final VaultSession _session;
  late final SettingsController _settings;
  DateTime? _backgroundedAt;
  bool? _appliedSecure;

  @override
  void initState() {
    super.initState();
    _session = context.read<VaultSession>();
    _settings = context.read<SettingsController>();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSessionChanged);
    _settings.addListener(_applySettings);
    _applySettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _settings.removeListener(_applySettings);
    super.dispose();
  }

  void _applySettings() {
    final v = _settings.value;
    Haptics.enabled = v.haptics;
    if (_appliedSecure != v.blockScreenshots) {
      _appliedSecure = v.blockScreenshots;
      SecureWindow.setSecure(v.blockScreenshots);
    }
  }

  /// When the vault locks, drop every route above the gate so no screen
  /// with decrypted content stays on the stack.
  void _onSessionChanged() {
    if (!_session.isUnlocked) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_session.isUnlocked || _session.inExternalActivity) return;
    final autoLock = _settings.value.autoLockSeconds;
    switch (state) {
      case AppLifecycleState.paused:
        if (autoLock == 0) {
          _session.lock();
        } else {
          _backgroundedAt ??= DateTime.now();
        }
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            DateTime.now().difference(since).inSeconds >= autoLock) {
          _session.lock();
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode =
        context.select<SettingsController, ThemeMode>((c) => c.value.themeMode);
    final localeCode =
        context.select<SettingsController, String?>((c) => c.value.localeCode);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (ctx) => ctx.s.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: localeCode == null ? null : Locale(localeCode),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const VaultGate(),
    );
  }
}

/// Chooses setup, lock or home based on vault state.
class VaultGate extends StatelessWidget {
  const VaultGate({super.key});

  @override
  Widget build(BuildContext context) {
    final unlocked = context.select<VaultSession, bool>((s) => s.isUnlocked);
    final auth = context.watch<AuthRepository>();
    final Widget child;
    if (unlocked) {
      child = const HomeScreen(key: ValueKey('home'));
    } else if (!auth.isSetUp) {
      child = const CredentialSetupScreen.create(key: ValueKey('setup'));
    } else {
      child = const LockScreen(key: ValueKey('lock'));
    }
    return AnimatedSwitcher(
      duration:
          MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.slow,
      switchInCurve: Curves.easeOutCubic,
      child: child,
    );
  }
}
