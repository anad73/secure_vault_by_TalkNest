import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/glass.dart';
import '../settings/settings_controller.dart';
import '../vault/data/vault_service.dart';
import '../vault/domain/models.dart';
import '../vault/presentation/item_actions.dart';
import '../vault/presentation/widgets/vault_thumb.dart';
import 'player_page.dart';

/// Full-screen viewer with swipe paging, pinch-zoom, rotate, favourite,
/// slideshow, share, unhide and delete.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen(
      {super.key, required this.items, required this.initialIndex});

  final List<VaultItem> items;
  final int initialIndex;

  static Future<void> open(BuildContext context,
      {required List<VaultItem> items, required int index}) {
    return Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: Motion.medium,
      reverseTransitionDuration: Motion.medium,
      pageBuilder: (_, __, ___) =>
          MediaViewerScreen(items: List.of(items), initialIndex: index),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final List<VaultItem> _items = widget.items;
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _chrome = true;
  Timer? _slideshow;

  /// Small window of decrypted images so swiping back is instant.
  final Map<String, Future<Uint8List>> _bytes = {};

  late final VaultService _vault;

  VaultItem get _current => _items[_index];

  @override
  void initState() {
    super.initState();
    _vault = context.read<VaultService>();
  }

  @override
  void dispose() {
    _slideshow?.cancel();
    _pages.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<Uint8List> _imageBytes(VaultItem item) {
    final hit = _bytes[item.fileId];
    if (hit != null) return hit;
    final f = _vault.readBytes(item);
    _bytes[item.fileId] = f;
    // Keep at most 5 decoded neighbours in memory.
    while (_bytes.length > 5) {
      _bytes.remove(_bytes.keys.first);
    }
    return f;
  }

  void _toggleChrome() {
    if (_slideshow != null) {
      _stopSlideshow();
      return;
    }
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(
        _chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _startSlideshow() {
    final seconds = context.read<SettingsController>().value.slideshowSeconds;
    setState(() => _chrome = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _slideshow = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted) return;
      final next = _nextImageIndex();
      if (next == null) {
        _stopSlideshow();
        return;
      }
      if (reduceMotion) {
        _pages.jumpToPage(next);
      } else {
        _pages.animateToPage(next,
            duration: Motion.slow, curve: Curves.easeInOut);
      }
    });
  }

  int? _nextImageIndex() {
    for (var i = _index + 1; i < _items.length; i++) {
      if (_items[i].kind == MediaKind.image) return i;
    }
    return null;
  }

  void _stopSlideshow() {
    _slideshow?.cancel();
    _slideshow = null;
    setState(() => _chrome = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _rotate() async {
    final updated = await _vault.rotate(_current);
    if (mounted) setState(() => _items[_index] = updated);
  }

  Future<void> _favorite() async {
    final updated = await _vault.toggleFavorite(_current);
    if (mounted) setState(() => _items[_index] = updated);
  }

  /// Removes the current item from the pager after it left the album.
  void _removeCurrent() {
    if (!mounted) return;
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  void _details() {
    final s = context.s;
    final it = _current;
    final rows = <(String, String)>[
      (s.detailName, it.name),
      (
        s.detailType,
        switch (it.kind) {
          MediaKind.image => s.kindImage,
          MediaKind.video => s.kindVideo,
          MediaKind.audio => s.kindAudio,
        }
      ),
      (s.detailSize, Fmt.bytes(it.size)),
      if (it.width > 0) (s.detailDimensions, '${it.width} × ${it.height}'),
      if (it.durationMs > 0)
        (s.detailDuration, Fmt.duration(Duration(milliseconds: it.durationMs))),
      (s.detailTaken, Fmt.date(it.takenAt)),
      (s.detailAdded, Fmt.date(it.addedAt)),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.details, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(k,
                              style: TextStyle(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ),
                        Expanded(child: SelectableText(v)),
                      ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_items.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final item = _current;
    final hasManyImages =
        _items.where((e) => e.kind == MediaKind.image).length > 1;

    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: Stack(children: [
          GestureDetector(
            onTap: _toggleChrome,
            child: PageView.builder(
              controller: _pages,
              itemCount: _items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final it = _items[i];
                return switch (it.kind) {
                  MediaKind.image => _ImagePage(
                      key: ValueKey('img-${it.fileId}'),
                      item: it,
                      bytes: _imageBytes(it),
                    ),
                  _ => PlayerPage(
                      key: ValueKey('play-${it.fileId}'),
                      item: it,
                      active: i == _index,
                    ),
                };
              },
            ),
          ),
          // Top bar
          AnimatedPositioned(
            duration: Motion.medium,
            curve: Curves.easeOut,
            top: _chrome ? 0 : -140,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: GlassPanel(
                  tint: Colors.black.withValues(alpha: 0.35),
                  borderRadius: Radii.xlAll,
                  child: Row(children: [
                    BackButton(
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop()),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    Text('${_index + 1}/${_items.length}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    IconButton(
                      tooltip: s.favorite,
                      color: Colors.white,
                      icon: Icon(item.favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded),
                      onPressed: _favorite,
                    ),
                    IconButton(
                      tooltip: s.details,
                      color: Colors.white,
                      icon: const Icon(Icons.info_outline_rounded),
                      onPressed: _details,
                    ),
                  ]),
                ),
              ),
            ),
          ),
          // Bottom bar
          AnimatedPositioned(
            duration: Motion.medium,
            curve: Curves.easeOut,
            bottom: _chrome ? 0 : -160,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: GlassPanel(
                  tint: Colors.black.withValues(alpha: 0.35),
                  borderRadius: Radii.xlAll,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (item.kind == MediaKind.image)
                        _ViewerAction(
                            icon: Icons.rotate_right_rounded,
                            label: s.rotate,
                            onTap: _rotate),
                      if (item.kind == MediaKind.image && hasManyImages)
                        _ViewerAction(
                            icon: Icons.slideshow_rounded,
                            label: s.slideshow,
                            onTap: _startSlideshow),
                      _ViewerAction(
                        icon: Icons.ios_share_rounded,
                        label: s.share,
                        onTap: () => ItemActions.share(context, [item]),
                      ),
                      _ViewerAction(
                        icon: Icons.lock_open_rounded,
                        label: s.unhide,
                        onTap: () async {
                          if (await ItemActions.unhide(context, [item])) {
                            _removeCurrent();
                          }
                        },
                      ),
                      _ViewerAction(
                        icon: Icons.delete_outline_rounded,
                        label: s.delete,
                        onTap: () async {
                          if (await ItemActions.delete(context, [item])) {
                            if (context.mounted) {
                              AppFeedback.success(context, s.done);
                            }
                            if (mounted) {
                              _removeCurrent();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ImagePage extends StatelessWidget {
  const _ImagePage({super.key, required this.item, required this.bytes});

  final VaultItem item;
  final Future<Uint8List> bytes;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decode at up to 2× screen resolution: sharp when zoomed, bounded memory.
    final target = (size.longestSide * dpr * 2).round().clamp(1080, 4096);
    final sideways = item.rotation.isOdd;
    final landscape = item.width >= item.height;
    final decodeWidth = (landscape != sideways) ? target : null;
    final decodeHeight = decodeWidth == null ? target : null;

    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: IconSizes.xl),
              const SizedBox(height: Space.md),
              Text(context.s.errCorrupted,
                  style: const TextStyle(color: Colors.white70)),
            ]),
          );
        }
        final data = snap.data;
        return InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: RotatedBox(
              quarterTurns: item.rotation,
              child: data == null
                  ? Stack(alignment: Alignment.center, children: [
                      AspectRatio(
                        aspectRatio: item.width > 0 && item.height > 0
                            ? item.width / item.height
                            : 1,
                        child: VaultThumb.item(item.copyWith(rotation: 0)),
                      ),
                      const CircularProgressIndicator(),
                    ])
                  : Image.memory(
                      data,
                      fit: BoxFit.contain,
                      cacheWidth: decodeWidth,
                      cacheHeight: decodeHeight,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      semanticLabel: item.name,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _ViewerAction extends StatelessWidget {
  const _ViewerAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.lgAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch + 8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: Space.xxs),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}
