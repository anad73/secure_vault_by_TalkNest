import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/biometric_service.dart';
import '../../auth/presentation/credential_setup_screen.dart';
import '../../auth/presentation/widgets/recovery_form.dart';
import '../../auth/vault_session.dart';
import '../../backup/backup_screen.dart';
import '../../vault/data/vault_service.dart';
import '../settings_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _bioAvailable;
  bool _bioEnabled = false;
  bool _bioBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBio();
  }

  Future<void> _loadBio() async {
    final bio = context.read<BiometricService>();
    final available = await bio.isAvailable();
    final enabled = await bio.isEnabled();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
    }
  }

  Future<void> _toggleBio(bool on) async {
    if (_bioBusy) return;
    final bio = context.read<BiometricService>();
    final session = context.read<VaultSession>();
    final reason = context.s.biometricReason;
    setState(() => _bioBusy = true);
    try {
      if (on) {
        final ok = await bio.enable(session.key, reason);
        if (mounted) setState(() => _bioEnabled = ok);
      } else {
        await bio.disable();
        if (mounted) setState(() => _bioEnabled = false);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<T?> _choose<T>(String title, List<(T, String)> options, T current) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ),
          for (final (value, label) in options)
            ListTile(
              title: Text(label),
              trailing: value == current
                  ? Icon(Icons.check_rounded,
                      color: Theme.of(ctx).colorScheme.primary)
                  : null,
              selected: value == current,
              onTap: () => Navigator.of(ctx).pop(value),
            ),
          const SizedBox(height: Space.sm),
        ]),
      ),
    );
  }

  Future<void> _editRecovery() async {
    final auth = context.read<AuthRepository>();
    final session = context.read<VaultSession>();
    final s = context.s;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl,
                MediaQuery.viewInsetsOf(ctx).bottom + Space.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(s.recoveryTitle, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: Space.sm),
              Text(s.recoverySubtitle, textAlign: TextAlign.center),
              const SizedBox(height: Space.lg),
              RecoveryForm(
                busy: busy,
                initialQuestion: auth.recoveryQuestion,
                onSave: (q, a) async {
                  setSheet(() => busy = true);
                  try {
                    await auth.setRecovery(session.key, q, a);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (mounted) {
                      setState(() {}); // refresh the question subtitle
                      AppFeedback.success(context, s.recoverySaved);
                    }
                  } catch (e) {
                    if (ctx.mounted) setSheet(() => busy = false);
                    if (mounted) AppFeedback.error(context, e);
                  }
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _integrity() async {
    final vault = context.read<VaultService>();
    final s = context.s;
    try {
      final r = await runWithProgress(
        context,
        label: (s, _, __) => s.integrity,
        task: (_) =>
            vault.checkIntegrity(fallbackAlbumName: s.recoveredAlbumName),
      );
      if (mounted) {
        AppFeedback.success(context,
            s.integrityResult(n: r.checked, r: r.recovered, m: r.removed));
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final ctrl = context.watch<SettingsController>();
    final v = ctrl.value;

    String autoLockLabel(int sec) => sec == 0
        ? s.autoLockImmediately
        : sec < 60
            ? s.autoLockSeconds(n: sec)
            : s.autoLockMinutes(n: sec ~/ 60);

    const languages = <(String?, String)>[
      (null, ''),
      ('en', 'English'),
      ('fa', 'دری'),
      ('ps', 'پښتو'),
    ];
    String languageLabel(String? code) => code == null
        ? s.languageSystem
        : languages
            .firstWhere((l) => l.$1 == code, orElse: () => (code, code))
            .$2;

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          _Section(s.appearance),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.lg, vertical: Space.sm),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_rounded),
                    label: Text(s.themeSystem)),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_rounded),
                    label: Text(s.themeLight)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_rounded),
                    label: Text(s.themeDark)),
              ],
              selected: {v.themeMode},
              onSelectionChanged: (sel) =>
                  ctrl.update(v.copyWith(themeMode: sel.first)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(s.language),
            subtitle: Text(languageLabel(v.localeCode)),
            onTap: () async {
              final options = [
                for (final l in languages)
                  (l.$1 ?? '', l.$1 == null ? s.languageSystem : l.$2),
              ];
              final picked = await _choose<String>(
                  s.language, options, v.localeCode ?? '');
              if (picked == null) return;
              await ctrl.update(picked.isEmpty
                  ? v.copyWith(clearLocale: true)
                  : v.copyWith(localeCode: picked));
            },
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_rounded),
            title: Text(s.gridColumns),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {v.gridColumns},
              onSelectionChanged: (sel) =>
                  ctrl.update(v.copyWith(gridColumns: sel.first)),
            ),
          ),
          _Section(s.security),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: Text(s.changeCredential),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => const CredentialSetupScreen.change(),
            )),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: Text(s.biometricUnlock),
            subtitle:
                _bioAvailable == false ? Text(s.biometricUnavailable) : null,
            value: _bioEnabled,
            onChanged: _bioAvailable == true && !_bioBusy ? _toggleBio : null,
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(s.setRecovery),
            subtitle:
                Text(context.watch<AuthRepository>().recoveryQuestion ?? '—'),
            onTap: _editRecovery,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(s.autoLock),
            subtitle: Text(autoLockLabel(v.autoLockSeconds)),
            onTap: () async {
              final picked = await _choose<int>(
                s.autoLock,
                [
                  for (final sec in const [0, 30, 60, 300])
                    (sec, autoLockLabel(sec))
                ],
                v.autoLockSeconds,
              );
              if (picked != null) {
                await ctrl.update(v.copyWith(autoLockSeconds: picked));
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screenshot_monitor_rounded),
            title: Text(s.blockScreenshots),
            subtitle: Text(s.blockScreenshotsBody),
            value: v.blockScreenshots,
            onChanged: (on) => ctrl.update(v.copyWith(blockScreenshots: on)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: Text(s.haptics),
            value: v.haptics,
            onChanged: (on) => ctrl.update(v.copyWith(haptics: on)),
          ),
          _Section(s.vault),
          SwitchListTile(
            secondary: const Icon(Icons.auto_delete_outlined),
            title: Text(s.deleteOriginals),
            value: v.deleteOriginals,
            onChanged: (on) => ctrl.update(v.copyWith(deleteOriginals: on)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.hide_image_outlined),
            title: Text(s.hideThumbnails),
            value: v.hideThumbnails,
            onChanged: (on) => ctrl.update(v.copyWith(hideThumbnails: on)),
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_rounded),
            title: Text(s.slideshowInterval),
            subtitle: Text(s.secondsShort(n: v.slideshowSeconds)),
            onTap: () async {
              final picked = await _choose<int>(
                s.slideshowInterval,
                [
                  for (final sec in const [2, 3, 5, 10])
                    (sec, s.secondsShort(n: sec))
                ],
                v.slideshowSeconds,
              );
              if (picked != null) {
                await ctrl.update(v.copyWith(slideshowSeconds: picked));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(s.backupTitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: Text(s.integrity),
            subtitle: Text(s.integrityBody),
            onTap: _integrity,
          ),
          _Section(s.about),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(s.version(v: '1.0.0')),
            subtitle: Text(s.aboutBody),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.sm),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
