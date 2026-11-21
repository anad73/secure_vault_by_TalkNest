import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../auth/vault_session.dart';
import '../../picker/gallery_picker_screen.dart';
import '../../settings/settings_controller.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';
import 'album_chooser.dart';

enum _Source { gallery, audio }

/// "+" flow: pick a source, a target album, the files, then encrypt them
/// with a progress dialog and report the real outcome.
abstract final class AddMediaFlow {
  static Future<void> start(BuildContext context, {int? albumId}) async {
    final s = context.s;
    final source = await showModalBottomSheet<_Source>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
                child: Text(s.addToVault,
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(s.addPhotosVideos),
                onTap: () => Navigator.of(ctx).pop(_Source.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.library_music_rounded),
                title: Text(s.addAudio),
                onTap: () => Navigator.of(ctx).pop(_Source.audio),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final target =
        albumId ?? await AlbumChooser.pick(context, title: s.addToVault);
    if (target == null || !context.mounted) return;

    switch (source) {
      case _Source.gallery:
        await _fromGallery(context, target);
      case _Source.audio:
        await _fromFiles(context, target);
    }
  }

  static Future<void> _fromGallery(BuildContext context, int albumId) async {
    final vault = context.read<VaultService>();
    final deleteOriginals =
        context.read<SettingsController>().value.deleteOriginals;
    final assets = await GalleryPickerScreen.open(context);
    if (assets == null || assets.isEmpty || !context.mounted) return;
    try {
      final result = await runWithProgress(
        context,
        label: (s, d, t) => s.hidingProgress(done: d, total: t),
        task: (report) => vault.hideAssets(assets, albumId, report),
      );
      if (!context.mounted) return;
      _report(context, result);
      if (deleteOriginals && result.sourceIds.isNotEmpty) {
        AppFeedback.info(context, context.s.originalsNote);
        await vault.deleteOriginals(result.sourceIds);
      }
    } catch (e) {
      if (context.mounted) AppFeedback.error(context, e);
    }
  }

  static Future<void> _fromFiles(BuildContext context, int albumId) async {
    final vault = context.read<VaultService>();
    final session = context.read<VaultSession>();
    try {
      final picked =
          await session.runExternal(() => FilePicker.platform.pickFiles(
                type: FileType.audio,
                allowMultiple: true,
              ));
      if (picked == null || !context.mounted) return;
      final files = [
        for (final f in picked.files)
          if (f.path != null) PickedSource(path: f.path!, name: f.name),
      ];
      if (files.isEmpty) return;
      final result = await runWithProgress(
        context,
        label: (s, d, t) => s.hidingProgress(done: d, total: t),
        task: (report) =>
            vault.importFiles(files, MediaKind.audio, albumId, report),
      );
      if (!context.mounted) return;
      final s = context.s;
      if (result.failed == 0) {
        AppFeedback.success(context,
            '${s.hiddenSummary(n: result.ok)}. ${s.audioOriginalsNote}');
      } else {
        _report(context, result);
      }
    } catch (e) {
      if (context.mounted) AppFeedback.error(context, e);
    }
  }

  static void _report(BuildContext context, BatchResult r) {
    final s = context.s;
    if (r.failed == 0) {
      AppFeedback.success(context, s.hiddenSummary(n: r.ok));
    } else {
      AppFeedback.info(context, s.resultSummary(ok: r.ok, failed: r.failed));
    }
  }
}
