import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/errors/app_exception.dart';
import 'package:safe_vault/data/crypto/vault_cipher.dart';

Uint8List _random(int n, [int seed = 1]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

Matcher _throwsKind(AppErrorKind kind) =>
    throwsA(isA<AppException>().having((e) => e.kind, 'kind', kind));

void main() {
  late Directory dir;
  final key = VaultCipher.generateKey();

  setUp(() => dir = Directory.systemTemp.createTempSync('cipher_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String path(String name) => '${dir.path}/$name';

  for (final size in [0, 1, 1000, VaultCipher.chunkSize, VaultCipher.chunkSize * 2 + 123]) {
    test('bytes round-trip ($size bytes)', () async {
      final data = _random(size);
      await VaultCipher.encryptBytes(
          data: data, dstPath: path('f'), key: key, fileId: 'id1', meta: {'name': 'x.jpg'});
      final out = await VaultCipher.decryptToBytes(path: path('f'), key: key, fileId: 'id1');
      expect(out.bytes, data);
      expect(out.meta['name'], 'x.jpg');
    });
  }

  test('file round-trip streams multiple chunks', () async {
    final data = _random(VaultCipher.chunkSize * 3 + 7, 9);
    File(path('plain')).writeAsBytesSync(data);
    await VaultCipher.encryptFile(
        srcPath: path('plain'), dstPath: path('enc'), key: key, fileId: 'abc', meta: {'k': 1});
    final encrypted = File(path('enc')).readAsBytesSync();
    expect(encrypted.length, greaterThan(data.length));
    await VaultCipher.decryptToFile(
        srcPath: path('enc'), dstPath: path('dec'), key: key, fileId: 'abc');
    expect(File(path('dec')).readAsBytesSync(), data);
    expect(File(path('enc.part')).existsSync(), isFalse);
  });

  test('ciphertext does not contain the plaintext', () async {
    final data = Uint8List.fromList(List.filled(4096, 0x41));
    await VaultCipher.encryptBytes(data: data, dstPath: path('f'), key: key, fileId: 'id');
    final raw = File(path('f')).readAsBytesSync();
    final run = List.filled(64, 0x41);
    var found = false;
    for (var i = 0; i + run.length <= raw.length && !found; i++) {
      found = raw.sublist(i, i + run.length).every((b) => b == 0x41);
    }
    expect(found, isFalse);
  });

  test('a flipped byte is detected', () async {
    await VaultCipher.encryptBytes(
        data: _random(5000), dstPath: path('f'), key: key, fileId: 'id');
    final raw = File(path('f')).readAsBytesSync();
    raw[raw.length - 100] ^= 0x01;
    File(path('f')).writeAsBytesSync(raw);
    await expectLater(VaultCipher.decryptToBytes(path: path('f'), key: key, fileId: 'id'),
        _throwsKind(AppErrorKind.corruptedData));
  });

  test('truncation at a record boundary is detected', () async {
    await VaultCipher.encryptBytes(
        data: _random(VaultCipher.chunkSize * 2), dstPath: path('f'), key: key, fileId: 'id');
    final raw = File(path('f')).readAsBytesSync();
    // Remove the final record: 4 (len) + 12 (nonce) + chunk + 16 (tag).
    final lastRecord = 4 + 12 + VaultCipher.chunkSize + 16;
    File(path('f')).writeAsBytesSync(raw.sublist(0, raw.length - lastRecord));
    await expectLater(VaultCipher.decryptToBytes(path: path('f'), key: key, fileId: 'id'),
        _throwsKind(AppErrorKind.corruptedData));
  });

  test('wrong key or swapped file id is rejected', () async {
    await VaultCipher.encryptBytes(data: _random(10), dstPath: path('f'), key: key, fileId: 'a');
    await expectLater(
        VaultCipher.decryptToBytes(
            path: path('f'), key: VaultCipher.generateKey(), fileId: 'a'),
        _throwsKind(AppErrorKind.corruptedData));
    await expectLater(VaultCipher.decryptToBytes(path: path('f'), key: key, fileId: 'b'),
        _throwsKind(AppErrorKind.corruptedData));
  });

  test('reencrypt changes key and id but keeps content', () async {
    final data = _random(VaultCipher.chunkSize + 10);
    final key2 = VaultCipher.generateKey();
    await VaultCipher.encryptBytes(
        data: data, dstPath: path('a'), key: key, fileId: 'old', meta: {'n': 'a'});
    await VaultCipher.reencrypt(
      srcPath: path('a'),
      srcKey: key,
      srcId: 'old',
      dstPath: path('b'),
      dstKey: key2,
      dstId: 'new',
      newMeta: {'n': 'b'},
    );
    final out = await VaultCipher.decryptToBytes(path: path('b'), key: key2, fileId: 'new');
    expect(out.bytes, data);
    expect(out.meta['n'], 'b');
  });

  test('readMeta reads only the metadata record', () async {
    await VaultCipher.encryptBytes(
        data: _random(100), dstPath: path('f'), key: key, fileId: 'id', meta: {'album': 'A'});
    final meta = await VaultCipher.readMeta(path: path('f'), key: key, fileId: 'id');
    expect(meta['album'], 'A');
  });

  test('file ids are 32 hex chars and unique', () {
    final ids = {for (var i = 0; i < 1000; i++) VaultCipher.newFileId()};
    expect(ids.length, 1000);
    expect(ids.every((e) => RegExp(r'^[0-9a-f]{32}$').hasMatch(e)), isTrue);
  });
}
