import 'package:flutter/material.dart';

import '../../../../core/design/tokens.dart';
import '../../../../core/l10n/app_strings.dart';

/// Question + answer fields with inline validation.
class RecoveryForm extends StatefulWidget {
  const RecoveryForm({
    super.key,
    required this.onSave,
    this.busy = false,
    this.secondary,
    this.initialQuestion,
  });

  final void Function(String question, String answer) onSave;
  final bool busy;
  final Widget? secondary;
  final String? initialQuestion;

  @override
  State<RecoveryForm> createState() => _RecoveryFormState();
}

class _RecoveryFormState extends State<RecoveryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _q =
      TextEditingController(text: widget.initialQuestion ?? '');
  final TextEditingController _a = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSave(_q.text.trim(), _a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _q,
            enabled: !widget.busy,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: s.recoveryQuestionHint),
            validator: (v) =>
                (v ?? '').trim().length < 3 ? s.recoveryAnswerTooShort : null,
          ),
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: _a,
            enabled: !widget.busy,
            obscureText: _obscure,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: s.recoveryAnswerHint,
              suffixIcon: IconButton(
                tooltip: s.recoveryAnswerHint,
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                (v ?? '').trim().length < 3 ? s.recoveryAnswerTooShort : null,
          ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: widget.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(s.save),
          ),
          if (widget.secondary != null) ...[
            const SizedBox(height: Space.sm),
            widget.secondary!,
          ],
        ],
      ),
    );
  }
}
