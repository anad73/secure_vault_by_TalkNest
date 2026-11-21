import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';

/// Holds the decrypted master key in memory while the vault is unlocked.
///
/// The key is zeroed when the vault locks. While [runExternal] is active
/// (system pickers, share sheet, delete confirmation), backgrounding the
/// app does not trigger auto-lock.
class VaultSession extends ChangeNotifier {
  Uint8List? _key;
  int _externalDepth = 0;

  bool get isUnlocked => _key != null;

  bool get inExternalActivity => _externalDepth > 0;

  /// Callbacks run on lock (e.g. wipe decrypted temp files).
  final List<Future<void> Function()> _onLock = [];

  /// Returns a *copy* of the master key. Long-running operations keep
  /// their copy, so zeroing the session key on lock can never make them
  /// continue with a wiped (all-zero) key.
  Uint8List get key {
    final k = _key;
    if (k == null) {
      throw const AppException(AppErrorKind.lockedOut, 'Vault is locked');
    }
    return Uint8List.fromList(k);
  }

  void addLockListener(Future<void> Function() callback) =>
      _onLock.add(callback);

  void unlock(Uint8List key) {
    _key = Uint8List.fromList(key);
    notifyListeners();
  }

  Future<void> lock() async {
    final k = _key;
    if (k == null) return;
    k.fillRange(0, k.length, 0);
    _key = null;
    notifyListeners();
    for (final cb in _onLock) {
      await cb();
    }
  }

  Future<T> runExternal<T>(Future<T> Function() action) async {
    _externalDepth++;
    try {
      return await action();
    } finally {
      // Grace period: the "resumed" lifecycle event can arrive slightly
      // after the external activity's future completes.
      Timer(const Duration(milliseconds: 800), () => _externalDepth--);
    }
  }
}
