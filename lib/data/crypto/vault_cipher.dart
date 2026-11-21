import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/errors/app_exception.dart';

/// Result of decrypting a vault file fully into memory.
class DecryptedBlob {
  const DecryptedBlob(this.meta, this.bytes);
  final Map<String, Object?> meta;
  final Uint8List bytes;
}

/// Chunked AES-256-GCM file format used for every file stored in the vault.
///
/// Layout:
/// ```text
/// "SGV1"                                   4-byte magic
/// record 0 : metadata JSON (encrypted)
/// record 1..n : file data, max 1 MiB each (encrypted)
/// record    = [u32 BE cipherLen][12-byte nonce][cipher][16-byte GCM tag]
/// ```
/// Every record's associated data binds the file id, record index and a
/// "final record" flag, which detects swapping, reordering and truncation.
/// There is always at least one data record, even for empty files.
///
/// All methods are pure Dart and safe to call from a background isolate.
abstract final class VaultCipher {
  static const List<int> _magic = [0x53, 0x47, 0x56, 0x31];
  static const int chunkSize = 1024 * 1024;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _maxRecord = chunkSize + 64 * 1024;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _random = Random.secure();

  /// New random 256-bit key.
  static Uint8List generateKey() => randomBytes(32);

  static Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// 128-bit random id, hex encoded. Used as the on-disk file name.
  static String newFileId() {
    final b = randomBytes(16);
    final sb = StringBuffer();
    for (final v in b) {
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static List<int> _aad(String id, int index, bool last) =>
      utf8.encode('SGV1|$id|$index|${last ? 1 : 0}');

  // ---------------------------------------------------------------- encrypt

  /// Encrypts [srcPath] into [dstPath], streaming in 1 MiB chunks.
  static Future<void> encryptFile({
    required String srcPath,
    required String dstPath,
    required Uint8List key,
    required String fileId,
    required Map<String, Object?> meta,
  }) async {
    final src = await File(srcPath).open();
    try {
      final total = await src.length();
      await _writeAtomically(dstPath, (out) async {
        final sk = SecretKeyData(key);
        await _writeRecord(
            out, sk, utf8.encode(jsonEncode(meta)), fileId, 0, false);
        var index = 1;
        var read = 0;
        do {
          final want = min(chunkSize, total - read);
          final chunk = await src.read(want);
          if (chunk.length != want) {
            throw const AppException(AppErrorKind.fileNotFound, 'Short read');
          }
          read += chunk.length;
          await _writeRecord(out, sk, chunk, fileId, index++, read >= total);
        } while (read < total);
      });
    } finally {
      await src.close();
    }
  }

  /// Encrypts an in-memory buffer (thumbnails, small files).
  static Future<void> encryptBytes({
    required Uint8List data,
    required String dstPath,
    required Uint8List key,
    required String fileId,
    Map<String, Object?> meta = const {},
  }) async {
    await _writeAtomically(dstPath, (out) async {
      final sk = SecretKeyData(key);
      await _writeRecord(
          out, sk, utf8.encode(jsonEncode(meta)), fileId, 0, false);
      var index = 1;
      var offset = 0;
      do {
        final end = min(offset + chunkSize, data.length);
        final last = end >= data.length;
        await _writeRecord(out, sk, Uint8List.sublistView(data, offset, end),
            fileId, index++, last);
        offset = end;
      } while (offset < data.length);
    });
  }

  // ---------------------------------------------------------------- decrypt

  /// Reads and authenticates only the metadata record.
  static Future<Map<String, Object?>> readMeta({
    required String path,
    required Uint8List key,
    required String fileId,
  }) async {
    final f = await File(path).open();
    try {
      final len = await f.length();
      await _checkMagic(f);
      final rec = await _readRecord(f, len, SecretKeyData(key), fileId, 0);
      return _decodeMeta(rec);
    } finally {
      await f.close();
    }
  }

  static Future<DecryptedBlob> decryptToBytes({
    required String path,
    required Uint8List key,
    required String fileId,
  }) async {
    final builder = BytesBuilder(copy: false);
    final meta = await _decryptRecords(path, key, fileId, (chunk) async {
      builder.add(chunk);
    });
    return DecryptedBlob(meta, builder.takeBytes());
  }

  static Future<Map<String, Object?>> decryptToFile({
    required String srcPath,
    required String dstPath,
    required Uint8List key,
    required String fileId,
  }) async {
    late Map<String, Object?> meta;
    await _writeAtomically(dstPath, (out) async {
      meta = await _decryptRecords(
          srcPath, key, fileId, (chunk) => out.writeFrom(chunk));
    }, withMagic: false);
    return meta;
  }

  /// Decrypts with one key/id and re-encrypts with another (backup import).
  static Future<void> reencrypt({
    required String srcPath,
    required Uint8List srcKey,
    required String srcId,
    required String dstPath,
    required Uint8List dstKey,
    required String dstId,
    Map<String, Object?>? newMeta,
  }) async {
    final src = await File(srcPath).open();
    try {
      final len = await src.length();
      await _checkMagic(src);
      final ssk = SecretKeyData(srcKey);
      final dsk = SecretKeyData(dstKey);
      await _writeAtomically(dstPath, (out) async {
        final metaClear = await _readRecord(src, len, ssk, srcId, 0);
        final metaOut =
            newMeta == null ? metaClear : utf8.encode(jsonEncode(newMeta));
        await _writeRecord(out, dsk, metaOut, dstId, 0, false);
        var index = 1;
        while (await src.position() < len) {
          final chunk = await _readRecord(src, len, ssk, srcId, index);
          final last = await src.position() >= len;
          await _writeRecord(out, dsk, chunk, dstId, index, last);
          index++;
        }
        if (index == 1) {
          throw const AppException(
              AppErrorKind.corruptedData, 'No data records');
        }
      });
    } finally {
      await src.close();
    }
  }

  // --------------------------------------------------------------- internals

  static Future<Map<String, Object?>> _decryptRecords(
    String path,
    Uint8List key,
    String fileId,
    Future<void> Function(List<int> chunk) sink,
  ) async {
    final f = await File(path).open();
    try {
      final len = await f.length();
      await _checkMagic(f);
      final sk = SecretKeyData(key);
      final meta = _decodeMeta(await _readRecord(f, len, sk, fileId, 0));
      var index = 1;
      while (await f.position() < len) {
        await sink(await _readRecord(f, len, sk, fileId, index++));
      }
      if (index == 1) {
        throw const AppException(AppErrorKind.corruptedData, 'No data records');
      }
      return meta;
    } finally {
      await f.close();
    }
  }

  static Map<String, Object?> _decodeMeta(List<int> clear) {
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, Object?>) {
      throw const AppException(AppErrorKind.corruptedData, 'Bad metadata');
    }
    return decoded;
  }

  static Future<void> _checkMagic(RandomAccessFile f) async {
    final m = await f.read(4);
    if (m.length != 4 ||
        m[0] != _magic[0] ||
        m[1] != _magic[1] ||
        m[2] != _magic[2] ||
        m[3] != _magic[3]) {
      throw const AppException(AppErrorKind.corruptedData, 'Bad magic');
    }
  }

  static Future<void> _writeRecord(RandomAccessFile out, SecretKey key,
      List<int> clear, String id, int index, bool last) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(clear,
        secretKey: key, nonce: nonce, aad: _aad(id, index, last));
    final header = ByteData(4)..setUint32(0, box.cipherText.length, Endian.big);
    await out.writeFrom(header.buffer.asUint8List());
    await out.writeFrom(nonce);
    await out.writeFrom(box.cipherText);
    await out.writeFrom(box.mac.bytes);
  }

  static Future<List<int>> _readRecord(RandomAccessFile f, int fileLength,
      SecretKey key, String id, int index) async {
    final header = await f.read(4);
    if (header.length != 4) {
      throw const AppException(AppErrorKind.corruptedData, 'Truncated header');
    }
    final cipherLen = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (cipherLen > _maxRecord) {
      throw const AppException(AppErrorKind.corruptedData, 'Record too large');
    }
    final nonce = await f.read(_nonceLength);
    final cipher = await f.read(cipherLen);
    final mac = await f.read(_macLength);
    if (nonce.length != _nonceLength ||
        cipher.length != cipherLen ||
        mac.length != _macLength) {
      throw const AppException(AppErrorKind.corruptedData, 'Truncated record');
    }
    final last = (await f.position()) >= fileLength;
    try {
      return await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: _aad(id, index, index == 0 ? false : last),
      );
    } on SecretBoxAuthenticationError catch (e) {
      throw AppException(
          AppErrorKind.corruptedData, 'Authentication failed', e);
    }
  }

  /// Writes to `<dst>.part` and renames on success so a crash never leaves
  /// a half-written file under the real name.
  static Future<void> _writeAtomically(
    String dstPath,
    Future<void> Function(RandomAccessFile out) body, {
    bool withMagic = true,
  }) async {
    final tmp = File('$dstPath.part');
    await tmp.parent.create(recursive: true);
    final out = await tmp.open(mode: FileMode.write);
    var ok = false;
    try {
      if (withMagic) await out.writeFrom(_magic);
      await body(out);
      await out.flush();
      ok = true;
    } finally {
      await out.close();
      if (!ok && await tmp.exists()) {
        await tmp.delete();
      }
    }
    await tmp.rename(dstPath);
  }
}
