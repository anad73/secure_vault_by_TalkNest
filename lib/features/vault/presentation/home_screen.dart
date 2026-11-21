import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../auth/vault_session.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/album_repository.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';
import 'add_media_flow.dart';
import 'album_chooser.dart';
import 'album_screen.dart';
import 'home_view_model.dart';
import 'widgets/album_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (c) =>
          HomeViewModel(c.read<AlbumRepository>(), c.read<VaultService>()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final vm = context.read<HomeViewModel>();
    final fallback = context.s.recoveredAlbumName;
    await vm.load();
    final report = await vm.backgroundIntegrityCheck(fallback);
    if (!mounted || report == null) return;
    if (report.recovered > 0 || report.removed > 0) {
      AppFeedback.info(
        context,
        context.s.integrityResult(
            n: report.checked, r: report.recovered, m: report.removed),
      );
    }
  }

  Future<void> _albumMenu(Album album) async {
    final s = context.s;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(album.name, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text(s.itemCount(n: album.itemCount)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(s.renameAlbum),
            onTap: () => Navigator.of(ctx).pop('rename'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded,
                color: Theme.of(ctx).colorScheme.error),
            title: Text(s.deleteAlbum,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () => Navigator.of(ctx).pop('delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') await renameAlbum(context, album);
    if (action == 'delete' && mounted) await deleteAlbum(context, album);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final vm = context.watch<HomeViewModel>();
    final albums = vm.albums;

    Widget body;
    if (vm.isLoading) {
      body = const SliverFillRemaining(
          hasScrollBody: true, child: SkeletonAlbums());
    } else if (vm.error != null && albums == null) {
      body = SliverFillRemaining(
        child: ErrorState(message: s.errUnknown, onRetry: vm.load),
      );
    } else {
      final list = albums ?? const <Album>[];
      body = SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(
          child: _SummaryCard(count: vm.fileCount, bytes: vm.totalBytes),
        ),
        if (vm.fileCount == 0)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 280,
              child: EmptyState(
                icon: Icons.lock_outline_rounded,
                title: s.emptyVaultTitle,
                message: s.emptyVaultBody,
              ),
            ),
          ),
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.md, Space.sm),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Expanded(
                  child: Text(s.albums,
                      style: Theme.of(context).textTheme.titleLarge)),
              TextButton.icon(
                onPressed: () => AlbumChooser.createAlbum(context),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(s.newAlbum),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, 120),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: Space.lg,
              crossAxisSpacing: Space.lg,
              childAspectRatio: 0.82,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final a = list[i];
              return AlbumCard(
                key: ValueKey(a.id),
                album: a,
                onTap: () => AlbumScreen.open(context, a.id),
                onLongPress: () => _albumMenu(a),
              );
            },
          ),
        ),
      ]);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.medium(
              title: Text(s.appName),
              actions: [
                IconButton(
                  tooltip: s.lockNow,
                  icon: const Icon(Icons.lock_outline_rounded),
                  onPressed: () => context.read<VaultSession>().lock(),
                ),
                IconButton(
                  tooltip: s.settings,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen()),
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
            ),
            body,
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddMediaFlow.start(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(s.addToVault),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.bytes});

  final int count;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Brand.accent,
          borderRadius: Radii.xlAll,
          boxShadow: [
            BoxShadow(
              color: Brand.accentA.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: Radii.mdAll,
              ),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: IconSizes.lg),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.s
                          .storageSummary(n: count, size: Fmt.bytes(bytes)),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(
                      'AES-256-GCM',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Shared album actions (also used from the album screen).
Future<void> renameAlbum(BuildContext context, Album album) async {
  final s = context.s;
  final vault = context.read<VaultService>();
  final others = {
    for (final a in await context.read<AlbumRepository>().all())
      if (a.id != album.id) a.name.toLowerCase()
  };
  if (!context.mounted) return;
  final name = await AppFeedback.prompt(
    context,
    title: s.renameAlbum,
    label: s.albumName,
    initial: album.name,
    confirmLabel: s.save,
    validator: (v) {
      if (v.isEmpty) return s.nameEmpty;
      if (others.contains(v.toLowerCase())) return s.nameExists;
      return null;
    },
  );
  if (name == null || name == album.name) return;
  try {
    await vault.renameAlbum(album.id, name);
  } catch (e) {
    if (context.mounted) AppFeedback.error(context, e);
  }
}

/// Returns true when the album was deleted.
Future<bool> deleteAlbum(BuildContext context, Album album) async {
  final s = context.s;
  final vault = context.read<VaultService>();
  final ok = await AppFeedback.confirm(
    context,
    title: s.deleteAlbum,
    message:
        '${s.deleteAlbumConfirm(name: album.name, n: album.itemCount)}\n${s.deleteConfirmBody}',
    confirmLabel: s.delete,
    destructive: true,
    icon: Icons.delete_forever_rounded,
  );
  if (!ok || !context.mounted) return false;
  try {
    await runWithProgress(
      context,
      label: (s, d, t) => s.deletingProgress(done: d, total: t),
      task: (report) => vault.deleteAlbum(album.id, report),
    );
    return true;
  } catch (e) {
    if (context.mounted) AppFeedback.error(context, e);
    return false;
  }
}
