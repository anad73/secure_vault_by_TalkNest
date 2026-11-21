import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Frosted-glass panel. Used selectively (viewer chrome, selection bar)
/// because backdrop blur is expensive; wrapped in a RepaintBoundary.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = Radii.lgAll,
    this.padding = EdgeInsets.zero,
    this.blur = 18,
    this.tint,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = tint ?? scheme.surface.withValues(alpha: dark ? 0.55 : 0.7);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius,
              border: Border.all(
                color:
                    scheme.outlineVariant.withValues(alpha: dark ? 0.25 : 0.4),
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Circular badge with the brand gradient, used for hero icons.
class GradientBadge extends StatelessWidget {
  const GradientBadge({super.key, required this.icon, this.size = 88});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Brand.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Brand.accentA.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.46),
    );
  }
}
