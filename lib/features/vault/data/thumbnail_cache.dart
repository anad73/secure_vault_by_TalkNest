import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/logging/app_logger.dart';
import '../../../data/crypto/vault_cipher.dart';

/// In-memory LRU cache of decrypted thumbnails.
///
/// Thumbnails are small (~20–40 KB), so they are decrypted on the UI
/// isolate; spawning an isolate per thumbnail would cost more than the
/// decryption. Concurrent requests for the same id share one future.
class ThumbnailCache {
  ThumbnailCache({this.maxEntries = 400});

  final int maxEntries;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inFlight = {};

  Uint8List? peek(String fileId) {
    final v = _cache.remove(fileId);
    if (v != null) _cache[fileId] = v; // mark as recently used
    return v;
  }

  Future<Uint8List?> load(String fileId, String path, Uint8List key) {
    final hit = peek(fileId);
    if (hit != null) return Future.value(hit);
    return _inFlight.putIfAbsent(fileId, () async {
      try {
        if (!await File(path).exists()) return null;
        final blob = await VaultCipher.decryptToBytes(
            path: path, key: key, fileId: '$fileId.t');
        _cache[fileId] = blob.bytes;
        while (_cache.length > maxEntries) {
          _cache.remove(_cache.keys.first);
        }
        return blob.bytes;
      } catch (e, st) {
        AppLogger.warn('Thumbs', 'thumbnail decrypt failed: ${e.runtimeType}');
        AppLogger.error('Thumbs', 'detail', e, st);
        return null;
      } finally {
        _inFlight.remove(fileId);
      }
    });
  }

  void evict(Iterable<String> fileIds) {
    for (final id in fileIds) {
      _cache.remove(id);
    }
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}
