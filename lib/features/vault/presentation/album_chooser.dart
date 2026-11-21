import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/feedback.dart';
import '../data/album_repository.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';
import 'widgets/vault_thumb.dart';

/// Bottom sheet to choose (or create) a target album.
abstract final class AlbumChooser {
  static Future<int?> pick(BuildContext context,
      {required String title, int? excludeId}) async {
    final albums = await context.read<AlbumRepository>().all();
    if (!context.mounted) return null;
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                child: const Icon(Icons.add_rounded),
              ),
              title: Text(ctx.s.newAlbum),
              onTap: () => Navigator.of(ctx).pop(-1),
            ),
            for (final a in albums)
              if (a.id != excludeId)
                ListTile(
                  leading: SizedBox.square(
                    dimension: 44,
                    child: ClipRRect(
                      borderRadius: Radii.smAll,
                      child: a.coverFileId == null
                          ? ColoredBox(
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.photo_library_outlined))
                          : VaultThumb(
                              fileId: a.coverFileId!,
                              kind: a.coverKind ?? MediaKind.image),
                    ),
                  ),
                  title: Text(a.name),
                  subtitle: Text(ctx.s.itemCount(n: a.itemCount)),
                  onTap: () => Navigator.of(ctx).pop(a.id),
                ),
          ],
        ),
      ),
    );
    if (choice == -1 && context.mounted) return createAlbum(context);
    return choice;
  }

  /// Prompts for a unique album name and creates it.
  static Future<int?> createAlbum(BuildContext context) async {
    final vault = context.read<VaultService>();
    final s = context.s;
    final existing = {
      for (final a in await context.read<AlbumRepository>().all())
        a.name.toLowerCase()
    };
    if (!context.mounted) return null;
    final name = await AppFeedback.prompt(
      context,
      title: s.newAlbum,
      label: s.albumName,
      confirmLabel: s.create,
      validator: (v) {
        if (v.isEmpty) return s.nameEmpty;
        if (existing.contains(v.toLowerCase())) return s.nameExists;
        return null;
      },
    );
    if (name == null) return null;
    return vault.createAlbum(name);
  }
}
