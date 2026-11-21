import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/feedback.dart';
import '../../vault/data/album_repository.dart';
import '../data/auth_repository.dart';
import '../vault_session.dart';
import 'auth_scaffold.dart';
import 'widgets/credential_pad.dart';
import 'widgets/recovery_form.dart';

enum _Mode { create, change, reset }

enum _Step { verifyCurrent, enter, confirm, recovery }

/// One flow for first-run setup, changing the credential, and resetting
/// it after answering the recovery question.
class CredentialSetupScreen extends StatefulWidget {
  const CredentialSetupScreen.create({super.key})
      : _mode = _Mode.create,
        _masterKey = null;

  const CredentialSetupScreen.change({super.key})
      : _mode = _Mode.change,
        _masterKey = null;

  const CredentialSetupScreen.reset({super.key, required Uint8List masterKey})
      : _mode = _Mode.reset,
        _masterKey = masterKey;

  final _Mode _mode;
  final Uint8List? _masterKey;

  @override
  State<CredentialSetupScreen> createState() => _CredentialSetupScreenState();
}

class _CredentialSetupScreenState extends State<CredentialSetupScreen> {
  late _Step _step =
      widget._mode == _Mode.change ? _Step.verifyCurrent : _Step.enter;
  late final AuthRepository _auth;
  late LockType _type;
  String? _first;
  Uint8List? _createdKey;
  bool _busy = false;
  int _errors = 0;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthRepository>();
    _type = _auth.lockType;
  }

  void _fail(String message) {
    Haptics.error();
    setState(() {
      _errors++;
      _busy = false;
      _status = message;
      _statusIsError = true;
    });
  }

  Future<void> _onSecret(String secret) async {
    final s = context.s;
    switch (_step) {
      case _Step.verifyCurrent:
        await _verifyCurrent(secret);
      case _Step.enter:
        setState(() {
          _first = secret;
          _step = _Step.confirm;
          _status = null;
        });
      case _Step.confirm:
        if (secret != _first) {
          _first = null;
          setState(() => _step = _Step.enter);
          _fail(s.mismatch);
          return;
        }
        await _commit(secret);
      case _Step.recovery:
        break;
    }
  }

  Future<void> _verifyCurrent(String secret) async {
    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _status = context.s.checking;
      _statusIsError = false;
    });
    try {
      final key = await auth.unlock(secret);
      key.fillRange(0, key.length, 0);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _step = _Step.enter;
      });
    } on AppException catch (e) {
      if (mounted) _fail(describeError(context.s, e));
    }
  }

  Future<void> _commit(String secret) async {
    final auth = context.read<AuthRepository>();
    final session = context.read<VaultSession>();
    final s = context.s;
    setState(() {
      _busy = true;
      _status = widget._mode == _Mode.create ? s.creatingVault : s.checking;
      _statusIsError = false;
    });
    try {
      switch (widget._mode) {
        case _Mode.create:
          _createdKey = await auth.createVault(_type, secret);
          if (!mounted) return;
          setState(() {
            _busy = false;
            _status = null;
            _step = _Step.recovery;
          });
        case _Mode.change:
          await auth.changeCredential(session.key, _type, secret);
          if (!mounted) return;
          AppFeedback.success(context, s.credentialChanged);
          Navigator.of(context).pop(true);
        case _Mode.reset:
          final key = widget._masterKey!;
          await auth.changeCredential(key, _type, secret);
          if (!mounted) return;
          Navigator.of(context).popUntil((r) => r.isFirst);
          session.unlock(key);
      }
    } catch (e) {
      if (mounted) _fail(describeError(s, e));
    } finally {
      _first = null;
    }
  }

  Future<void> _finishCreate({String? question, String? answer}) async {
    final key = _createdKey!;
    final auth = context.read<AuthRepository>();
    final albums = context.read<AlbumRepository>();
    final session = context.read<VaultSession>();
    final s = context.s;
    setState(() => _busy = true);
    try {
      if (question != null && answer != null) {
        await auth.setRecovery(key, question, answer);
      }
      await albums.ensure(s.defaultAlbumName);
      session.unlock(key);
    } catch (e) {
      if (mounted) _fail(describeError(s, e));
    }
  }

  Future<void> _skipRecovery() async {
    final s = context.s;
    final ok = await AppFeedback.confirm(
      context,
      title: s.recoveryTitle,
      message: s.noRecoveryWarning,
      confirmLabel: s.skip,
      icon: Icons.warning_amber_rounded,
      destructive: true,
    );
    if (ok && mounted) await _finishCreate();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_step == _Step.recovery) {
      return AuthScaffold(
        icon: Icons.help_outline_rounded,
        title: s.recoveryTitle,
        subtitle: s.recoverySubtitle,
        status: _status,
        statusIsError: _statusIsError,
        child: RecoveryForm(
          busy: _busy,
          onSave: (q, a) => _finishCreate(question: q, answer: a),
          secondary: TextButton(
            onPressed: _busy ? null : _skipRecovery,
            child: Text(s.skip),
          ),
        ),
      );
    }

    final isPin = _type == LockType.pin;
    final title = switch (_step) {
      _Step.verifyCurrent => s.enterCurrent,
      _Step.enter => isPin ? s.enterNewPin : s.drawNewPattern,
      _ => isPin ? s.confirmPin : s.confirmPattern,
    };
    return AuthScaffold(
      appBar: widget._mode == _Mode.create
          ? null
          : AppBar(backgroundColor: Colors.transparent),
      icon: _step == _Step.verifyCurrent
          ? Icons.lock_rounded
          : Icons.shield_rounded,
      title: widget._mode == _Mode.create && _step == _Step.enter
          ? s.setupTitle
          : title,
      subtitle: widget._mode == _Mode.create && _step == _Step.enter
          ? '${s.setupSubtitle}\n$title'
          : null,
      status: _status,
      statusIsError: _statusIsError,
      top: _step == _Step.enter
          ? SegmentedButton<LockType>(
              segments: [
                ButtonSegment(
                    value: LockType.pin,
                    icon: const Icon(Icons.dialpad_rounded),
                    label: Text(s.lockTypePin)),
                ButtonSegment(
                    value: LockType.pattern,
                    icon: const Icon(Icons.pattern_rounded),
                    label: Text(s.lockTypePattern)),
              ],
              selected: {_type},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _type = v.first;
                        _status = null;
                      }),
            )
          : null,
      child: Column(
        children: [
          CredentialPad(
            // Verifying uses the *stored* type; new entries use the choice.
            type: _step == _Step.verifyCurrent ? _auth.lockType : _type,
            enabled: !_busy,
            errorCount: _errors,
            onSecret: _onSecret,
            onTooShort: () => _fail(s.patternTooShort),
          ),
          if (_busy) ...[
            const SizedBox(height: Space.lg),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
