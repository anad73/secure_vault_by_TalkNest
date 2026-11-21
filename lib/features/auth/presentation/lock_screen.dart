import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../data/auth_repository.dart';
import '../data/biometric_service.dart';
import '../vault_session.dart';
import 'auth_scaffold.dart';
import 'recovery_screen.dart';
import 'widgets/credential_pad.dart';

/// Shown whenever the vault is set up but locked.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late final AuthRepository _auth;
  late final BiometricService _bio;
  late final VaultSession _session;

  bool _busy = false;
  bool _bioEnabled = false;
  int _errors = 0;
  String? _status;
  bool _statusIsError = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthRepository>();
    _bio = context.read<BiometricService>();
    _session = context.read<VaultSession>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshLockout();
      _initBiometric();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _initBiometric() async {
    final enabled = await _bio.isEnabled();
    if (!mounted) return;
    setState(() => _bioEnabled = enabled);
    if (enabled && _auth.lockoutRemaining == null) await _unlockWithBiometric();
  }

  void _refreshLockout() {
    _ticker?.cancel();
    final left = _auth.lockoutRemaining;
    if (left == null) return;
    _setLockoutStatus(left);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final l = _auth.lockoutRemaining;
      if (!mounted) {
        t.cancel();
        return;
      }
      if (l == null) {
        t.cancel();
        setState(() => _status = null);
      } else {
        _setLockoutStatus(l);
      }
    });
  }

  void _setLockoutStatus(Duration left) {
    setState(() {
      _status = context.s.lockedOutFor(t: Fmt.duration(left));
      _statusIsError = true;
    });
  }

  Future<void> _unlock(String secret) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = context.s.checking;
      _statusIsError = false;
    });
    try {
      final key = await _auth.unlock(secret);
      Haptics.success();
      _session.unlock(key);
    } on AppException catch (e) {
      if (!mounted) return;
      Haptics.error();
      setState(() {
        _errors++;
        _busy = false;
        _statusIsError = true;
        _status = e.kind == AppErrorKind.wrongCredential &&
                _auth.attemptsLeft > 0
            ? '${context.s.errWrongCredential} ${context.s.attemptsLeft(n: _auth.attemptsLeft)}'
            : describeError(context.s, e);
      });
      _refreshLockout();
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_busy) return;
    final key = await _bio.unlock(context.s.biometricReason);
    if (key == null) {
      if (!mounted) return;
      // Entry may have been invalidated (new fingerprint enrolled).
      final still = await _bio.isEnabled();
      if (mounted) setState(() => _bioEnabled = still);
      return;
    }
    _session.unlock(key);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final type = _auth.lockType;
    final lockedOut = _auth.lockoutRemaining != null;
    return AuthScaffold(
      icon: Icons.lock_rounded,
      title: type == LockType.pin ? s.enterPin : s.drawPattern,
      subtitle: s.vaultLocked,
      status: _status,
      statusIsError: _statusIsError,
      footer: Wrap(
        alignment: WrapAlignment.center,
        spacing: Space.sm,
        children: [
          if (_bioEnabled)
            TextButton.icon(
              onPressed: _busy || lockedOut ? null : _unlockWithBiometric,
              icon: const Icon(Icons.fingerprint_rounded),
              label: Text(s.useBiometric),
            ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const RecoveryScreen()),
                    ),
            child: Text(s.forgotPin),
          ),
        ],
      ),
      child: CredentialPad(
        type: type,
        enabled: !_busy && !lockedOut,
        errorCount: _errors,
        onSecret: _unlock,
        onTooShort: () => setState(() {
          _errors++;
          _status = s.patternTooShort;
          _statusIsError = true;
        }),
      ),
    );
  }
}
