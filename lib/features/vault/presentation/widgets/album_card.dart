import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../domain/models.dart';
import 'vault_thumb.dart';

/// Album card: cover thumbnail, name and item count.
class AlbumCard extends StatelessWidget {
  const AlbumCard(
      {super.key, required this.album, required this.onTap, this.onLongPress});

  final Album album;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '${album.name}, ${context.s.itemCount(n: album.itemCount)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: Radii.lgAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: Radii.lgAll,
                  boxShadow: Shadows.card(theme.brightness),
                ),
                child: ClipRRect(
                  borderRadius: Radii.lgAll,
                  child: album.coverFileId == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.primaryContainer,
                                scheme.tertiaryContainer,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(Icons.photo_library_outlined,
                                size: IconSizes.xl,
                                color: scheme.onPrimaryContainer),
                          ),
                        )
                      : VaultThumb(
                          fileId: album.coverFileId!,
                          kind: album.coverKind ?? MediaKind.image,
                        ),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.xs),
              child: Text(album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.xs),
              child: Text(
                context.s.itemCount(n: album.itemCount),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
