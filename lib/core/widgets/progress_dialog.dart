import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../l10n/app_strings.dart';
import '../utils/progress.dart';

export '../utils/progress.dart';

/// Shows a non-dismissible dialog with a linear progress bar while [task]
/// runs, then closes it and returns the task's result (or rethrows).
Future<T> runWithProgress<T>(
  BuildContext context, {
  required String Function(AppStrings s, int done, int total) label,
  required Future<T> Function(ProgressReporter report) task,
}) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  // Not awaited: the dialog stays up while the task runs. The notifier is
  // disposed only after the dialog's exit animation has finished.
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(progress: progress, label: label),
    ),
  ).whenComplete(() {
    open = false;
    progress.dispose();
  });
  try {
    return await task((done, total) {
      if (open) progress.value = (done, total);
    });
  } finally {
    if (open && navigator.mounted) navigator.pop();
    await dialog;
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress, required this.label});

  final ValueNotifier<(int, int)> progress;
  final String Function(AppStrings s, int done, int total) label;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return AlertDialog(
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (done, total) = value;
          final fraction = total == 0 ? null : done / total;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label(s, done, total), style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.lg),
              ClipRRect(
                borderRadius: Radii.smAll,
                child: LinearProgressIndicator(value: fraction, minHeight: 8),
              ),
              const SizedBox(height: Space.md),
              Text(
                s.doNotClose,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}
