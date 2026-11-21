import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/errors/app_exception.dart';
import 'vault_cipher.dart';

/// A master key encrypted ("wrapped") with a key derived from a secret.
///
/// No hash of the secret is stored: a secret is correct exactly when the
/// AES-GCM tag of the wrapped key verifies.
class WrappedKey {
  const WrappedKey({
    required this.salt,
    required this.nonce,
    required this.cipherWithMac,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List cipherWithMac;
  final int iterations;

  Map<String, Object?> toJson() => {
        'kdf': 'pbkdf2-hmac-sha256',
        'it': iterations,
        'salt': base64Encode(salt),
        'nonce': base64Encode(nonce),
        'ct': base64Encode(cipherWithMac),
      };

  factory WrappedKey.fromJson(Map<String, Object?> json) {
    try {
      return WrappedKey(
        salt: base64Decode(json['salt']! as String),
        nonce: base64Decode(json['nonce']! as String),
        cipherWithMac: base64Decode(json['ct']! as String),
        iterations: json['it']! as int,
      );
    } catch (e) {
      throw AppException(AppErrorKind.corruptedData, 'Bad wrapped key', e);
    }
  }

  String encode() => jsonEncode(toJson());

  static WrappedKey decode(String s) =>
      WrappedKey.fromJson(jsonDecode(s) as Map<String, Object?>);
}

/// PBKDF2 + AES-GCM key wrapping. CPU heavy work runs in a background
/// isolate so the UI keeps animating while a PIN is checked.
abstract final class KeyWrapper {
  /// OWASP's 2023 guidance for PBKDF2-HMAC-SHA256 is 600k iterations for
  /// server-side hashing. On-device pure-Dart PBKDF2 at that cost takes
  /// several seconds on mid-range phones, so we use 210k combined with a
  /// persistent escalating lockout (see AuthRepository).
  static const int defaultIterations = 210000;

  static Future<WrappedKey> wrap(Uint8List masterKey, String secret,
      {int iterations = defaultIterations}) {
    final salt = VaultCipher.randomBytes(16);
    return Isolate.run(() => _wrap(masterKey, secret, salt, iterations));
  }

  /// Throws [AppErrorKind.wrongCredential] when [secret] is wrong.
  static Future<Uint8List> unwrap(WrappedKey wrapped, String secret) async {
    final result = await Isolate.run(() => _unwrap(wrapped.salt, wrapped.nonce,
        wrapped.cipherWithMac, wrapped.iterations, secret));
    if (result == null) {
      throw const AppException(AppErrorKind.wrongCredential);
    }
    return result;
  }
}

Future<SecretKey> _derive(String secret, Uint8List salt, int iterations) {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  return kdf.deriveKeyFromPassword(password: secret, nonce: salt);
}

Future<WrappedKey> _wrap(
    Uint8List master, String secret, Uint8List salt, int iterations) async {
  final kek = await _derive(secret, salt, iterations);
  final aes = AesGcm.with256bits();
  final nonce = aes.newNonce();
  final box = await aes.encrypt(master,
      secretKey: kek, nonce: nonce, aad: utf8.encode('SGV1-KEY'));
  return WrappedKey(
    salt: salt,
    nonce: Uint8List.fromList(nonce),
    cipherWithMac: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    iterations: iterations,
  );
}

Future<Uint8List?> _unwrap(Uint8List salt, Uint8List nonce,
    Uint8List cipherWithMac, int iterations, String secret) async {
  if (cipherWithMac.length < 17) return null;
  final kek = await _derive(secret, salt, iterations);
  final aes = AesGcm.with256bits();
  final split = cipherWithMac.length - 16;
  try {
    final clear = await aes.decrypt(
      SecretBox(cipherWithMac.sublist(0, split),
          nonce: nonce, mac: Mac(cipherWithMac.sublist(split))),
      secretKey: kek,
      aad: utf8.encode('SGV1-KEY'),
    );
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    return null;
  }
}
