import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';

/// 3×3 unlock pattern. Calls [onComplete] with the node indices (0..8)
/// when the finger lifts.
class PatternPad extends StatefulWidget {
  const PatternPad({
    super.key,
    required this.onComplete,
    this.errorCount = 0,
    this.enabled = true,
    this.size = 280,
  });

  final ValueChanged<List<int>> onComplete;
  final int errorCount;
  final bool enabled;
  final double size;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> _path = [];
  Offset? _finger;
  bool _error = false;

  @override
  void didUpdateWidget(covariant PatternPad old) {
    super.didUpdateWidget(old);
    if (widget.errorCount != old.errorCount) {
      setState(() => _error = true);
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _error = false;
            _path.clear();
          });
        }
      });
    }
  }

  Offset _center(int i) {
    final cell = widget.size / 3;
    return Offset((i % 3) * cell + cell / 2, (i ~/ 3) * cell + cell / 2);
  }

  int? _hit(Offset p) {
    final radius = widget.size / 9;
    for (var i = 0; i < 9; i++) {
      if ((p - _center(i)).distance <= radius) return i;
    }
    return null;
  }

  void _visit(Offset p) {
    final i = _hit(p);
    if (i == null || _path.contains(i)) return;
    // Auto-include a skipped middle node (e.g. 0 -> 2 passes 1).
    if (_path.isNotEmpty) {
      final a = _path.last;
      final ar = a ~/ 3, ac = a % 3, br = i ~/ 3, bc = i % 3;
      if ((ar + br).isEven && (ac + bc).isEven) {
        final mid = ((ar + br) ~/ 2) * 3 + (ac + bc) ~/ 2;
        if (mid != a && mid != i && !_path.contains(mid)) _path.add(mid);
      }
    }
    _path.add(i);
    Haptics.tap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        onPanStart: widget.enabled
            ? (d) => setState(() {
                  _error = false;
                  _path.clear();
                  _visit(d.localPosition);
                  _finger = d.localPosition;
                })
            : null,
        onPanUpdate: widget.enabled
            ? (d) => setState(() {
                  _visit(d.localPosition);
                  _finger = d.localPosition;
                })
            : null,
        onPanEnd: widget.enabled
            ? (_) {
                setState(() => _finger = null);
                if (_path.isNotEmpty) {
                  widget.onComplete(List.unmodifiable(_path));
                }
              }
            : null,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _PatternPainter(
              path: List.of(_path),
              finger: _finger,
              center: _center,
              color: _error ? scheme.error : scheme.primary,
              idle: scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.path,
    required this.finger,
    required this.center,
    required this.color,
    required this.idle,
  });

  final List<int> path;
  final Offset? finger;
  final Offset Function(int) center;
  final Color color;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < path.length; i++) {
      canvas.drawLine(center(path[i - 1]), center(path[i]), line);
    }
    if (path.isNotEmpty && finger != null) {
      canvas.drawLine(center(path.last), finger!, line);
    }
    for (var i = 0; i < 9; i++) {
      final active = path.contains(i);
      final c = center(i);
      if (active) {
        canvas.drawCircle(
            c, 22, Paint()..color = color.withValues(alpha: 0.18));
      }
      canvas.drawCircle(
          c, active ? 9 : 7, Paint()..color = active ? color : idle);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.path.length != path.length ||
      old.finger != finger ||
      old.color != color;
}
