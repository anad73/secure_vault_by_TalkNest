import 'dart:io';
import 'dart:typed_data';

import 'package:safe_vault/data/crypto/vault_cipher.dart';
import 'package:safe_vault/data/db/app_database.dart';
import 'package:safe_vault/data/storage/vault_paths.dart';
import 'package:safe_vault/features/auth/vault_session.dart';
import 'package:safe_vault/features/backup/backup_service.dart';
import 'package:safe_vault/features/vault/data/album_repository.dart';
import 'package:safe_vault/features/vault/data/item_repository.dart';
import 'package:safe_vault/features/vault/data/thumbnail_cache.dart';
import 'package:safe_vault/features/vault/data/vault_service.dart';
import 'package:safe_vault/features/vault/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A complete, isolated vault (in-memory DB + temp folder) for tests.
class TestVault {
  TestVault._(this.dir, this.db, this.paths, this.session, this.albums, this.items,
      this.vault, this.backup);

  final Directory dir;
  final AppDatabase db;
  final VaultPaths paths;
  final VaultSession session;
  final AlbumRepository albums;
  final ItemRepository items;
  final VaultService vault;
  final BackupService backup;

  static Future<TestVault> create() async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('vault_test');
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final paths = VaultPaths.forTest(dir);
    final session = VaultSession()..unlock(VaultCipher.generateKey());
    final albums = AlbumRepository(db.db);
    final items = ItemRepository(db.db);
    final vault = VaultService(
      session: session,
      paths: paths,
      albums: albums,
      items: items,
      thumbs: ThumbnailCache(),
    );
    final backup = BackupService(
        session: session,
        paths: paths,
        albums: albums,
        items: items,
        vault: vault,
        kdfIterations: 1000);
    return TestVault._(dir, db, paths, session, albums, items, vault, backup);
  }

  /// Adds an encrypted item exactly like the import path does.
  Future<VaultItem> addItem(int albumId, Uint8List data,
      {String name = 'a.jpg', String albumName = 'A', DateTime? takenAt}) async {
    final fileId = VaultCipher.newFileId();
    final item = NewItem(
      albumId: albumId,
      fileId: fileId,
      kind: MediaKind.image,
      name: name,
      mime: 'image/jpeg',
      size: data.length,
      takenAt: takenAt ?? DateTime(2025, 5, 1),
      hasThumb: true,
    );
    await VaultCipher.encryptBytes(
        data: data,
        dstPath: paths.mediaFile(fileId),
        key: session.key,
        fileId: fileId,
        meta: item.toEmbeddedMeta(albumName));
    await VaultCipher.encryptBytes(
        data: Uint8List.fromList([1, 2, 3]),
        dstPath: paths.thumbFile(fileId),
        key: session.key,
        fileId: '$fileId.t');
    final id = await items.insert(item);
    return (await items.byId(id))!;
  }

  Future<void> dispose() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void noProgress(int done, int total) {}
