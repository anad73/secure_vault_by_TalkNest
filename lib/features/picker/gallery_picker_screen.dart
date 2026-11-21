import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/states.dart';
import '../auth/vault_session.dart';
import 'gallery_picker_view_model.dart';

/// Multi-select picker over the device gallery. Pops with the selected
/// [AssetEntity] list, or null when cancelled.
class GalleryPickerScreen extends StatelessWidget {
  const GalleryPickerScreen({super.key});

  static Future<List<AssetEntity>?> open(BuildContext context) {
    return Navigator.of(context).push(MaterialPageRoute<List<AssetEntity>>(
      builder: (_) => ChangeNotifierProvider(
        create: (c) => GalleryPickerViewModel(c.read<VaultSession>())..init(),
        child: const GalleryPickerScreen(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GalleryPickerViewModel>();
    final s = context.s;
    return Scaffold(
      appBar: AppBar(
        title: vm.status == PickerStatus.ready && vm.paths.length > 1
            ? _PathDropdown(vm: vm)
            : Text(s.pickerTitle),
        actions: [
          if (vm.status == PickerStatus.ready && vm.assets.isNotEmpty)
            IconButton(
              tooltip: s.selectAll,
              icon: const Icon(Icons.select_all_rounded),
              onPressed: vm.selectAllLoaded,
            ),
        ],
      ),
      body: switch (vm.status) {
        PickerStatus.checking => const SkeletonGrid(columns: 4, count: 24),
        PickerStatus.denied => EmptyState(
            icon: Icons.photo_library_outlined,
            title: s.permissionTitle,
            message: s.permissionBody,
            action: Wrap(spacing: Space.sm, children: [
              FilledButton(onPressed: vm.init, child: Text(s.grantAccess)),
              OutlinedButton(
                  onPressed: vm.openSettings, child: Text(s.openSettings)),
            ]),
          ),
        PickerStatus.error =>
          ErrorState(message: s.errUnknown, onRetry: vm.init),
        PickerStatus.ready => vm.assets.isEmpty && !vm.isLoading
            ? EmptyState(
                icon: Icons.image_not_supported_outlined, title: s.galleryEmpty)
            : _Grid(vm: vm),
      },
      bottomNavigationBar: AnimatedSwitcher(
        duration: Motion.medium,
        child: vm.selectedCount == 0
            ? const SizedBox.shrink()
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(vm.selection),
                    icon: const Icon(Icons.lock_rounded),
                    label: Text(s.hideCount(n: vm.selectedCount)),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PathDropdown extends StatelessWidget {
  const _PathDropdown({required this.vm});

  final GalleryPickerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<AssetPathEntity>(
        value: vm.current,
        isExpanded: true,
        borderRadius: Radii.mdAll,
        items: [
          for (final p in vm.paths)
            DropdownMenuItem(
              value: p,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (p) {
          if (p != null) vm.selectPath(p);
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.vm});

  final GalleryPickerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 800) vm.loadMore();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(Dimens.gridSpacing),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: Dimens.gridSpacing,
          crossAxisSpacing: Dimens.gridSpacing,
        ),
        itemCount: vm.assets.length,
        itemBuilder: (context, i) {
          final a = vm.assets[i];
          return _AssetTile(
            key: ValueKey(a.id),
            asset: a,
            selected: vm.isSelected(a),
            onTap: () => vm.toggle(a),
          );
        },
      ),
    );
  }
}

class _AssetTile extends StatefulWidget {
  const _AssetTile(
      {super.key,
      required this.asset,
      required this.selected,
      required this.onTap});

  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  late final Future<Uint8List?> _thumb = widget.asset
      .thumbnailDataWithSize(const ThumbnailSize.square(220), quality: 80);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = widget.asset;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: Motion.fast,
          scale: widget.selected ? 0.88 : 1,
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(widget.selected ? Radii.md : Radii.sm),
            child: Stack(fit: StackFit.expand, children: [
              FutureBuilder<Uint8List?>(
                future: _thumb,
                builder: (context, snap) => snap.data == null
                    ? ColoredBox(color: scheme.surfaceContainerHigh)
                    : Image.memory(snap.data!,
                        fit: BoxFit.cover, gaplessPlayback: true),
              ),
              if (a.type == AssetType.video)
                PositionedDirectional(
                  end: Space.xs,
                  bottom: Space.xs,
                  child: Text(
                    Fmt.duration(a.videoDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              PositionedDirectional(
                top: Space.xs,
                end: Space.xs,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected ? scheme.primary : Colors.black26,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: widget.selected
                      ? Icon(Icons.check_rounded,
                          size: 16, color: scheme.onPrimary)
                      : null,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
