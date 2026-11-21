import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Item persistence with keyset pagination and batch writes.
class ItemRepository {
  ItemRepository(this._db);

  final Database _db;

  static const int pageSize = 90;

  /// Loads one page of an album. Pass the [after] cursor of the previous
  /// page's last item. Uses the composite indexes created in migration 1.
  Future<List<VaultItem>> page({
    required int albumId,
    ItemSort sort = ItemSort.newestAdded,
    PageCursor? after,
    int limit = pageSize,
    String? search,
  }) async {
    final spec = _sortSpec(sort);
    final where = StringBuffer('album_id = ?');
    final args = <Object?>[albumId];
    if (search != null && search.trim().isNotEmpty) {
      where.write(r" AND name LIKE ? ESCAPE '\'");
      args.add('%${_escapeLike(search.trim())}%');
    }
    if (after != null) {
      final cmp = spec.descending ? '<' : '>';
      where.write(
          ' AND (${spec.column} $cmp ? OR (${spec.column} = ? AND id $cmp ?))');
      args
        ..add(after.sortValue)
        ..add(after.sortValue)
        ..add(after.id);
    }
    final dir = spec.descending ? 'DESC' : 'ASC';
    final rows = await _db.query(
      'items',
      where: where.toString(),
      whereArgs: args,
      orderBy: '${spec.column} $dir, id $dir',
      limit: limit,
    );
    return rows.map(VaultItem.fromRow).toList(growable: false);
  }

  /// Cursor pointing after [item] for the given sort.
  PageCursor cursorFor(VaultItem item, ItemSort sort) => switch (sort) {
        ItemSort.newestAdded ||
        ItemSort.oldestAdded =>
          PageCursor(item.addedAt.millisecondsSinceEpoch, item.id),
        ItemSort.newestTaken =>
          PageCursor(item.takenAt.millisecondsSinceEpoch, item.id),
        ItemSort.name => PageCursor(item.name, item.id),
      };

  Future<VaultItem?> byId(int id) async {
    final rows =
        await _db.query('items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : VaultItem.fromRow(rows.first);
  }

  Future<List<VaultItem>> byIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final out = <VaultItem>[];
    // SQLite's default host-parameter limit is 999; stay well under it.
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final marks = List.filled(chunk.length, '?').join(',');
      final rows =
          await _db.query('items', where: 'id IN ($marks)', whereArgs: chunk);
      out.addAll(rows.map(VaultItem.fromRow));
    }
    return out;
  }

  /// Every item in an album, in id order (for album-wide operations).
  Future<List<VaultItem>> allInAlbum(int albumId) async {
    final rows = await _db.query('items',
        where: 'album_id = ?', whereArgs: [albumId], orderBy: 'id ASC');
    return rows.map(VaultItem.fromRow).toList(growable: false);
  }

  Future<List<String>> allFileIds() async {
    final rows = await _db.query('items', columns: ['file_id']);
    return rows.map((r) => r['file_id']! as String).toList(growable: false);
  }

  Future<int> totalCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM items')) ??
      0;

  Future<int> totalSize() async =>
      Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COALESCE(SUM(size),0) FROM items')) ??
      0;

  Future<int> insert(NewItem item) =>
      _db.insert('items', item.toRow(DateTime.now()));

  Future<void> setRotation(int id, int rotation) async {
    await _db.update('items', {'rotation': rotation % 4},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setFavorite(int id, bool favorite) async {
    await _db.update('items', {'favorite': favorite ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Moves many items in one transaction.
  Future<void> moveAll(List<int> ids, int albumId) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in ids) {
        batch.update('items', {'album_id': albumId},
            where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteAll(List<int> ids) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in ids) {
        batch.delete('items', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteByFileIds(List<String> fileIds) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final f in fileIds) {
        batch.delete('items', where: 'file_id = ?', whereArgs: [f]);
      }
      await batch.commit(noResult: true);
    });
  }

  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  static ({String column, bool descending}) _sortSpec(ItemSort s) =>
      switch (s) {
        ItemSort.newestAdded => (column: 'added_at', descending: true),
        ItemSort.oldestAdded => (column: 'added_at', descending: false),
        ItemSort.newestTaken => (column: 'taken_at', descending: true),
        ItemSort.name => (column: 'name', descending: false),
      };
}
