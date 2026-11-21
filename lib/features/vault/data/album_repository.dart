import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Album persistence. All SQL is parameterised.
class AlbumRepository {
  AlbumRepository(this._db);

  final Database _db;

  /// One query returns albums with item counts and cover ids (no N+1).
  Future<List<Album>> all() async {
    final rows = await _db.rawQuery('''
      SELECT a.id, a.name, a.created_at,
             (SELECT COUNT(*) FROM items i WHERE i.album_id = a.id) AS item_count,
             (SELECT i.file_id FROM items i
                WHERE i.album_id = a.id AND i.has_thumb = 1
                ORDER BY i.added_at DESC, i.id DESC LIMIT 1) AS cover_file_id,
             (SELECT i.kind FROM items i
                WHERE i.album_id = a.id AND i.has_thumb = 1
                ORDER BY i.added_at DESC, i.id DESC LIMIT 1) AS cover_kind
      FROM albums a
      ORDER BY a.sort_order ASC, a.created_at ASC
    ''');
    return rows.map(Album.fromRow).toList(growable: false);
  }

  Future<Album?> byId(int id) async {
    final rows =
        await _db.query('albums', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Album.fromRow(rows.first);
  }

  Future<Album?> byName(String name) async {
    final rows = await _db.query('albums',
        where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : Album.fromRow(rows.first);
  }

  Future<int> create(String name) {
    return _db.insert('albums', {
      'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Returns an existing album with [name] or creates it.
  Future<int> ensure(String name) async {
    final existing = await byName(name);
    return existing?.id ?? await create(name);
  }

  Future<void> rename(int id, String name) async {
    await _db.update('albums', {'name': name.trim()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the album row; item rows cascade. Files must be removed by the
  /// caller (VaultService) first.
  Future<void> delete(int id) async {
    await _db.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    return Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM albums')) ??
        0;
  }
}
