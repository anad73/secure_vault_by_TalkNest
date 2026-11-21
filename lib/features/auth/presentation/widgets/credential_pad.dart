import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import 'pattern_pad.dart';
import 'pin_pad.dart';

/// Turns raw PIN digits / pattern nodes into the secret fed to the KDF.
/// The prefix separates the two input spaces.
abstract final class Credential {
  static const int minPatternNodes = 4;

  static String pin(String digits) => 'pin:$digits';

  static String pattern(List<int> nodes) => 'pat:${nodes.join('-')}';
}

/// Shows a [PinPad] or [PatternPad] depending on [type] and reports the
/// encoded secret. Patterns shorter than 4 dots go to [onTooShort].
class CredentialPad extends StatelessWidget {
  const CredentialPad({
    super.key,
    required this.type,
    required this.onSecret,
    required this.onTooShort,
    this.errorCount = 0,
    this.enabled = true,
  });

  final LockType type;
  final ValueChanged<String> onSecret;
  final VoidCallback onTooShort;
  final int errorCount;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      LockType.pin => PinPad(
          key: const ValueKey('pin'),
          enabled: enabled,
          errorCount: errorCount,
          onSubmit: (d) => onSecret(Credential.pin(d)),
        ),
      LockType.pattern => PatternPad(
          key: const ValueKey('pattern'),
          enabled: enabled,
          errorCount: errorCount,
          size: (MediaQuery.sizeOf(context).shortestSide * 0.78)
              .clamp(220.0, 320.0),
          onComplete: (nodes) {
            if (nodes.length < Credential.minPatternNodes) {
              onTooShort();
            } else {
              onSecret(Credential.pattern(nodes));
            }
          },
        ),
    };
  }
}
