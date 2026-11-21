import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/debouncer.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/progress_dialog.dart';
import '../auth/vault_session.dart';
import 'backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _guard = SingleFlight();

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final backup = context.read<BackupService>();
    final session = context.read<VaultSession>();
    final s = context.s;
    await _guard.run(() async {
      try {
        final path = await runWithProgress(
          context,
          label: (s, d, t) => s.exportingProgress(done: d, total: t),
          task: (report) => backup.export(_pass.text, report),
        );
        if (!mounted) return;
        _pass.clear();
        _confirm.clear();
        AppFeedback.success(context, s.backupReady);
        await session.runExternal(() => Share.shareXFiles(
              [XFile(path, mimeType: 'application/octet-stream')],
              subject: s.appName,
            ));
      } catch (e) {
        if (mounted) AppFeedback.error(context, e);
      }
    });
  }

  Future<void> _import() async {
    final backup = context.read<BackupService>();
    final session = context.read<VaultSession>();
    final s = context.s;
    await _guard.run(() async {
      try {
        final picked = await session.runExternal(() => FilePicker.platform
            .pickFiles(type: FileType.any, allowMultiple: false));
        final path = picked?.files.single.path;
        if (path == null || !mounted) return;
        final password = await _askPassword();
        if (password == null || !mounted) return;
        final r = await runWithProgress(
          context,
          label: (s, d, t) => s.importingProgress(done: d, total: t),
          task: (report) => backup.import(path, password, report),
        );
        if (mounted) {
          AppFeedback.success(
              context, s.restoreDone(ok: r.ok, failed: r.failed));
        }
      } catch (e) {
        if (mounted) AppFeedback.error(context, e);
      } finally {
        try {
          await FilePicker.platform.clearTemporaryFiles();
        } catch (_) {
          // Best effort; cache is wiped by the OS too.
        }
      }
    });
  }

  Future<String?> _askPassword() {
    final c = TextEditingController();
    final s = context.s;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.backupPassword),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
          decoration: InputDecoration(labelText: s.backupPassword),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text),
              child: Text(s.continueLabel)),
        ],
      ),
    );
    // The controller is left to GC: disposing it here would race the
    // dialog's exit animation, which still renders the TextField.
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Icon(Icons.cloud_upload_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: Space.md),
                      Expanded(
                          child: Text(s.exportBackup,
                              style: theme.textTheme.titleMedium)),
                    ]),
                    const SizedBox(height: Space.sm),
                    Text(s.exportBackupBody, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: Space.lg),
                    TextFormField(
                      controller: _pass,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: s.backupPassword,
                          helperText: s.backupPasswordHint),
                      validator: (v) =>
                          (v ?? '').length < 8 ? s.passwordTooShort : null,
                    ),
                    const SizedBox(height: Space.md),
                    TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: InputDecoration(labelText: s.confirmPassword),
                      validator: (v) =>
                          v != _pass.text ? s.passwordMismatch : null,
                    ),
                    const SizedBox(height: Space.lg),
                    FilledButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.lock_rounded),
                      label: Text(s.exportBackup),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.settings_backup_restore_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: Space.md),
                    Expanded(
                        child: Text(s.importBackup,
                            style: theme.textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: Space.sm),
                  Text(s.importBackupBody, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: Space.lg),
                  OutlinedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(s.importBackup),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
