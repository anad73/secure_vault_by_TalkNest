import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/logging/app_logger.dart';

/// Opens the SQLite database and owns schema migrations.
///
/// The database only stores metadata in app-private storage. Media bytes
/// are kept in encrypted files (see VaultCipher).
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;
  static const String fileName = 'safe_vault.db';

  static Future<AppDatabase> open(
      {DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _migrate(db, 0, version);
        },
        onUpgrade: (db, from, to) async {
          AppLogger.info('DB', 'Migrating schema $from -> $to');
          await _migrate(db, from, to);
        },
      ),
    );
    return AppDatabase._(db);
  }

  /// Runs every migration step in order inside one transaction so a failed
  /// upgrade never leaves a half-migrated schema.
  static Future<void> _migrate(Database db, int from, int to) async {
    await db.transaction((txn) async {
      for (var v = from + 1; v <= to; v++) {
        final step = _migrations[v];
        if (step == null) continue;
        for (final sql in step) {
          await txn.execute(sql);
        }
      }
    });
  }

  /// Migration scripts keyed by target version. Append new versions; never
  /// edit an existing entry once released.
  static const Map<int, List<String>> _migrations = {
    1: [
      '''
      CREATE TABLE albums (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        created_at  INTEGER NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0
      )''',
      '''
      CREATE TABLE items (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        album_id     INTEGER NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
        file_id      TEXT    NOT NULL UNIQUE,
        kind         INTEGER NOT NULL,
        name         TEXT    NOT NULL,
        mime         TEXT    NOT NULL DEFAULT '',
        size         INTEGER NOT NULL DEFAULT 0,
        added_at     INTEGER NOT NULL,
        taken_at     INTEGER NOT NULL,
        width        INTEGER NOT NULL DEFAULT 0,
        height       INTEGER NOT NULL DEFAULT 0,
        duration_ms  INTEGER NOT NULL DEFAULT 0,
        rotation     INTEGER NOT NULL DEFAULT 0,
        has_thumb    INTEGER NOT NULL DEFAULT 0,
        favorite     INTEGER NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX idx_items_album_added ON items(album_id, added_at DESC, id DESC)',
      'CREATE INDEX idx_items_album_taken ON items(album_id, taken_at DESC, id DESC)',
      'CREATE INDEX idx_items_album_name ON items(album_id, name, id)',
      'CREATE INDEX idx_items_kind ON items(kind)',
      'CREATE INDEX idx_items_favorite ON items(favorite) WHERE favorite = 1',
    ],
  };

  /// `PRAGMA quick_check`; returns true when the file is healthy.
  Future<bool> quickCheck() async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    return rows.isNotEmpty && rows.first.values.first == 'ok';
  }

  Future<void> close() => db.close();
}
