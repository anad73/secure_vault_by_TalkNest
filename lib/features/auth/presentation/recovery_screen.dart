import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/l10n/app_strings.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';
import 'credential_setup_screen.dart';

/// "Forgot PIN?" – answers the recovery question, then sets a new
/// credential for the same master key (no data loss).
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _answer = TextEditingController();
  late final AuthRepository _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthRepository>();
  }

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _answer.text.trim().isEmpty) return;
    final auth = _auth;
    final s = context.s;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await auth.recover(_answer.text);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => CredentialSetupScreen.reset(masterKey: key),
      ));
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.kind == AppErrorKind.wrongCredential
            ? s.errWrongCredential
            : describeError(s, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final auth = _auth;
    final question = auth.recoveryQuestion;
    return AuthScaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      icon: Icons.key_rounded,
      title: s.resetTitle,
      subtitle: auth.hasRecovery ? s.answerQuestion : s.noRecoverySet,
      status: _error,
      statusIsError: true,
      child: !auth.hasRecovery
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(question ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: Space.lg),
                TextField(
                  controller: _answer,
                  enabled: !_busy,
                  autofocus: true,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(labelText: s.recoveryAnswerHint),
                ),
                const SizedBox(height: Space.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4))
                      : Text(s.continueLabel),
                ),
              ],
            ),
    );
  }
}
