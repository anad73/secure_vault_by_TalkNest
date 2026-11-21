import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/features/vault/data/item_repository.dart';
import 'package:safe_vault/features/vault/domain/models.dart';

import '../helpers.dart';

void main() {
  late TestVault v;

  setUp(() async => v = await TestVault.create());
  tearDown(() async => v.dispose());

  test('schema passes SQLite quick_check and has the expected indexes', () async {
    expect(await v.db.quickCheck(), isTrue);
    final idx = await v.db.db
        .rawQuery("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='items'");
    final names = idx.map((r) => r['name']).toSet();
    expect(names, containsAll(['idx_items_album_added', 'idx_items_album_taken', 'idx_items_album_name']));
  });

  test('album list returns counts and covers in one query', () async {
    final a = await v.albums.create('Trip');
    await v.albums.create('Empty');
    await v.addItem(a, Uint8List(10));
    await v.addItem(a, Uint8List(10));
    final all = await v.albums.all();
    final trip = all.firstWhere((x) => x.name == 'Trip');
    final empty = all.firstWhere((x) => x.name == 'Empty');
    expect(trip.itemCount, 2);
    expect(trip.coverFileId, isNotNull);
    expect(empty.itemCount, 0);
    expect(empty.coverFileId, isNull);
  });

  test('keyset pagination visits every item exactly once, in order', () async {
    final a = await v.albums.create('Big');
    // Insert in a transaction-like burst; identical added_at values are
    // likely, which exercises the (sort value, id) tie-breaker.
    for (var i = 0; i < 250; i++) {
      await v.items.insert(NewItem(
        albumId: a,
        fileId: 'f$i'.padLeft(32, '0'),
        kind: MediaKind.image,
        name: 'img_${i.toString().padLeft(3, '0')}.jpg',
        mime: 'image/jpeg',
        size: 1,
        takenAt: DateTime(2020).add(Duration(minutes: i)),
      ));
    }
    for (final sort in ItemSort.values) {
      final seen = <int>[];
      PageCursor? cursor;
      while (true) {
        final page = await v.items.page(albumId: a, sort: sort, after: cursor);
        seen.addAll(page.map((e) => e.id));
        if (page.length < ItemRepository.pageSize) break;
        cursor = v.items.cursorFor(page.last, sort);
      }
      expect(seen.length, 250, reason: '$sort');
      expect(seen.toSet().length, 250, reason: 'no duplicates for $sort');
    }
    final byName = await v.items.page(albumId: a, sort: ItemSort.name, limit: 3);
    expect(byName.map((e) => e.name), ['img_000.jpg', 'img_001.jpg', 'img_002.jpg']);
  });

  test('search escapes LIKE wildcards', () async {
    final a = await v.albums.create('S');
    await v.addItem(a, Uint8List(1), name: '100%_real.jpg');
    await v.addItem(a, Uint8List(1), name: '100abc.jpg');
    final hits = await v.items.page(albumId: a, search: '%_');
    expect(hits.map((e) => e.name), ['100%_real.jpg']);
  });

  test('move and delete run as batches; deleting an album cascades', () async {
    final a = await v.albums.create('A');
    final b = await v.albums.create('B');
    final i1 = await v.addItem(a, Uint8List(1));
    final i2 = await v.addItem(a, Uint8List(1));
    await v.items.moveAll([i1.id, i2.id], b);
    expect((await v.items.page(albumId: b)).length, 2);
    await v.albums.delete(b);
    expect(await v.items.totalCount(), 0);
  });
}
