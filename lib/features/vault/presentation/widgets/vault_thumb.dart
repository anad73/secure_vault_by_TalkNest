import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/tokens.dart';
import '../../../settings/settings_controller.dart';
import '../../data/vault_service.dart';
import '../../domain/models.dart';

/// Decrypted thumbnail with placeholder, error state and fade-in.
///
/// The decoded image is downscaled to the tile size (`cacheWidth`) so a
/// grid of hundreds of items stays light on memory.
class VaultThumb extends StatefulWidget {
  const VaultThumb({
    super.key,
    required this.fileId,
    required this.kind,
    this.rotation = 0,
    this.hasThumb = true,
  });

  VaultThumb.item(VaultItem item, {Key? key})
      : this(
          key: key ?? ValueKey(item.fileId),
          fileId: item.fileId,
          kind: item.kind,
          rotation: item.rotation,
          hasThumb: item.hasThumb,
        );

  final String fileId;
  final MediaKind kind;
  final int rotation;
  final bool hasThumb;

  @override
  State<VaultThumb> createState() => _VaultThumbState();
}

class _VaultThumbState extends State<VaultThumb> {
  Future<Uint8List?>? _future;
  VaultService? _vault;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vault ??= context.read<VaultService>();
    _future ??= _load();
  }

  @override
  void didUpdateWidget(covariant VaultThumb old) {
    super.didUpdateWidget(old);
    if (old.fileId != widget.fileId) _future = _load();
  }

  Future<Uint8List?> _load() {
    if (!widget.hasThumb || widget.kind == MediaKind.audio) {
      return Future.value(null);
    }
    return _vault!.thumbnailById(widget.fileId);
  }

  @override
  Widget build(BuildContext context) {
    final hide =
        context.select<SettingsController, bool>((c) => c.value.hideThumbnails);
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(_iconFor(widget.kind),
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            size: IconSizes.lg),
      ),
    );
    if (hide || !widget.hasThumb || widget.kind == MediaKind.audio) {
      return placeholder;
    }

    return LayoutBuilder(builder: (context, constraints) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
      final cacheWidth = (w * dpr).round().clamp(64, 640);
      return FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snap) {
          final bytes = snap.data;
          final child = bytes == null
              ? placeholder
              : RotatedBox(
                  quarterTurns: widget.rotation,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => placeholder,
                  ),
                );
          return AnimatedSwitcher(duration: Motion.fast, child: child);
        },
      );
    });
  }

  static IconData _iconFor(MediaKind k) => switch (k) {
        MediaKind.image => Icons.image_outlined,
        MediaKind.video => Icons.movie_outlined,
        MediaKind.audio => Icons.music_note_rounded,
      };
}
