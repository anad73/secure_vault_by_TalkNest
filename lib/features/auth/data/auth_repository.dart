import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_exception.dart';
import '../../../data/crypto/key_wrapper.dart';
import '../../../data/crypto/vault_cipher.dart';

enum LockType { pin, pattern }

/// Stores the wrapped master key and brute-force counters.
///
/// Only non-secret material is persisted: PBKDF2 salts and AES-GCM wrapped
/// keys. The PIN/pattern itself is never stored, not even as a hash.
class AuthRepository {
  AuthRepository(this._prefs, {DateTime Function()? clock, int? iterations})
      : _now = clock ?? DateTime.now,
        _iterations = iterations ?? KeyWrapper.defaultIterations;

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final int _iterations;

  static const int maxAttempts = 5;
  static const Duration baseLockout = Duration(seconds: 30);
  static const Duration maxLockout = Duration(hours: 1);

  static const _kType = 'auth.type';
  static const _kWrapped = 'auth.wrapped';
  static const _kRecoveryQ = 'auth.recovery.q';
  static const _kRecoveryWrapped = 'auth.recovery.wrapped';
  static const _kFailures = 'auth.failures';
  static const _kLockUntil = 'auth.lock_until';

  bool get isSetUp => _prefs.getString(_kWrapped) != null;

  LockType get lockType =>
      _prefs.getString(_kType) == 'pattern' ? LockType.pattern : LockType.pin;

  bool get hasRecovery => _prefs.getString(_kRecoveryWrapped) != null;

  String? get recoveryQuestion => _prefs.getString(_kRecoveryQ);

  int get failures => _prefs.getInt(_kFailures) ?? 0;

  int get attemptsLeft => max(0, maxAttempts - failures);

  /// Remaining lockout, or null when unlocking is allowed.
  Duration? get lockoutRemaining {
    final until = _prefs.getInt(_kLockUntil);
    if (until == null) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(_now());
    return left.isNegative || left == Duration.zero ? null : left;
  }

  /// First-run: creates a random master key and protects it with [secret].
  Future<Uint8List> createVault(LockType type, String secret) async {
    final master = VaultCipher.generateKey();
    final wrapped =
        await KeyWrapper.wrap(master, secret, iterations: _iterations);
    await _prefs.setString(_kType, type.name);
    await _prefs.setString(_kWrapped, wrapped.encode());
    await _resetFailures();
    return master;
  }

  /// Returns the master key or throws [AppErrorKind.wrongCredential] /
  /// [AppErrorKind.lockedOut].
  Future<Uint8List> unlock(String secret) =>
      _guarded(() => _unwrapKey(_kWrapped, secret));

  Future<Uint8List> recover(String answer) =>
      _guarded(() => _unwrapKey(_kRecoveryWrapped, normalizeAnswer(answer)));

  /// Re-wraps the already unlocked master key with a new credential.
  Future<void> changeCredential(
      Uint8List master, LockType type, String secret) async {
    final wrapped =
        await KeyWrapper.wrap(master, secret, iterations: _iterations);
    await _prefs.setString(_kType, type.name);
    await _prefs.setString(_kWrapped, wrapped.encode());
  }

  Future<void> setRecovery(
      Uint8List master, String question, String answer) async {
    final wrapped = await KeyWrapper.wrap(master, normalizeAnswer(answer),
        iterations: _iterations);
    await _prefs.setString(_kRecoveryQ, question.trim());
    await _prefs.setString(_kRecoveryWrapped, wrapped.encode());
  }

  /// Case- and whitespace-insensitive so "Kabul " and "kabul" match.
  static String normalizeAnswer(String answer) =>
      answer.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<Uint8List> _unwrapKey(String prefKey, String secret) async {
    final raw = _prefs.getString(prefKey);
    if (raw == null) {
      throw const AppException(AppErrorKind.wrongCredential, 'Not set');
    }
    return KeyWrapper.unwrap(WrappedKey.decode(raw), secret);
  }

  Future<Uint8List> _guarded(Future<Uint8List> Function() attempt) async {
    if (lockoutRemaining != null) {
      throw const AppException(AppErrorKind.lockedOut);
    }
    try {
      final key = await attempt();
      await _resetFailures();
      return key;
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.wrongCredential) await _registerFailure();
      rethrow;
    }
  }

  Future<void> _registerFailure() async {
    final f = failures + 1;
    await _prefs.setInt(_kFailures, f);
    if (f >= maxAttempts) {
      // 30 s, 60 s, 120 s … capped at one hour. Persisted, so restarting
      // the app does not reset it.
      final exp = min(f - maxAttempts, 7);
      final ms = min(
          baseLockout.inMilliseconds * (1 << exp), maxLockout.inMilliseconds);
      await _prefs.setInt(_kLockUntil, _now().millisecondsSinceEpoch + ms);
    }
  }

  Future<void> _resetFailures() async {
    await _prefs.remove(_kFailures);
    await _prefs.remove(_kLockUntil);
  }
}
