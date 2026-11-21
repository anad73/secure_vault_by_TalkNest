import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/models.dart';
import 'vault_thumb.dart';

/// Grid tile for one vault item with selection overlay.
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final VaultItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: item.name,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedScale(
          scale: selected ? 0.9 : 1,
          duration: Motion.fast,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(selected ? Radii.md : Radii.sm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                VaultThumb.item(item),
                if (item.kind == MediaKind.audio)
                  Padding(
                    padding: const EdgeInsets.all(Space.sm),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.labelSmall,
                      ),
                    ),
                  ),
                if (item.kind == MediaKind.video)
                  PositionedDirectional(
                    end: Space.xs,
                    bottom: Space.xs,
                    child: _Badge(
                      icon: Icons.play_arrow_rounded,
                      label:
                          Fmt.duration(Duration(milliseconds: item.durationMs)),
                    ),
                  ),
                if (item.favorite)
                  const PositionedDirectional(
                    start: Space.xs,
                    bottom: Space.xs,
                    child: Icon(Icons.favorite_rounded,
                        color: Colors.white,
                        size: IconSizes.sm,
                        shadows: [
                          Shadow(blurRadius: 6, color: Colors.black54)
                        ]),
                  ),
                if (selecting)
                  PositionedDirectional(
                    top: Space.xs,
                    end: Space.xs,
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? scheme.primary : Colors.black26,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: selected
                          ? Icon(Icons.check_rounded,
                              size: 16, color: scheme.onPrimary)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          const BoxDecoration(color: Colors.black54, borderRadius: Radii.smAll),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.xs + 2, vertical: Space.xxs),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: Space.xxs),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
