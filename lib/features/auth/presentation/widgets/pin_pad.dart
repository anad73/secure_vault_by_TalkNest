import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/tokens.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/utils/haptics.dart';

/// Numeric keypad with entry dots and a shake animation on error.
///
/// Supports hardware keyboards (digits, Backspace, Enter). Digit order is
/// always left-to-right, also in RTL languages.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmit,
    this.minLength = 4,
    this.maxLength = 12,
    this.errorCount = 0,
    this.enabled = true,
  });

  final ValueChanged<String> onSubmit;
  final int minLength;
  final int maxLength;

  /// Increment to clear the entry and play the error shake.
  final int errorCount;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  final StringBuffer _digits = StringBuffer();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: Motion.slow);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant PinPad old) {
    super.didUpdateWidget(old);
    if (widget.errorCount != old.errorCount) {
      _digits.clear();
      if (!MediaQuery.disableAnimationsOf(context)) _shake.forward(from: 0);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String d) {
    if (!widget.enabled || _digits.length >= widget.maxLength) return;
    Haptics.tap();
    setState(() => _digits.write(d));
  }

  void _backspace() {
    if (!widget.enabled || _digits.isEmpty) return;
    Haptics.tap();
    final s = _digits.toString();
    setState(() {
      _digits
        ..clear()
        ..write(s.substring(0, s.length - 1));
    });
  }

  void _submit() {
    if (!widget.enabled || _digits.length < widget.minLength) return;
    final value = _digits.toString();
    setState(_digits.clear);
    widget.onSubmit(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _add(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.s;
    final canSubmit = _digits.length >= widget.minLength && widget.enabled;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                final dx = math.sin(_shake.value * math.pi * 6) *
                    12 *
                    (1 - _shake.value);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: _Dots(count: _digits.length, max: widget.maxLength),
            ),
            const SizedBox(height: Space.xl),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final d in row) _Key(label: d, onTap: () => _add(d))
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Key(
                  icon: Icons.backspace_outlined,
                  semantic: s.deleteDigit,
                  onTap: _backspace,
                ),
                _Key(label: '0', onTap: () => _add('0')),
                _Key(
                  icon: Icons.arrow_forward_rounded,
                  semantic: s.continueLabel,
                  onTap: canSubmit ? _submit : null,
                  filled: true,
                  color: canSubmit
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  iconColor:
                      canSubmit ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.max});

  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = math.max(4, count);
    return Semantics(
      label: '$count / $max',
      liveRegion: true,
      child: SizedBox(
        height: 20,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < shown; i++)
              AnimatedContainer(
                duration: Motion.fast,
                margin: const EdgeInsets.symmetric(horizontal: Space.xs + 2),
                width: i < count ? 14 : 12,
                height: i < count ? 14 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < count ? scheme.primary : Colors.transparent,
                  border: Border.all(
                    color: i < count ? scheme.primary : scheme.outline,
                    width: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    this.semantic,
    required this.onTap,
    this.filled = false,
    this.color,
    this.iconColor,
  });

  final String? label;
  final IconData? icon;
  final String? semantic;
  final VoidCallback? onTap;
  final bool filled;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = filled
        ? color
        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.all(Space.sm),
      child: Semantics(
        button: true,
        label: semantic ?? label,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: Dimens.pinKey,
              child: Center(
                child: label != null
                    ? Text(label!,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w500))
                    : Icon(icon,
                        color: iconColor ?? theme.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
