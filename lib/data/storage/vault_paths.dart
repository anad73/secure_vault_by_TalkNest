import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Locations of vault files. Everything lives in app-private storage
/// that other apps (and the system gallery) cannot read.
class VaultPaths {
  VaultPaths._(this.root, this.temp);

  /// `<app support>/vault` – encrypted media and thumbnails.
  final Directory root;

  /// `<cache>/vault_tmp` – short-lived decrypted files (video playback,
  /// sharing, unhide). Wiped on every start and on lock.
  final Directory temp;

  static Future<VaultPaths> create() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();
    final paths = VaultPaths._(
      Directory(p.join(support.path, 'vault')),
      Directory(p.join(cache.path, 'vault_tmp')),
    );
    await paths.root.create(recursive: true);
    await paths.media.create(recursive: true);
    await paths.thumbs.create(recursive: true);
    await paths.wipeTemp();
    return paths;
  }

  /// Test-only constructor.
  factory VaultPaths.forTest(Directory base) {
    final paths = VaultPaths._(Directory(p.join(base.path, 'vault')),
        Directory(p.join(base.path, 'tmp')));
    paths.media.createSync(recursive: true);
    paths.thumbs.createSync(recursive: true);
    paths.temp.createSync(recursive: true);
    return paths;
  }

  Directory get media => Directory(p.join(root.path, 'm'));
  Directory get thumbs => Directory(p.join(root.path, 't'));

  String mediaFile(String fileId) => p.join(media.path, fileId);
  String thumbFile(String fileId) => p.join(thumbs.path, fileId);

  /// Unique path for a decrypted temp file, keeping the extension so that
  /// players and share targets recognise the type.
  String tempFile(String fileId, String originalName) {
    final ext = p.extension(originalName);
    return p.join(temp.path, '$fileId${ext.isEmpty ? '' : ext}');
  }

  Future<void> wipeTemp() async {
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // A file may still be held open by the media player; it is retried
      // on the next lock/start.
    }
    await temp.create(recursive: true);
  }
}
