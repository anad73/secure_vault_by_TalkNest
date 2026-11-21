import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/formatters.dart';
import '../vault/data/vault_service.dart';
import '../vault/domain/models.dart';
import '../vault/presentation/widgets/vault_thumb.dart';

/// Video and audio playback. The file is decrypted into private temp
/// storage only while this page is the active one, and deleted on dispose.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, required this.active});

  final VaultItem item;
  final bool active;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  File? _temp;
  bool _failed = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void didUpdateWidget(covariant PlayerPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _start();
    } else if (!widget.active && old.active) {
      _controller?.pause();
    }
  }

  Future<void> _start() async {
    if (_controller != null || _starting || !mounted) return;
    _starting = true;
    final vault = context.read<VaultService>();
    try {
      final file = await vault.decryptToTemp(widget.item);
      _temp = file;
      final c = VideoPlayerController.file(file);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _controller = c);
      await c.play();
    } catch (e, st) {
      AppLogger.error('Player', 'playback failed', e, st);
      if (mounted) setState(() => _failed = true);
    } finally {
      _starting = false;
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _controller;
    c?.removeListener(_onTick);
    c?.dispose();
    final t = _temp;
    if (t != null) {
      t.delete().catchError((Object _) => t);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = _controller;
    final isAudio = widget.item.kind == MediaKind.audio;

    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.white70, size: IconSizes.xl),
          const SizedBox(height: Space.md),
          Text(s.videoError, style: const TextStyle(color: Colors.white70)),
        ]),
      );
    }

    final Widget visual;
    if (isAudio) {
      visual = Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 180,
          height: 180,
          decoration: const BoxDecoration(
              gradient: Brand.accent, shape: BoxShape.circle),
          child: const Icon(Icons.music_note_rounded,
              color: Colors.white, size: 88),
        ),
        const SizedBox(height: Space.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Text(widget.item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white)),
        ),
      ]);
    } else if (c == null) {
      visual = Stack(alignment: Alignment.center, children: [
        AspectRatio(
          aspectRatio: widget.item.width > 0 && widget.item.height > 0
              ? widget.item.width / widget.item.height
              : 16 / 9,
          child: VaultThumb.item(widget.item),
        ),
        const CircularProgressIndicator(),
      ]);
    } else {
      visual =
          AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
    }

    return Stack(children: [
      Center(child: visual),
      if (c != null)
        Positioned(
          left: Space.lg,
          right: Space.lg,
          bottom: 110,
          child:
              _Controls(controller: c, playLabel: s.play, pauseLabel: s.pause),
        ),
      if (c == null && isAudio && widget.active)
        const Positioned(
          left: 0,
          right: 0,
          bottom: 140,
          child: Center(child: CircularProgressIndicator()),
        ),
    ]);
  }
}

class _Controls extends StatelessWidget {
  const _Controls(
      {required this.controller,
      required this.playLabel,
      required this.pauseLabel});

  final VideoPlayerController controller;
  final String playLabel;
  final String pauseLabel;

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    final total = v.duration.inMilliseconds;
    final pos = v.position.inMilliseconds.clamp(0, total == 0 ? 1 : total);
    const white = TextStyle(color: Colors.white, fontSize: 12);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        IconButton(
          tooltip: v.isPlaying ? pauseLabel : playLabel,
          iconSize: IconSizes.lg,
          color: Colors.white,
          icon: Icon(
              v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: () => v.isPlaying ? controller.pause() : controller.play(),
        ),
        Text(Fmt.duration(v.position), style: white),
        Expanded(
          child: Slider(
            value: total == 0 ? 0 : pos / total,
            onChanged: total == 0
                ? null
                : (f) => controller
                    .seekTo(Duration(milliseconds: (f * total).round())),
          ),
        ),
        Text(Fmt.duration(v.duration), style: white),
      ]),
    );
  }
}
