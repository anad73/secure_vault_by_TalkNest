import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../settings/settings_controller.dart';
import '../../viewer/media_viewer_screen.dart';
import '../data/album_repository.dart';
import '../data/item_repository.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';
import 'add_media_flow.dart';
import 'album_view_model.dart';
import 'home_screen.dart' show deleteAlbum, renameAlbum;
import 'item_actions.dart';
import 'widgets/media_tile.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key});

  static Future<void> open(BuildContext context, int albumId) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider(
        create: (c) => AlbumViewModel(
          albumId: albumId,
          albums: c.read<AlbumRepository>(),
          items: c.read<ItemRepository>(),
          vault: c.read<VaultService>(),
        )..refresh(),
        child: const AlbumScreen(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AlbumViewModel>();
    return PopScope(
      canPop: !vm.selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vm.clearSelection();
      },
      child: Scaffold(
        appBar: vm.selecting ? _SelectionAppBar(vm: vm) : _NormalAppBar(vm: vm),
        body: _Body(vm: vm),
        floatingActionButton: vm.selecting
            ? null
            : FloatingActionButton(
                tooltip: context.s.addToVault,
                onPressed: () =>
                    AddMediaFlow.start(context, albumId: vm.albumId),
                child: const Icon(Icons.add_rounded),
              ),
        bottomNavigationBar: AnimatedSwitcher(
          duration: Motion.medium,
          transitionBuilder: (child, anim) =>
              SizeTransition(sizeFactor: anim, child: child),
          child: vm.selecting ? _SelectionBar(vm: vm) : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _NormalAppBar extends StatefulWidget implements PreferredSizeWidget {
  const _NormalAppBar({required this.vm});

  final AlbumViewModel vm;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<_NormalAppBar> createState() => _NormalAppBarState();
}

class _NormalAppBarState extends State<_NormalAppBar> {
  bool _searching = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final vm = widget.vm;
    final album = vm.album;
    return AppBar(
      title: _searching
          ? TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: s.search,
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: vm.setQuery,
            )
          : Text(album?.name ?? ''),
      actions: [
        IconButton(
          tooltip: s.search,
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () {
            setState(() => _searching = !_searching);
            if (!_searching) {
              _controller.clear();
              vm.setQuery('');
            }
          },
        ),
        PopupMenuButton<ItemSort>(
          tooltip: s.sort,
          icon: const Icon(Icons.sort_rounded),
          initialValue: vm.sort,
          onSelected: vm.setSort,
          itemBuilder: (_) => [
            PopupMenuItem(
                value: ItemSort.newestAdded, child: Text(s.sortNewest)),
            PopupMenuItem(
                value: ItemSort.oldestAdded, child: Text(s.sortOldest)),
            PopupMenuItem(
                value: ItemSort.newestTaken, child: Text(s.sortTaken)),
            PopupMenuItem(value: ItemSort.name, child: Text(s.sortName)),
          ],
        ),
        if (album != null)
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                await renameAlbum(context, album);
              } else if (v == 'delete') {
                // byId() has no item count; read it from the full list.
                final all = await context.read<AlbumRepository>().all();
                if (!context.mounted) return;
                final full =
                    all.where((a) => a.id == album.id).firstOrNull ?? album;
                final deleted = await deleteAlbum(context, full);
                if (deleted && context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(s.renameAlbum)),
              PopupMenuItem(value: 'delete', child: Text(s.deleteAlbum)),
            ],
          ),
      ],
    );
  }
}

class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionAppBar({required this.vm});

  final AlbumViewModel vm;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AppBar(
      leading: IconButton(
        tooltip: s.close,
        icon: const Icon(Icons.close_rounded),
        onPressed: vm.clearSelection,
      ),
      title: Text(s.selectedCount(n: vm.selected.length)),
      actions: [
        IconButton(
          tooltip: s.selectAll,
          icon: const Icon(Icons.select_all_rounded),
          onPressed: () async {
            try {
              await vm.selectAll();
            } catch (e) {
              if (context.mounted) AppFeedback.error(context, e);
            }
          },
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vm});

  final AlbumViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final columns =
        context.select<SettingsController, int>((c) => c.value.gridColumns);
    if (vm.isInitialLoading) return SkeletonGrid(columns: columns);
    if (vm.error != null && vm.items.isEmpty) {
      return ErrorState(message: s.errUnknown, onRetry: vm.refresh);
    }
    if (vm.items.isEmpty) {
      return vm.query.isNotEmpty
          ? EmptyState(icon: Icons.search_off_rounded, title: s.noResults)
          : EmptyState(
              icon: Icons.add_photo_alternate_outlined,
              title: s.emptyAlbumTitle,
              message: s.emptyAlbumBody,
              action: FilledButton.icon(
                onPressed: () =>
                    AddMediaFlow.start(context, albumId: vm.albumId),
                icon: const Icon(Icons.add_rounded),
                label: Text(s.addToVault),
              ),
            );
    }
    return RefreshIndicator(
      onRefresh: vm.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 1200) vm.loadMore();
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(Dimens.gridSpacing),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: Dimens.gridSpacing,
                  crossAxisSpacing: Dimens.gridSpacing,
                ),
                itemCount: vm.items.length,
                itemBuilder: (context, i) {
                  final item = vm.items[i];
                  return MediaTile(
                    key: ValueKey(item.id),
                    item: item,
                    selected: vm.selected.contains(item.id),
                    selecting: vm.selecting,
                    onTap: () {
                      if (vm.selecting) {
                        Haptics.tap();
                        vm.toggle(item);
                      } else {
                        MediaViewerScreen.open(context,
                            items: vm.items, index: i);
                      }
                    },
                    onLongPress: () {
                      Haptics.tap();
                      vm.toggle(item);
                    },
                  );
                },
              ),
            ),
            if (vm.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(Space.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.vm});

  final AlbumViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final items = vm.selectedItems;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
        child: GlassPanel(
          borderRadius: Radii.xlAll,
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BarAction(
                icon: Icons.drive_file_move_outline,
                label: s.move,
                onTap: () =>
                    ItemActions.move(context, items, fromAlbum: vm.albumId),
              ),
              _BarAction(
                icon: Icons.lock_open_rounded,
                label: s.unhide,
                onTap: () => ItemActions.unhide(context, items),
              ),
              _BarAction(
                icon: Icons.ios_share_rounded,
                label: s.share,
                onTap: items.length > 20
                    ? null
                    : () => ItemActions.share(context, items),
              ),
              _BarAction(
                icon: Icons.delete_outline_rounded,
                label: s.delete,
                color: Theme.of(context).colorScheme.error,
                onTap: () => ItemActions.delete(context, items),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? Theme.of(context).disabledColor : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.lgAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch + 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: c),
              const SizedBox(height: Space.xxs),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: c)),
            ],
          ),
        ),
      ),
    );
  }
}
