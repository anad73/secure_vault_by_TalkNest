import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/debouncer.dart';
import '../data/album_repository.dart';
import '../data/item_repository.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';

/// Paged item grid for one album, with sorting, debounced search and
/// multi-selection.
class AlbumViewModel extends ChangeNotifier {
  AlbumViewModel({
    required this.albumId,
    required AlbumRepository albums,
    required ItemRepository items,
    required VaultService vault,
  })  : _albums = albums,
        _items = items,
        _vault = vault {
    _vault.addListener(_onVaultChanged);
  }

  final int albumId;
  final AlbumRepository _albums;
  final ItemRepository _items;
  final VaultService _vault;
  final Debouncer _searchDebounce =
      Debouncer(const Duration(milliseconds: 300));

  Album? _album;
  List<VaultItem> _list = const [];
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  ItemSort _sort = ItemSort.newestAdded;
  String _query = '';
  final Set<int> _selected = {};
  int _generation = 0;
  bool _disposed = false;

  Album? get album => _album;
  List<VaultItem> get items => _list;
  bool get isInitialLoading => _initialLoading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  Object? get error => _error;
  ItemSort get sort => _sort;
  String get query => _query;
  Set<int> get selected => _selected;
  bool get selecting => _selected.isNotEmpty;

  List<VaultItem> get selectedItems =>
      _list.where((e) => _selected.contains(e.id)).toList(growable: false);

  void _onVaultChanged() => refresh(keepSelection: true);

  /// Reloads from the first page. A generation counter drops results of
  /// stale requests (e.g. after the search text changed again).
  Future<void> refresh({bool keepSelection = false}) async {
    final gen = ++_generation;
    _error = null;
    if (!keepSelection) _selected.clear();
    _notify();
    try {
      final album = await _albums.byId(albumId);
      final first =
          await _items.page(albumId: albumId, sort: _sort, search: _query);
      if (gen != _generation || _disposed) return;
      _album = album;
      _list = first;
      _hasMore = first.length == ItemRepository.pageSize;
      _selected.retainAll(first.map((e) => e.id));
    } catch (e, st) {
      if (gen != _generation) return;
      AppLogger.error('Album', 'load failed', e, st);
      _error = e;
    } finally {
      if (gen == _generation) {
        _initialLoading = false;
        _notify();
      }
    }
  }

  /// Loads the next page; ignored while a page is already loading.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _list.isEmpty) return;
    _loadingMore = true;
    final gen = _generation;
    _notify();
    try {
      final next = await _items.page(
        albumId: albumId,
        sort: _sort,
        search: _query,
        after: _items.cursorFor(_list.last, _sort),
      );
      if (gen != _generation || _disposed) return;
      _list = [..._list, ...next];
      _hasMore = next.length == ItemRepository.pageSize;
    } catch (e, st) {
      AppLogger.error('Album', 'load more failed', e, st);
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  void setSort(ItemSort sort) {
    if (sort == _sort) return;
    _sort = sort;
    refresh();
  }

  void setQuery(String q) {
    _query = q;
    _searchDebounce(() => refresh());
  }

  void toggle(VaultItem item) {
    if (!_selected.remove(item.id)) _selected.add(item.id);
    _notify();
  }

  void clearSelection() {
    _selected.clear();
    _notify();
  }

  /// Selects every item in the album, including pages not loaded yet.
  Future<void> selectAll() async {
    final gen = _generation;
    final all = List.of(_list);
    var more = _hasMore && all.isNotEmpty;
    while (more) {
      final next = await _items.page(
        albumId: albumId,
        sort: _sort,
        search: _query,
        after: _items.cursorFor(all.last, _sort),
      );
      all.addAll(next);
      more = next.length == ItemRepository.pageSize;
    }
    if (gen != _generation || _disposed) return;
    _list = all;
    _hasMore = false;
    _selected.addAll(all.map((e) => e.id));
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce.dispose();
    _vault.removeListener(_onVaultChanged);
    super.dispose();
  }
}
