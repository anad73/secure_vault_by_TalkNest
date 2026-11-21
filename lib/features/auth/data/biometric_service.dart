import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/logging/app_logger.dart';

/// Fingerprint unlock.
///
/// When enabled, a copy of the master key is stored in
/// flutter_secure_storage, which encrypts it with a key held in the
/// Android Keystore. It is only read after a successful biometric prompt.
class BiometricService {
  BiometricService({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _kKey = 'vault.master.bio';

  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException catch (e) {
      AppLogger.warn('Bio', 'availability check failed: ${e.code}');
      return false;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return await _storage.containsKey(key: _kKey);
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _prompt(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options:
            const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException catch (e) {
      AppLogger.warn('Bio', 'authenticate failed: ${e.code}');
      return false;
    }
  }

  /// Asks for a fingerprint, then stores [master]. Returns false if the
  /// user cancelled.
  Future<bool> enable(Uint8List master, String reason) async {
    if (!await _prompt(reason)) return false;
    await _storage.write(key: _kKey, value: base64Encode(master));
    return true;
  }

  Future<void> disable() async {
    try {
      await _storage.delete(key: _kKey);
    } on PlatformException catch (e) {
      AppLogger.warn('Bio', 'disable failed: ${e.code}');
    }
  }

  /// Returns the master key after a successful prompt, otherwise null.
  Future<Uint8List?> unlock(String reason) async {
    if (!await isEnabled()) return null;
    if (!await _prompt(reason)) return null;
    try {
      final v = await _storage.read(key: _kKey);
      return v == null ? null : base64Decode(v);
    } on PlatformException catch (e) {
      // Keystore entry invalidated (e.g. new fingerprint enrolled).
      AppLogger.warn('Bio', 'read failed: ${e.code}');
      await disable();
      return null;
    }
  }
}
