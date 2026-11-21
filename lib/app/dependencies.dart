import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/db/app_database.dart';
import '../data/storage/vault_paths.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/biometric_service.dart';
import '../features/auth/vault_session.dart';
import '../features/backup/backup_service.dart';
import '../features/settings/settings_controller.dart';
import '../features/vault/data/album_repository.dart';
import '../features/vault/data/item_repository.dart';
import '../features/vault/data/thumbnail_cache.dart';
import '../features/vault/data/vault_service.dart';

/// Composition root: creates every service once, in dependency order.
/// Widgets receive them through Provider (constructor injection in tests).
class AppDependencies {
  AppDependencies._({
    required this.database,
    required this.paths,
    required this.settings,
    required this.auth,
    required this.biometrics,
    required this.session,
    required this.albums,
    required this.items,
    required this.thumbs,
    required this.vault,
    required this.backup,
  });

  final AppDatabase database;
  final VaultPaths paths;
  final SettingsController settings;
  final AuthRepository auth;
  final BiometricService biometrics;
  final VaultSession session;
  final AlbumRepository albums;
  final ItemRepository items;
  final ThumbnailCache thumbs;
  final VaultService vault;
  final BackupService backup;

  static Future<AppDependencies> create() async {
    // Independent I/O in parallel to shorten startup.
    final (prefs, paths, database) = await (
      SharedPreferences.getInstance(),
      VaultPaths.create(),
      AppDatabase.open(),
    ).wait;

    final session = VaultSession();
    final albums = AlbumRepository(database.db);
    final items = ItemRepository(database.db);
    final thumbs = ThumbnailCache();
    final vault = VaultService(
      session: session,
      paths: paths,
      albums: albums,
      items: items,
      thumbs: thumbs,
    );

    // Locking forgets every decrypted byte the app still holds.
    session.addLockListener(() async {
      thumbs.clear();
      await paths.wipeTemp();
    });

    return AppDependencies._(
      database: database,
      paths: paths,
      settings: SettingsController(prefs),
      auth: AuthRepository(prefs),
      biometrics: BiometricService(),
      session: session,
      albums: albums,
      items: items,
      thumbs: thumbs,
      vault: vault,
      backup: BackupService(
        session: session,
        paths: paths,
        albums: albums,
        items: items,
        vault: vault,
      ),
    );
  }
}
