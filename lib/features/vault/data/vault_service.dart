import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/progress.dart';
import '../../../data/crypto/crypto_worker.dart';
import '../../../data/crypto/vault_cipher.dart';
import '../../../data/storage/vault_paths.dart';
import '../../auth/vault_session.dart';
import '../domain/models.dart';
import 'album_repository.dart';
import 'item_repository.dart';
import 'thumbnail_cache.dart';

/// Outcome of a batch operation. Never reports success for a failed item.
class BatchResult {
  const BatchResult(
      {required this.ok, required this.failed, this.sourceIds = const []});

  final int ok;
  final int failed;

  /// Gallery asset ids that were hidden successfully (for deleting originals).
  final List<String> sourceIds;
}

class IntegrityReport {
  const IntegrityReport(
      {required this.checked, required this.recovered, required this.removed});

  final int checked;
  final int recovered;
  final int removed;
}

/// A file chosen through the system file picker (audio import).
class PickedSource {
  const PickedSource({required this.path, required this.name});

  final String path;
  final String name;
}

/// Business logic for the vault: hiding, unhiding, deleting, moving and
/// self-repair. Notifies listeners after every mutation so view-models can
/// reload only what they show.
class VaultService extends ChangeNotifier {
  VaultService({
    required VaultSession session,
    required VaultPaths paths,
    required AlbumRepository albums,
    required ItemRepository items,
    required ThumbnailCache thumbs,
  })  : _session = session,
        _paths = paths,
        _albums = albums,
        _items = items,
        _thumbs = thumbs;

  final VaultSession _session;
  final VaultPaths _paths;
  final AlbumRepository _albums;
  final ItemRepository _items;
  final ThumbnailCache _thumbs;

  static const _tag = 'Vault';

  VaultPaths get paths => _paths;

  /// Tells listeners that vault content changed outside this class
  /// (e.g. a backup import).
  void refresh() => notifyListeners();

  // ------------------------------------------------------------------ read

  // These are `async` so a locked vault surfaces as a failed Future
  // instead of a synchronous throw inside widget lifecycle methods.

  Future<Uint8List?> thumbnail(VaultItem item) async {
    if (!item.hasThumb) return null;
    return _thumbs.load(
        item.fileId, _paths.thumbFile(item.fileId), _session.key);
  }

  Future<Uint8List?> thumbnailById(String fileId) async =>
      _thumbs.load(fileId, _paths.thumbFile(fileId), _session.key);

  /// Full decrypted bytes (images). Runs on a background isolate.
  Future<Uint8List> readBytes(VaultItem item) async =>
      CryptoWorker.decryptBytes(
          path: _paths.mediaFile(item.fileId),
          key: _session.key,
          fileId: item.fileId);

  /// Decrypts into the private temp folder (video/audio playback, sharing).
  /// The caller deletes the file when done; all temp files are also wiped
  /// on lock and on start.
  Future<File> decryptToTemp(VaultItem item) async {
    final out = _paths.tempFile(item.fileId, item.name);
    if (await File(out).exists()) return File(out);
    await CryptoWorker.decryptToFile(
        srcPath: _paths.mediaFile(item.fileId),
        dstPath: out,
        key: _session.key,
        fileId: item.fileId);
    return File(out);
  }

  // ------------------------------------------------------------------ hide

  Future<BatchResult> hideAssets(
      List<AssetEntity> assets, int albumId, ProgressReporter report) async {
    final key = _session.key;
    final albumName = (await _albums.byId(albumId))?.name ?? '';
    var ok = 0, failed = 0;
    final hidden = <String>[];
    report(0, assets.length);
    for (var i = 0; i < assets.length; i++) {
      try {
        await _hideAsset(assets[i], albumId, albumName, key);
        ok++;
        hidden.add(assets[i].id);
      } catch (e, st) {
        failed++;
        AppLogger.error(_tag, 'hide failed', e, st);
      }
      report(i + 1, assets.length);
    }
    notifyListeners();
    return BatchResult(ok: ok, failed: failed, sourceIds: hidden);
  }

  Future<void> _hideAsset(
      AssetEntity a, int albumId, String albumName, Uint8List key) async {
    final kind = a.type == AssetType.video ? MediaKind.video : MediaKind.image;
    final file = await a.originFile;
    if (file == null || !await file.exists()) {
      throw const AppException(AppErrorKind.fileNotFound, 'originFile null');
    }
    var name = await a.titleAsync;
    if (name.trim().isEmpty) name = p.basename(file.path);
    final mime = await a.mimeTypeAsync ?? _mimeFromName(name, kind);
    final fileId = VaultCipher.newFileId();
    var item = NewItem(
      albumId: albumId,
      fileId: fileId,
      kind: kind,
      name: name,
      mime: mime,
      size: await file.length(),
      takenAt: a.createDateTime,
      width: a.width,
      height: a.height,
      durationMs: a.videoDuration.inMilliseconds,
    );
    try {
      await CryptoWorker.encryptFile(
        srcPath: file.path,
        dstPath: _paths.mediaFile(fileId),
        key: key,
        fileId: fileId,
        meta: item.toEmbeddedMeta(albumName),
      );
      final thumb = await _safeThumb(a);
      if (thumb != null) {
        await VaultCipher.encryptBytes(
            data: thumb,
            dstPath: _paths.thumbFile(fileId),
            key: key,
            fileId: '$fileId.t');
        item = item.withThumb(true);
      }
      await _items.insert(item);
    } catch (_) {
      await _deleteFiles(fileId);
      rethrow;
    } finally {
      await _deleteIfCacheCopy(file);
    }
  }

  Future<Uint8List?> _safeThumb(AssetEntity a) async {
    try {
      return await a.thumbnailDataWithSize(const ThumbnailSize.square(320),
          quality: 82);
    } catch (e) {
      AppLogger.warn(_tag, 'thumbnail generation failed');
      return null;
    }
  }

  /// Removes the hidden originals from the gallery. Android shows its own
  /// confirmation dialog (MediaStore delete request) on Android 11+.
  Future<int> deleteOriginals(List<String> assetIds) async {
    if (assetIds.isEmpty) return 0;
    try {
      final deleted = await _session
          .runExternal(() => PhotoManager.editor.deleteWithIds(assetIds));
      return deleted.length;
    } catch (e, st) {
      AppLogger.error(_tag, 'delete originals failed', e, st);
      return 0;
    }
  }

  /// Imports files picked with the system picker (audio).
  Future<BatchResult> importFiles(List<PickedSource> files, MediaKind kind,
      int albumId, ProgressReporter report) async {
    final key = _session.key;
    final albumName = (await _albums.byId(albumId))?.name ?? '';
    var ok = 0, failed = 0;
    report(0, files.length);
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final fileId = VaultCipher.newFileId();
      try {
        final src = File(f.path);
        final stat = await src.stat();
        final item = NewItem(
          albumId: albumId,
          fileId: fileId,
          kind: kind,
          name: f.name,
          mime: _mimeFromName(f.name, kind),
          size: stat.size,
          takenAt: stat.modified,
        );
        await CryptoWorker.encryptFile(
          srcPath: f.path,
          dstPath: _paths.mediaFile(fileId),
          key: key,
          fileId: fileId,
          meta: item.toEmbeddedMeta(albumName),
        );
        await _items.insert(item);
        ok++;
      } catch (e, st) {
        failed++;
        await _deleteFiles(fileId);
        AppLogger.error(_tag, 'import failed', e, st);
      }
      report(i + 1, files.length);
    }
    try {
      // file_picker keeps plaintext copies in the cache; remove them.
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {
      // Best effort: the OS also clears the cache folder.
    }
    notifyListeners();
    return BatchResult(ok: ok, failed: failed);
  }

  // ---------------------------------------------------------------- unhide

  /// Restores items: photos/videos into the gallery, audio via the system
  /// "save as" dialog. Items are removed from the vault only after the
  /// restored copy was written successfully.
  Future<BatchResult> unhide(
      List<VaultItem> items, ProgressReporter report) async {
    var ok = 0, failed = 0;
    final removed = <VaultItem>[];
    report(0, items.length);
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      File? temp;
      try {
        temp = await decryptToTemp(item);
        final saved = await _restore(item, temp);
        if (saved) {
          await _deleteFiles(item.fileId);
          removed.add(item);
          ok++;
        } else {
          failed++;
        }
      } catch (e, st) {
        failed++;
        AppLogger.error(_tag, 'unhide failed', e, st);
      } finally {
        await _tryDelete(temp);
      }
      report(i + 1, items.length);
    }
    await _items.deleteAll(removed.map((e) => e.id).toList());
    _thumbs.evict(removed.map((e) => e.fileId));
    notifyListeners();
    return BatchResult(ok: ok, failed: failed);
  }

  Future<bool> _restore(VaultItem item, File temp) async {
    switch (item.kind) {
      case MediaKind.image:
        await PhotoManager.editor
            .saveImageWithPath(temp.path, title: item.name);
        return true;
      case MediaKind.video:
        await PhotoManager.editor.saveVideo(temp, title: item.name);
        return true;
      case MediaKind.audio:
        final bytes = await temp.readAsBytes();
        final path =
            await _session.runExternal(() => FilePicker.platform.saveFile(
                  fileName: item.name,
                  bytes: bytes,
                ));
        return path != null;
    }
  }

  // ------------------------------------------------------- delete / move

  Future<BatchResult> delete(
      List<VaultItem> items, ProgressReporter report) async {
    var ok = 0, failed = 0;
    final removed = <int>[];
    report(0, items.length);
    for (var i = 0; i < items.length; i++) {
      try {
        // Files first: if the app dies midway, the integrity check removes
        // rows whose file is gone rather than resurrecting deleted media.
        await _deleteFiles(items[i].fileId);
        removed.add(items[i].id);
        ok++;
      } catch (e, st) {
        failed++;
        AppLogger.error(_tag, 'delete failed', e, st);
      }
      report(i + 1, items.length);
    }
    await _items.deleteAll(removed);
    _thumbs.evict(items.map((e) => e.fileId));
    notifyListeners();
    return BatchResult(ok: ok, failed: failed);
  }

  Future<void> move(List<VaultItem> items, int albumId) async {
    await _items.moveAll(items.map((e) => e.id).toList(), albumId);
    notifyListeners();
  }

  Future<VaultItem> rotate(VaultItem item) async {
    final next = item.copyWith(rotation: (item.rotation + 1) % 4);
    await _items.setRotation(item.id, next.rotation);
    notifyListeners();
    return next;
  }

  Future<VaultItem> toggleFavorite(VaultItem item) async {
    final next = item.copyWith(favorite: !item.favorite);
    await _items.setFavorite(item.id, next.favorite);
    notifyListeners();
    return next;
  }

  // ---------------------------------------------------------------- albums

  Future<int> createAlbum(String name) async {
    final id = await _albums.create(name);
    notifyListeners();
    return id;
  }

  Future<void> renameAlbum(int id, String name) async {
    await _albums.rename(id, name);
    notifyListeners();
  }

  Future<void> deleteAlbum(int albumId, ProgressReporter report) async {
    final items = await _items.allInAlbum(albumId);
    final result = await delete(items, report);
    if (result.failed > 0) {
      throw AppException(
          AppErrorKind.unknown, '${result.failed} files not deleted');
    }
    await _albums.delete(albumId);
    notifyListeners();
  }

  Future<bool> albumNameExists(String name, {int? exceptId}) async {
    final a = await _albums.byName(name.trim());
    return a != null && a.id != exceptId;
  }

  // ------------------------------------------------------------ integrity

  /// Reconciles files on disk with database rows:
  /// * re-registers encrypted files that have no row (using their embedded
  ///   metadata),
  /// * removes rows whose file is missing,
  /// * deletes half-written `.part` files and orphaned thumbnails.
  Future<IntegrityReport> checkIntegrity(
      {required String fallbackAlbumName}) async {
    final key = _session.key;
    final dbIds = (await _items.allFileIds()).toSet();
    final diskIds = <String>{};
    var recovered = 0;

    await for (final e in _paths.media.list(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (name.endsWith('.part')) {
        await _tryDelete(e);
        continue;
      }
      diskIds.add(name);
      if (dbIds.contains(name)) continue;
      try {
        final meta =
            await CryptoWorker.readMeta(path: e.path, key: key, fileId: name);
        final albumName = (meta['album'] as String?)?.trim();
        final albumId = await _albums.ensure(
            albumName == null || albumName.isEmpty
                ? fallbackAlbumName
                : albumName);
        final hasThumb = await File(_paths.thumbFile(name)).exists();
        await _items
            .insert(NewItem.fromEmbeddedMeta(meta, name, albumId, hasThumb));
        recovered++;
      } catch (_) {
        // Not decryptable with this vault's key (or damaged). Leave it in
        // place so nothing is ever destroyed automatically.
        AppLogger.warn(_tag, 'unrecoverable orphan file skipped');
      }
    }

    final missing = dbIds.difference(diskIds).toList();
    if (missing.isNotEmpty) {
      await _items.deleteByFileIds(missing);
      for (final id in missing) {
        await _tryDelete(File(_paths.thumbFile(id)));
      }
    }

    await for (final e in _paths.thumbs.list(followLinks: false)) {
      if (e is File && !diskIds.contains(p.basename(e.path))) {
        await _tryDelete(e);
      }
    }

    if (recovered > 0 || missing.isNotEmpty) notifyListeners();
    return IntegrityReport(
        checked: diskIds.length, recovered: recovered, removed: missing.length);
  }

  // ---------------------------------------------------------------- stats

  Future<(int count, int bytes)> stats() async =>
      (await _items.totalCount(), await _items.totalSize());

  // -------------------------------------------------------------- helpers

  Future<void> _deleteFiles(String fileId) async {
    await _tryDelete(File(_paths.mediaFile(fileId)));
    await _tryDelete(File(_paths.thumbFile(fileId)));
  }

  Future<void> _tryDelete(FileSystemEntity? f) async {
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      AppLogger.warn(_tag, 'delete failed: ${e.osError?.errorCode}');
    }
  }

  /// photo_manager may hand back a copy in our cache folder (scoped
  /// storage); that plaintext copy must not linger.
  Future<void> _deleteIfCacheCopy(File f) async {
    final cacheRoot = _paths.temp.parent.path;
    if (p.isWithin(cacheRoot, f.path)) await _tryDelete(f);
  }

  static String _mimeFromName(String name, MediaKind kind) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'mp4': 'video/mp4',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      '3gp': 'video/3gpp',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'opus': 'audio/opus',
      'flac': 'audio/flac',
      'amr': 'audio/amr',
    };
    final known = map[ext];
    if (known != null) return known;
    return switch (kind) {
      MediaKind.image => 'image/*',
      MediaKind.video => 'video/*',
      MediaKind.audio => 'audio/*',
    };
  }
}
