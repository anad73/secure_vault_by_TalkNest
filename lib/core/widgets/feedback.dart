import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../errors/error_mapper.dart';
import '../l10n/app_strings.dart';
import '../utils/haptics.dart';

/// Snackbars and dialogs shared by all screens.
abstract final class AppFeedback {
  static void success(BuildContext context, String message) {
    Haptics.success();
    _show(context, message, Icons.check_circle_rounded, null);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, Icons.info_outline_rounded, null);
  }

  static void error(BuildContext context, Object error) {
    Haptics.error();
    _show(context, describeError(context.s, error), Icons.error_outline_rounded,
        Theme.of(context).colorScheme.error);
  }

  static void _show(
      BuildContext context, String message, IconData icon, Color? iconColor) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final scheme = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(icon,
              color: iconColor ?? scheme.onInverseSurface, size: IconSizes.md),
          const SizedBox(width: Space.md),
          Expanded(child: Text(message)),
        ]),
      ));
  }

  /// Confirmation dialog. Returns true only when the user confirms.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    required String confirmLabel,
    bool destructive = false,
    IconData? icon,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: icon == null
            ? null
            : Icon(icon, color: destructive ? scheme.error : scheme.primary),
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.s.cancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Single text field dialog (album names). Validation runs inline.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    required String label,
    String initial = '',
    required String confirmLabel,
    String? Function(String value)? validator,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: title,
        label: label,
        initial: initial,
        confirmLabel: confirmLabel,
        validator: validator,
      ),
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
    this.validator,
  });

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;
  final String? Function(String value)? validator;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    final err = widget.validator?.call(v);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: widget.label, errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.s.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
