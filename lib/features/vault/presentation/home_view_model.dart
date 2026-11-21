import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../data/album_repository.dart';
import '../data/vault_service.dart';
import '../domain/models.dart';

/// Albums list + storage summary for the home screen.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(this._albums, this._vault) {
    _vault.addListener(_onVaultChanged);
  }

  final AlbumRepository _albums;
  final VaultService _vault;

  List<Album>? _items;
  Object? _error;
  bool _loading = false;
  bool _reloadQueued = false;
  bool _disposed = false;
  (int, int) _stats = (0, 0);

  List<Album>? get albums => _items;
  Object? get error => _error;
  bool get isLoading => _loading && _items == null;
  int get fileCount => _stats.$1;
  int get totalBytes => _stats.$2;

  void _onVaultChanged() => load();

  /// Loads albums. Calls made while a load is running are coalesced into
  /// one follow-up load (no duplicate queries).
  Future<void> load() async {
    if (_loading) {
      _reloadQueued = true;
      return;
    }
    _loading = true;
    _error = null;
    if (_items == null) _notify();
    try {
      final result = await _albums.all();
      final stats = await _vault.stats();
      _items = result;
      _stats = stats;
    } catch (e, st) {
      AppLogger.error('Home', 'load failed', e, st);
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
    if (_reloadQueued) {
      _reloadQueued = false;
      await load();
    }
  }

  /// Silent background repair after unlock; reloads if anything changed.
  Future<IntegrityReport?> backgroundIntegrityCheck(
      String fallbackAlbumName) async {
    try {
      return await _vault.checkIntegrity(fallbackAlbumName: fallbackAlbumName);
    } catch (e, st) {
      AppLogger.error('Home', 'integrity check failed', e, st);
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _vault.removeListener(_onVaultChanged);
    super.dispose();
  }
}
