import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A normalized keep rectangle, independent of screen pixels or PDF points.
class CropOverlay extends StatefulWidget {
  final Rect rectangle;
  final ValueChanged<Rect> onChanged;
  final Widget child;
  final bool enabled;
  const CropOverlay({
    super.key,
    required this.rectangle,
    required this.onChanged,
    required this.child,
    this.enabled = true,
  });
  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  Offset _anchor = Offset.zero;
  Rect _start = Rect.zero;
  int _handle = -1;
  Offset _point(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0, 1),
    (point.dy / size.height).clamp(0, 1),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.precise : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: !widget.enabled
              ? null
              : (event) {
                  _anchor = _point(event.localPosition, size);
                  _start = widget.rectangle;
                  final corners = [
                    _start.topLeft,
                    _start.topRight,
                    _start.bottomRight,
                    _start.bottomLeft,
                  ];
                  _handle = -1;
                  for (var i = 0; i < 4; i++) {
                    final delta = corners[i] - _anchor;
                    if (math.sqrt(
                          math.pow(delta.dx * size.width, 2) +
                              math.pow(delta.dy * size.height, 2),
                        ) <
                        20) {
                      _handle = i;
                      break;
                    }
                  }
                  if (_handle == -1 &&
                      _start.contains(_anchor) &&
                      _start != const Rect.fromLTWH(0, 0, 1, 1))
                    _handle = 4;
                },
          onPanUpdate: !widget.enabled
              ? null
              : (event) {
                  final point = _point(event.localPosition, size);
                  Rect next;
                  if (_handle == 4) {
                    final move = point - _anchor;
                    next = Rect.fromLTWH(
                      (_start.left + move.dx).clamp(0, 1 - _start.width),
                      (_start.top + move.dy).clamp(0, 1 - _start.height),
                      _start.width,
                      _start.height,
                    );
                  } else {
                    final opposites = [
                      _start.bottomRight,
                      _start.bottomLeft,
                      _start.topLeft,
                      _start.topRight,
                    ];
                    next = Rect.fromPoints(
                      _handle < 0 ? _anchor : opposites[_handle],
                      point,
                    );
                  }
                  if (next.width >= .01 && next.height >= .01)
                    widget.onChanged(next);
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              IgnorePointer(
                child: CustomPaint(painter: _CropPainter(widget.rectangle)),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CropPainter extends CustomPainter {
  final Rect normalized;
  const _CropPainter(this.normalized);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      normalized.left * size.width,
      normalized.top * size.height,
      normalized.right * size.width,
      normalized.bottom * size.height,
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: .55),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppTheme.amber,
    );
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: 8, height: 8),
        Paint()..color = AppTheme.amber,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.normalized != normalized;
}
