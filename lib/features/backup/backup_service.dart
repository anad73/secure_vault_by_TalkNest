import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/progress.dart';
import '../../data/crypto/crypto_worker.dart';
import '../../data/crypto/key_wrapper.dart';
import '../../data/crypto/vault_cipher.dart';
import '../../data/storage/vault_paths.dart';
import '../auth/vault_session.dart';
import '../vault/data/album_repository.dart';
import '../vault/data/item_repository.dart';
import '../vault/data/vault_service.dart';
import '../vault/domain/models.dart';

/// Single-file encrypted backups.
///
/// ```text
/// "SGBK" | u8 version | u32 headerLen | header JSON
///   header = { v, created, count, key: <master key wrapped with the
///              backup password (PBKDF2 + AES-GCM)> }
/// per item:
///   u8 idLen | fileId (ascii hex)
///   u32 len | nonce | cipher | mac      item metadata (AES-GCM, master key)
///   u64 len | raw vault file            already encrypted, copied as-is
///   u64 len | raw thumbnail file        0 when there is no thumbnail
/// ```
/// Exporting never decrypts media, so it is fast and the plaintext never
/// touches disk. Importing re-encrypts each file with this vault's key.
class BackupService {
  BackupService({
    required VaultSession session,
    required VaultPaths paths,
    required AlbumRepository albums,
    required ItemRepository items,
    required VaultService vault,
    int? kdfIterations,
  })  : _iterations = kdfIterations ?? KeyWrapper.defaultIterations,
        _session = session,
        _paths = paths,
        _albums = albums,
        _items = items,
        _vault = vault;

  final VaultSession _session;
  final VaultPaths _paths;
  final AlbumRepository _albums;
  final ItemRepository _items;
  final VaultService _vault;
  final int _iterations;

  static const List<int> _magic = [0x53, 0x47, 0x42, 0x4B]; // SGBK
  static const int _version = 1;
  static const int _copyChunk = 1024 * 1024;
  static final AesGcm _aes = AesGcm.with256bits();

  /// Writes a backup of every item to the temp folder and returns its path.
  Future<String> export(String password, ProgressReporter report) async {
    final key = _session.key;
    final albums = {for (final a in await _albums.all()) a.id: a.name};
    final all = <VaultItem>[];
    for (final albumId in albums.keys) {
      all.addAll(await _items.allInAlbum(albumId));
    }
    final wrapped =
        await KeyWrapper.wrap(key, password, iterations: _iterations);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'SafeVault_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.svbk';
    final outPath = p.join(_paths.temp.path, name);
    final tmp = File('$outPath.part');
    final out = await tmp.open(mode: FileMode.write);
    var ok = false;
    try {
      await out.writeFrom(_magic);
      await out.writeFrom([_version]);
      final header = utf8.encode(jsonEncode({
        'v': _version,
        'created': now.millisecondsSinceEpoch,
        'count': all.length,
        'key': wrapped.toJson(),
      }));
      await out.writeFrom(_u32(header.length));
      await out.writeFrom(header);

      report(0, all.length);
      for (var i = 0; i < all.length; i++) {
        final item = all[i];
        final id = ascii.encode(item.fileId);
        await out.writeFrom([id.length]);
        await out.writeFrom(id);
        final meta = item.toEmbeddedMeta(albums[item.albumId] ?? '')
          ..['fav'] = item.favorite
          ..['added'] = item.addedAt.millisecondsSinceEpoch;
        await _writeMeta(out, key, item.fileId, meta);
        await _copyIn(out, File(_paths.mediaFile(item.fileId)));
        final thumb = File(_paths.thumbFile(item.fileId));
        if (item.hasThumb && await thumb.exists()) {
          await _copyIn(out, thumb);
        } else {
          await out.writeFrom(_u64(0));
        }
        report(i + 1, all.length);
      }
      await out.flush();
      ok = true;
    } finally {
      await out.close();
      if (!ok && await tmp.exists()) await tmp.delete();
    }
    await tmp.rename(outPath);
    return outPath;
  }

  /// Reads the backup header and checks the password. Returns the source
  /// master key. Wrong passwords do not count towards the PIN lockout.
  Future<(Uint8List, int)> _openHeader(
      RandomAccessFile f, String password) async {
    final magic = await f.read(4);
    final version = await f.read(1);
    if (magic.length != 4 ||
        !_listEq(magic, _magic) ||
        version.length != 1 ||
        version[0] != _version) {
      throw const AppException(AppErrorKind.invalidBackup);
    }
    final len = _readU32(await f.read(4));
    if (len <= 0 || len > 1024 * 1024) {
      throw const AppException(AppErrorKind.invalidBackup);
    }
    final header = jsonDecode(utf8.decode(await f.read(len)));
    if (header is! Map<String, Object?> ||
        header['key'] is! Map<String, Object?>) {
      throw const AppException(AppErrorKind.invalidBackup);
    }
    final wrapped = WrappedKey.fromJson(header['key']! as Map<String, Object?>);
    final count = (header['count'] as num?)?.toInt() ?? 0;
    return (await KeyWrapper.unwrap(wrapped, password), count);
  }

  /// Imports every item of a backup into this vault.
  Future<BatchResult> import(
      String path, String password, ProgressReporter report) async {
    final newKey = _session.key;
    final f = await File(path).open();
    var ok = 0, failed = 0;
    try {
      final total = await f.length();
      final (oldKey, count) = await _openHeader(f, password);
      var index = 0;
      report(0, count);
      final albumIds = <String, int>{};
      while (await f.position() < total) {
        final idLen = (await f.read(1)).first;
        final oldId = ascii.decode(await f.read(idLen));
        if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(oldId)) {
          throw const AppException(AppErrorKind.invalidBackup, 'bad id');
        }
        final meta = await _readMeta(f, oldKey, oldId);
        final mediaTemp = File(p.join(_paths.temp.path, 'imp_$oldId'));
        final thumbTemp = File(p.join(_paths.temp.path, 'imp_$oldId.t'));
        await _copyOut(f, mediaTemp);
        final hasThumb = await _copyOut(f, thumbTemp) > 0;
        final newId = VaultCipher.newFileId();
        try {
          final albumName = (meta['album'] as String?)?.trim() ?? '';
          final albumId = albumIds[albumName] ??=
              await _albums.ensure(albumName.isEmpty ? 'Backup' : albumName);
          await CryptoWorker.reencrypt(
            srcPath: mediaTemp.path,
            srcKey: oldKey,
            srcId: oldId,
            dstPath: _paths.mediaFile(newId),
            dstKey: newKey,
            dstId: newId,
            newMeta: meta,
          );
          var thumbOk = false;
          if (hasThumb) {
            final t = await VaultCipher.decryptToBytes(
                path: thumbTemp.path, key: oldKey, fileId: '$oldId.t');
            await VaultCipher.encryptBytes(
                data: t.bytes,
                dstPath: _paths.thumbFile(newId),
                key: newKey,
                fileId: '$newId.t');
            thumbOk = true;
          }
          final id = await _items
              .insert(NewItem.fromEmbeddedMeta(meta, newId, albumId, thumbOk));
          if (meta['fav'] == true) await _items.setFavorite(id, true);
          ok++;
        } catch (e, st) {
          failed++;
          AppLogger.error('Backup', 'item import failed', e, st);
          await _tryDelete(File(_paths.mediaFile(newId)));
          await _tryDelete(File(_paths.thumbFile(newId)));
        } finally {
          await _tryDelete(mediaTemp);
          await _tryDelete(thumbTemp);
        }
        index++;
        report(index, count < index ? index : count);
      }
    } on RangeError catch (e) {
      throw AppException(AppErrorKind.invalidBackup, 'truncated', e);
    } on StateError catch (e) {
      throw AppException(AppErrorKind.invalidBackup, 'truncated', e);
    } finally {
      await f.close();
      _vault.refresh();
    }
    return BatchResult(ok: ok, failed: failed);
  }

  // ------------------------------------------------------------- helpers

  Future<void> _writeMeta(RandomAccessFile out, Uint8List key, String id,
      Map<String, Object?> meta) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(utf8.encode(jsonEncode(meta)),
        secretKey: SecretKeyData(key),
        nonce: nonce,
        aad: utf8.encode('SGBK|$id'));
    await out.writeFrom(_u32(box.cipherText.length));
    await out.writeFrom(nonce);
    await out.writeFrom(box.cipherText);
    await out.writeFrom(box.mac.bytes);
  }

  Future<Map<String, Object?>> _readMeta(
      RandomAccessFile f, Uint8List key, String id) async {
    final len = _readU32(await f.read(4));
    if (len > 1024 * 1024) throw const AppException(AppErrorKind.invalidBackup);
    final nonce = await f.read(12);
    final cipher = await f.read(len);
    final mac = await f.read(16);
    if (nonce.length != 12 || cipher.length != len || mac.length != 16) {
      throw const AppException(AppErrorKind.invalidBackup, 'truncated meta');
    }
    try {
      final clear = await _aes.decrypt(
          SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
          secretKey: SecretKeyData(key),
          aad: utf8.encode('SGBK|$id'));
      final m = jsonDecode(utf8.decode(clear));
      if (m is! Map<String, Object?>) throw const FormatException();
      return m;
    } on SecretBoxAuthenticationError catch (e) {
      throw AppException(AppErrorKind.corruptedData, 'meta auth', e);
    } on FormatException catch (e) {
      throw AppException(AppErrorKind.invalidBackup, 'meta json', e);
    }
  }

  /// Appends `u64 length` + the file's bytes.
  Future<void> _copyIn(RandomAccessFile out, File src) async {
    final r = await src.open();
    try {
      final len = await r.length();
      await out.writeFrom(_u64(len));
      var left = len;
      while (left > 0) {
        final chunk = await r.read(left < _copyChunk ? left : _copyChunk);
        if (chunk.isEmpty) {
          throw const AppException(AppErrorKind.fileNotFound, 'short');
        }
        await out.writeFrom(chunk);
        left -= chunk.length;
      }
    } finally {
      await r.close();
    }
  }

  /// Reads `u64 length` + bytes into [dst]. Returns the length.
  Future<int> _copyOut(RandomAccessFile f, File dst) async {
    final len = _readU64(await f.read(8));
    final w = await dst.open(mode: FileMode.write);
    try {
      var left = len;
      while (left > 0) {
        final chunk = await f.read(left < _copyChunk ? left : _copyChunk);
        if (chunk.isEmpty) {
          throw const AppException(AppErrorKind.invalidBackup, 'eof');
        }
        await w.writeFrom(chunk);
        left -= chunk.length;
      }
    } finally {
      await w.close();
    }
    return len;
  }

  Future<void> _tryDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Wiped with the temp folder later.
    }
  }

  static Uint8List _u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
  static Uint8List _u64(int v) =>
      (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();

  static int _readU32(Uint8List b) {
    if (b.length != 4) {
      throw const AppException(AppErrorKind.invalidBackup, 'eof');
    }
    return ByteData.sublistView(b).getUint32(0, Endian.big);
  }

  static int _readU64(Uint8List b) {
    if (b.length != 8) {
      throw const AppException(AppErrorKind.invalidBackup, 'eof');
    }
    return ByteData.sublistView(b).getUint64(0, Endian.big);
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
