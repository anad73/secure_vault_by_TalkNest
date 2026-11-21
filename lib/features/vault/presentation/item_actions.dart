import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../auth/vault_session.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';
import 'album_chooser.dart';

/// Item operations shared by the album grid and the viewer. Each returns
/// true when the items left the current view (moved/unhidden/deleted).
abstract final class ItemActions {
  static Future<bool> move(BuildContext context, List<VaultItem> items,
      {required int fromAlbum}) async {
    if (items.isEmpty) return false;
    final vault = context.read<VaultService>();
    final target = await AlbumChooser.pick(context,
        title: context.s.moveTo, excludeId: fromAlbum);
    if (target == null || target == fromAlbum) return false;
    try {
      await vault.move(items, target);
      return true;
    } catch (e) {
      if (context.mounted) AppFeedback.error(context, e);
      return false;
    }
  }

  static Future<bool> unhide(
      BuildContext context, List<VaultItem> items) async {
    if (items.isEmpty) return false;
    final s = context.s;
    final vault = context.read<VaultService>();
    final ok = await AppFeedback.confirm(
      context,
      title: s.unhideConfirmTitle(n: items.length),
      message: s.unhideConfirmBody,
      confirmLabel: s.unhide,
      icon: Icons.lock_open_rounded,
    );
    if (!ok || !context.mounted) return false;
    try {
      final r = await runWithProgress(
        context,
        label: (s, d, t) => s.unhidingProgress(done: d, total: t),
        task: (report) => vault.unhide(items, report),
      );
      if (!context.mounted) return r.ok > 0;
      if (r.failed == 0) {
        AppFeedback.success(context, s.resultSummary(ok: r.ok, failed: 0));
      } else {
        AppFeedback.info(context, s.resultSummary(ok: r.ok, failed: r.failed));
      }
      return r.ok > 0;
    } catch (e) {
      if (context.mounted) AppFeedback.error(context, e);
      return false;
    }
  }

  static Future<bool> delete(
      BuildContext context, List<VaultItem> items) async {
    if (items.isEmpty) return false;
    final s = context.s;
    final vault = context.read<VaultService>();
    final ok = await AppFeedback.confirm(
      context,
      title: s.deleteConfirmTitle(n: items.length),
      message: s.deleteConfirmBody,
      confirmLabel: s.delete,
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !context.mounted) return false;
    try {
      final r = await runWithProgress(
        context,
        label: (s, d, t) => s.deletingProgress(done: d, total: t),
        task: (report) => vault.delete(items, report),
      );
      if (context.mounted && r.failed > 0) {
        AppFeedback.info(context, s.resultSummary(ok: r.ok, failed: r.failed));
      }
      return r.ok > 0;
    } catch (e) {
      if (context.mounted) AppFeedback.error(context, e);
      return false;
    }
  }

  /// Shares decrypted copies after an explicit warning.
  static Future<void> share(BuildContext context, List<VaultItem> items) async {
    if (items.isEmpty) return;
    final s = context.s;
    final vault = context.read<VaultService>();
    final session = context.read<VaultSession>();
    final ok = await AppFeedback.confirm(
      context,
      title: s.share,
      message: s.shareWarning,
      confirmLabel: s.share,
      icon: Icons.warning_amber_rounded,
    );
    if (!ok || !context.mounted) return;
    try {
      final files = await runWithProgress(
        context,
        label: (s, d, t) => s.exportingProgress(done: d, total: t),
        task: (report) async {
          final out = <XFile>[];
          report(0, items.length);
          for (var i = 0; i < items.length; i++) {
            final f = await vault.decryptToTemp(items[i]);
            out.add(
                XFile(f.path, mimeType: items[i].mime, name: items[i].name));
            report(i + 1, items.length);
          }
          return out;
        },
      );
      await session.runExternal(() => Share.shareXFiles(files));
    } catch (e) {
      if (context.mounted) AppFeedback.error(context, e);
    }
  }
}
