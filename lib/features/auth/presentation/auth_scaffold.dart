import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/glass.dart';

/// Shared layout for lock, setup and recovery screens: gradient badge,
/// title, status line and the input area, centred and scrollable so it
/// works on small screens, in landscape and with large fonts.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.status,
    this.statusIsError = false,
    required this.child,
    this.footer,
    this.top,
    this.appBar,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? status;
  final bool statusIsError;
  final Widget child;
  final Widget? footer;
  final Widget? top;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: appBar,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.2,
            colors: [scheme.primary.withValues(alpha: 0.16), scheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.xl, vertical: Space.xl),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: Dimens.maxContentWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (top != null) ...[
                      top!,
                      const SizedBox(height: Space.lg)
                    ],
                    GradientBadge(icon: icon, size: 76),
                    const SizedBox(height: Space.lg),
                    Text(title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center),
                    if (subtitle != null) ...[
                      const SizedBox(height: Space.sm),
                      Text(subtitle!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: Space.md),
                    SizedBox(
                      height: 40,
                      child: AnimatedSwitcher(
                        duration: Motion.medium,
                        child: status == null
                            ? const SizedBox.shrink()
                            : Text(
                                status!,
                                key: ValueKey(status),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: statusIsError
                                      ? scheme.error
                                      : scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    child,
                    if (footer != null) ...[
                      const SizedBox(height: Space.lg),
                      footer!
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
