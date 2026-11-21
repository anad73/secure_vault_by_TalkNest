import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/errors/app_exception.dart';
import 'package:safe_vault/data/crypto/vault_cipher.dart';
import 'package:safe_vault/features/vault/domain/models.dart';

import '../helpers.dart';

Uint8List _bytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late TestVault v;

  setUp(() async => v = await TestVault.create());
  tearDown(() async => v.dispose());

  test('readBytes decrypts on a background isolate', () async {
    final a = await v.albums.create('A');
    final data = _bytes(300000, 1);
    final item = await v.addItem(a, data);
    expect(await v.vault.readBytes(item), data);
  });

  test('delete removes files and rows, reporting real progress', () async {
    final a = await v.albums.create('A');
    final items = [for (var i = 0; i < 3; i++) await v.addItem(a, _bytes(10, i))];
    final progress = <int>[];
    final r = await v.vault.delete(items, (d, t) => progress.add(d));
    expect(r.ok, 3);
    expect(r.failed, 0);
    expect(progress, [0, 1, 2, 3]);
    expect(await v.items.totalCount(), 0);
    expect(v.paths.media.listSync(), isEmpty);
    expect(v.paths.thumbs.listSync(), isEmpty);
  });

  test('rotate cycles through four quarter turns', () async {
    final a = await v.albums.create('A');
    var item = await v.addItem(a, _bytes(10, 1));
    for (var i = 1; i <= 4; i++) {
      item = await v.vault.rotate(item);
      expect(item.rotation, i % 4);
    }
    expect((await v.items.byId(item.id))!.rotation, 0);
  });

  test('integrity check re-registers orphan files and drops broken rows', () async {
    final a = await v.albums.create('Holiday');
    final keep = await v.addItem(a, _bytes(50, 1), albumName: 'Holiday', name: 'keep.jpg');
    final orphan = await v.addItem(a, _bytes(50, 2), albumName: 'Holiday', name: 'orphan.jpg');
    final broken = await v.addItem(a, _bytes(50, 3), albumName: 'Holiday', name: 'broken.jpg');

    // Simulate a lost DB row and a lost file.
    await v.items.deleteAll([orphan.id]);
    File(v.paths.mediaFile(broken.fileId)).deleteSync();
    // And a half-written file from a crash.
    File('${v.paths.mediaFile('deadbeef')}.part').writeAsBytesSync([1, 2, 3]);

    final report = await v.vault.checkIntegrity(fallbackAlbumName: 'Recovered');
    expect(report.recovered, 1);
    expect(report.removed, 1);

    final names = (await v.items.page(albumId: a)).map((e) => e.name).toSet();
    expect(names, {'keep.jpg', 'orphan.jpg'});
    expect(File('${v.paths.mediaFile('deadbeef')}.part').existsSync(), isFalse);
    expect(await v.vault.readBytes(keep), _bytes(50, 1));
  });

  test('integrity check never deletes files it cannot decrypt', () async {
    final foreign = VaultCipher.newFileId();
    await VaultCipher.encryptBytes(
        data: _bytes(10, 9),
        dstPath: v.paths.mediaFile(foreign),
        key: VaultCipher.generateKey(), // another vault's key
        fileId: foreign);
    final report = await v.vault.checkIntegrity(fallbackAlbumName: 'Recovered');
    expect(report.recovered, 0);
    expect(File(v.paths.mediaFile(foreign)).existsSync(), isTrue);
  });

  test('locking zeroes the key but running operations keep their copy', () async {
    final key = v.session.key;
    await v.session.lock();
    expect(() => v.session.key, throwsA(isA<AppException>()));
    expect(key.any((b) => b != 0), isTrue);
  });

  test('backup export → import into a different vault keeps every byte', () async {
    final a = await v.albums.create('Family');
    final originals = <String, Uint8List>{};
    for (var i = 0; i < 3; i++) {
      final data = _bytes(VaultCipher.chunkSize ~/ 2 + i, i + 10);
      final item = await v.addItem(a, data, name: 'p$i.jpg', albumName: 'Family');
      originals[item.name] = data;
    }
    final fav = (await v.items.page(albumId: a)).first;
    await v.vault.toggleFavorite(fav);

    final path = await v.backup.export('correct horse', noProgress);

    final other = await TestVault.create();
    addTearDown(other.dispose);
    // Copy the backup out of the source vault's temp folder.
    final copy = File('${other.dir.path}/b.svbk')..writeAsBytesSync(File(path).readAsBytesSync());

    await expectLater(other.backup.import(copy.path, 'wrong password', noProgress),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', AppErrorKind.wrongCredential)));

    final r = await other.backup.import(copy.path, 'correct horse', noProgress);
    expect(r.ok, 3);
    expect(r.failed, 0);

    final albums = await other.albums.all();
    expect(albums.single.name, 'Family');
    final imported = await other.items.page(albumId: albums.single.id);
    expect(imported.length, 3);
    expect(imported.where((e) => e.favorite).length, 1);
    for (final item in imported) {
      expect(item.kind, MediaKind.image);
      expect(await other.vault.readBytes(item), originals[item.name]);
    }
  });
}
