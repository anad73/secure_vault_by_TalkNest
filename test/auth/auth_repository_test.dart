import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vault/core/errors/app_exception.dart';
import 'package:safe_vault/data/crypto/key_wrapper.dart';
import 'package:safe_vault/data/crypto/vault_cipher.dart';
import 'package:safe_vault/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Matcher _throwsKind(AppErrorKind kind) =>
    throwsA(isA<AppException>().having((e) => e.kind, 'kind', kind));

void main() {
  // Low PBKDF2 cost keeps tests fast; production uses defaultIterations.
  const iterations = 1000;
  late SharedPreferences prefs;
  late DateTime now;
  late AuthRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 1, 1, 12);
    repo = AuthRepository(prefs, clock: () => now, iterations: iterations);
  });

  test('key wrapping round-trips and rejects a wrong secret', () async {
    final master = VaultCipher.generateKey();
    final w = await KeyWrapper.wrap(master, 'pin:1234', iterations: iterations);
    expect(await KeyWrapper.unwrap(w, 'pin:1234'), master);
    await expectLater(KeyWrapper.unwrap(w, 'pin:1235'), _throwsKind(AppErrorKind.wrongCredential));
    // Serialisation survives a round trip.
    expect(await KeyWrapper.unwrap(WrappedKey.decode(w.encode()), 'pin:1234'), master);
  });

  test('no default credential before setup', () {
    expect(repo.isSetUp, isFalse);
  });

  test('create then unlock returns the same master key', () async {
    final master = await repo.createVault(LockType.pin, 'pin:2468');
    expect(repo.isSetUp, isTrue);
    expect(repo.lockType, LockType.pin);
    expect(await repo.unlock('pin:2468'), master);
  });

  test('the PIN itself is never persisted', () async {
    await repo.createVault(LockType.pin, 'pin:97531');
    final all = prefs.getKeys().map((k) => prefs.get(k).toString()).join('|');
    expect(all.contains('97531'), isFalse);
  });

  test('five failures trigger an escalating, persistent lockout', () async {
    await repo.createVault(LockType.pin, 'pin:1111');
    for (var i = 0; i < AuthRepository.maxAttempts; i++) {
      await expectLater(repo.unlock('pin:0000'), _throwsKind(AppErrorKind.wrongCredential));
    }
    expect(repo.lockoutRemaining, isNotNull);
    expect(repo.lockoutRemaining!.inSeconds, inInclusiveRange(29, 30));
    // Even the right PIN is refused while locked out.
    await expectLater(repo.unlock('pin:1111'), _throwsKind(AppErrorKind.lockedOut));

    // A fresh repository instance (app restart) still sees the lockout.
    final restarted = AuthRepository(prefs, clock: () => now, iterations: iterations);
    expect(restarted.lockoutRemaining, isNotNull);

    // After it expires, another failure doubles the wait.
    now = now.add(const Duration(seconds: 31));
    expect(repo.lockoutRemaining, isNull);
    await expectLater(repo.unlock('pin:0000'), _throwsKind(AppErrorKind.wrongCredential));
    expect(repo.lockoutRemaining!.inSeconds, inInclusiveRange(59, 60));

    // Success resets the counter.
    now = now.add(const Duration(minutes: 2));
    await repo.unlock('pin:1111');
    expect(repo.failures, 0);
    expect(repo.lockoutRemaining, isNull);
  });

  test('recovery answer resets credential without losing the key', () async {
    final master = await repo.createVault(LockType.pattern, 'pat:0-1-2-5');
    await repo.setRecovery(master, 'First school?', '  Kabul   High ');
    expect(repo.hasRecovery, isTrue);

    final recovered = await repo.recover('kabul high');
    expect(recovered, master);

    await repo.changeCredential(recovered, LockType.pin, 'pin:5555');
    expect(repo.lockType, LockType.pin);
    expect(await repo.unlock('pin:5555'), master);
    await expectLater(repo.unlock('pat:0-1-2-5'), _throwsKind(AppErrorKind.wrongCredential));
  });
}
