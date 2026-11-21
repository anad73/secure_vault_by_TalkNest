import 'dart:isolate';
import 'dart:typed_data';

import 'vault_cipher.dart';

/// Runs [VaultCipher] operations on background isolates so that large
/// files never block the UI thread.
///
/// Every closure below only captures sendable values (strings, byte lists,
/// JSON maps).
abstract final class CryptoWorker {
  static Future<void> encryptFile({
    required String srcPath,
    required String dstPath,
    required Uint8List key,
    required String fileId,
    required Map<String, Object?> meta,
  }) {
    return Isolate.run(() => VaultCipher.encryptFile(
        srcPath: srcPath,
        dstPath: dstPath,
        key: key,
        fileId: fileId,
        meta: meta));
  }

  static Future<void> encryptBytes({
    required Uint8List data,
    required String dstPath,
    required Uint8List key,
    required String fileId,
    Map<String, Object?> meta = const {},
  }) {
    return Isolate.run(() => VaultCipher.encryptBytes(
        data: data, dstPath: dstPath, key: key, fileId: fileId, meta: meta));
  }

  static Future<Uint8List> decryptBytes({
    required String path,
    required Uint8List key,
    required String fileId,
  }) {
    return Isolate.run(() async {
      final blob = await VaultCipher.decryptToBytes(
          path: path, key: key, fileId: fileId);
      return blob.bytes;
    });
  }

  static Future<Map<String, Object?>> decryptToFile({
    required String srcPath,
    required String dstPath,
    required Uint8List key,
    required String fileId,
  }) {
    return Isolate.run(() => VaultCipher.decryptToFile(
        srcPath: srcPath, dstPath: dstPath, key: key, fileId: fileId));
  }

  static Future<Map<String, Object?>> readMeta({
    required String path,
    required Uint8List key,
    required String fileId,
  }) {
    return Isolate.run(
        () => VaultCipher.readMeta(path: path, key: key, fileId: fileId));
  }

  static Future<void> reencrypt({
    required String srcPath,
    required Uint8List srcKey,
    required String srcId,
    required String dstPath,
    required Uint8List dstKey,
    required String dstId,
    Map<String, Object?>? newMeta,
  }) {
    return Isolate.run(() => VaultCipher.reencrypt(
          srcPath: srcPath,
          srcKey: srcKey,
          srcId: srcId,
          dstPath: dstPath,
          dstKey: dstKey,
          dstId: dstId,
          newMeta: newMeta,
        ));
  }
}
