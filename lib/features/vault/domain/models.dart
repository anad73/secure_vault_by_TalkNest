import 'package:flutter/foundation.dart';

enum MediaKind {
  image,
  video,
  audio;

  static MediaKind fromIndex(int i) =>
      MediaKind.values[i.clamp(0, MediaKind.values.length - 1)];
}

@immutable
class Album {
  const Album({
    required this.id,
    required this.name,
    required this.createdAt,
    this.itemCount = 0,
    this.coverFileId,
    this.coverKind,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int itemCount;

  /// File id of the most recent item, used for the album cover thumbnail.
  final String? coverFileId;
  final MediaKind? coverKind;

  factory Album.fromRow(Map<String, Object?> r) => Album(
        id: r['id']! as int,
        name: r['name']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        itemCount: (r['item_count'] as int?) ?? 0,
        coverFileId: r['cover_file_id'] as String?,
        coverKind: r['cover_kind'] == null
            ? null
            : MediaKind.fromIndex(r['cover_kind']! as int),
      );

  @override
  bool operator ==(Object other) =>
      other is Album &&
      other.id == id &&
      other.name == name &&
      other.itemCount == itemCount &&
      other.coverFileId == coverFileId;

  @override
  int get hashCode => Object.hash(id, name, itemCount, coverFileId);
}

@immutable
class VaultItem {
  const VaultItem({
    required this.id,
    required this.albumId,
    required this.fileId,
    required this.kind,
    required this.name,
    required this.mime,
    required this.size,
    required this.addedAt,
    required this.takenAt,
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.rotation = 0,
    this.hasThumb = false,
    this.favorite = false,
  });

  final int id;
  final int albumId;

  /// Random on-disk name of the encrypted file.
  final String fileId;
  final MediaKind kind;
  final String name;
  final String mime;
  final int size;
  final DateTime addedAt;
  final DateTime takenAt;
  final int width;
  final int height;
  final int durationMs;

  /// Clockwise quarter turns applied when displaying (0..3).
  final int rotation;
  final bool hasThumb;
  final bool favorite;

  VaultItem copyWith({int? albumId, int? rotation, bool? favorite}) =>
      VaultItem(
        id: id,
        albumId: albumId ?? this.albumId,
        fileId: fileId,
        kind: kind,
        name: name,
        mime: mime,
        size: size,
        addedAt: addedAt,
        takenAt: takenAt,
        width: width,
        height: height,
        durationMs: durationMs,
        rotation: rotation ?? this.rotation,
        hasThumb: hasThumb,
        favorite: favorite ?? this.favorite,
      );

  factory VaultItem.fromRow(Map<String, Object?> r) => VaultItem(
        id: r['id']! as int,
        albumId: r['album_id']! as int,
        fileId: r['file_id']! as String,
        kind: MediaKind.fromIndex(r['kind']! as int),
        name: r['name']! as String,
        mime: (r['mime'] as String?) ?? '',
        size: (r['size'] as int?) ?? 0,
        addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at']! as int),
        takenAt: DateTime.fromMillisecondsSinceEpoch(
            (r['taken_at'] as int?) ?? (r['added_at']! as int)),
        width: (r['width'] as int?) ?? 0,
        height: (r['height'] as int?) ?? 0,
        durationMs: (r['duration_ms'] as int?) ?? 0,
        rotation: (r['rotation'] as int?) ?? 0,
        hasThumb: ((r['has_thumb'] as int?) ?? 0) == 1,
        favorite: ((r['favorite'] as int?) ?? 0) == 1,
      );

  /// Metadata embedded (encrypted) inside the vault file itself, so the
  /// database can be rebuilt from the files if it is ever lost.
  Map<String, Object?> toEmbeddedMeta(String albumName) => {
        'v': 1,
        'name': name,
        'kind': kind.index,
        'mime': mime,
        'size': size,
        'w': width,
        'h': height,
        'dur': durationMs,
        'taken': takenAt.millisecondsSinceEpoch,
        'rot': rotation,
        'album': albumName,
      };

  @override
  bool operator ==(Object other) =>
      other is VaultItem &&
      other.id == id &&
      other.rotation == rotation &&
      other.albumId == albumId &&
      other.favorite == favorite;

  @override
  int get hashCode => Object.hash(id, rotation, albumId, favorite);
}

/// Data needed to insert a new item.
class NewItem {
  const NewItem({
    required this.albumId,
    required this.fileId,
    required this.kind,
    required this.name,
    required this.mime,
    required this.size,
    required this.takenAt,
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.rotation = 0,
    this.hasThumb = false,
  });

  final int albumId;
  final String fileId;
  final MediaKind kind;
  final String name;
  final String mime;
  final int size;
  final DateTime takenAt;
  final int width;
  final int height;
  final int durationMs;
  final int rotation;
  final bool hasThumb;

  Map<String, Object?> toRow(DateTime addedAt) => {
        'album_id': albumId,
        'file_id': fileId,
        'kind': kind.index,
        'name': name,
        'mime': mime,
        'size': size,
        'added_at': addedAt.millisecondsSinceEpoch,
        'taken_at': takenAt.millisecondsSinceEpoch,
        'width': width,
        'height': height,
        'duration_ms': durationMs,
        'rotation': rotation,
        'has_thumb': hasThumb ? 1 : 0,
      };

  Map<String, Object?> toEmbeddedMeta(String albumName) => {
        'v': 1,
        'name': name,
        'kind': kind.index,
        'mime': mime,
        'size': size,
        'w': width,
        'h': height,
        'dur': durationMs,
        'taken': takenAt.millisecondsSinceEpoch,
        'rot': rotation,
        'album': albumName,
      };

  NewItem withThumb(bool value) => NewItem(
        albumId: albumId,
        fileId: fileId,
        kind: kind,
        name: name,
        mime: mime,
        size: size,
        takenAt: takenAt,
        width: width,
        height: height,
        durationMs: durationMs,
        rotation: rotation,
        hasThumb: value,
      );

  /// Rebuilds a [NewItem] from metadata embedded in a vault file.
  static NewItem fromEmbeddedMeta(
      Map<String, Object?> m, String fileId, int albumId, bool hasThumb) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return NewItem(
      albumId: albumId,
      fileId: fileId,
      kind: MediaKind.fromIndex(i('kind')),
      name: (m['name'] as String?) ?? fileId,
      mime: (m['mime'] as String?) ?? '',
      size: i('size'),
      takenAt: DateTime.fromMillisecondsSinceEpoch(i('taken')),
      width: i('w'),
      height: i('h'),
      durationMs: i('dur'),
      rotation: i('rot') % 4,
      hasThumb: hasThumb,
    );
  }
}

/// Sort orders available in an album.
enum ItemSort { newestAdded, oldestAdded, newestTaken, name }

/// Keyset pagination cursor (avoids OFFSET scans on large albums).
@immutable
class PageCursor {
  const PageCursor(this.sortValue, this.id);
  final Object sortValue;
  final int id;
}
