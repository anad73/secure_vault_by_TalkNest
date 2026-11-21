import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/logging/app_logger.dart';
import '../auth/vault_session.dart';

enum PickerStatus { checking, denied, ready, error }

/// Device gallery browsing with paging (80 assets per page).
class GalleryPickerViewModel extends ChangeNotifier {
  GalleryPickerViewModel(this._session);

  final VaultSession _session;
  static const int pageSize = 80;

  PickerStatus _status = PickerStatus.checking;
  List<AssetPathEntity> _paths = const [];
  AssetPathEntity? _current;
  List<AssetEntity> _assets = const [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  int _generation = 0;
  bool _disposed = false;
  final Map<String, AssetEntity> _selected = {};

  PickerStatus get status => _status;
  List<AssetPathEntity> get paths => _paths;
  AssetPathEntity? get current => _current;
  List<AssetEntity> get assets => _assets;
  bool get hasMore => _hasMore;
  bool get isLoading => _loading;
  int get selectedCount => _selected.length;
  bool isSelected(AssetEntity a) => _selected.containsKey(a.id);
  List<AssetEntity> get selection => _selected.values.toList(growable: false);

  Future<void> init() async {
    _status = PickerStatus.checking;
    _notify();
    try {
      final ps =
          await _session.runExternal(PhotoManager.requestPermissionExtend);
      if (!ps.hasAccess) {
        _status = PickerStatus.denied;
        _notify();
        return;
      }
      _paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false)
          ],
        ),
      );
      _status = PickerStatus.ready;
      if (_paths.isNotEmpty) {
        await selectPath(_paths.first);
      } else {
        _notify();
      }
    } catch (e, st) {
      AppLogger.error('Picker', 'init failed', e, st);
      _status = PickerStatus.error;
      _notify();
    }
  }

  Future<void> openSettings() => _session.runExternal(PhotoManager.openSetting);

  Future<void> selectPath(AssetPathEntity path) async {
    _current = path;
    _assets = const [];
    _page = 0;
    _hasMore = true;
    _generation++;
    _notify();
    await loadMore();
  }

  Future<void> loadMore() async {
    final path = _current;
    if (path == null || _loading || !_hasMore) return;
    _loading = true;
    final gen = _generation;
    _notify();
    try {
      final next = await path.getAssetListPaged(page: _page, size: pageSize);
      if (gen != _generation || _disposed) return;
      _assets = [..._assets, ...next];
      _page++;
      _hasMore = next.length == pageSize;
    } catch (e, st) {
      AppLogger.error('Picker', 'page load failed', e, st);
      _hasMore = false;
    } finally {
      _loading = false;
      _notify();
    }
  }

  void toggle(AssetEntity a) {
    if (_selected.remove(a.id) == null) _selected[a.id] = a;
    _notify();
  }

  void selectAllLoaded() {
    for (final a in _assets) {
      _selected[a.id] = a;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
