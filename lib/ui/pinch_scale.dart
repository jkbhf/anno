import 'package:flutter/widgets.dart';

/// Two fingers on the words make them bigger or smaller.
///
/// Built on a [Listener] and not on a [GestureDetector], deliberately: a
/// scale gesture joins the arena and wins against the drag of the scrollable
/// under it, which would cost the words their scrolling - the one thing a
/// finger does with them far more often than resizing. A raw pointer never
/// competes, so both work: one finger scrolls, two resize.
///
/// Only the distance between the two fingers is read, never the focal point.
/// The list keeps scrolling under a pinch, which is the lesser evil and barely
/// noticeable next to a text that cannot be scrolled at all.
class PinchScale extends StatefulWidget {
  const PinchScale({
    required this.scaleOf,
    required this.onScale,
    required this.child,
    super.key,
  });

  /// The factor in force when a pinch starts - what the gesture multiplies.
  final double Function() scaleOf;

  /// The factor the fingers are asking for. Clamping is the receiver's.
  final ValueChanged<double> onScale;

  final Widget child;

  @override
  State<PinchScale> createState() => _PinchScaleState();
}

class _PinchScaleState extends State<PinchScale> {
  final Map<int, Offset> _points = {};

  /// The distance the pinch started at, and the factor it started from. Null
  /// while fewer than two fingers are down.
  double? _fromDistance;
  double _fromScale = 1;

  double? get _distance {
    if (_points.length < 2) return null;
    final points = _points.values.toList();
    final gap = (points[0] - points[1]).distance;
    // Two fingers in the same spot would divide by nothing.
    return gap < 24 ? null : gap;
  }

  void _down(PointerDownEvent event) {
    _points[event.pointer] = event.position;
    _begin();
  }

  void _begin() {
    final distance = _distance;
    if (distance == null) return;
    _fromDistance = distance;
    _fromScale = widget.scaleOf();
  }

  void _move(PointerMoveEvent event) {
    if (!_points.containsKey(event.pointer)) return;
    _points[event.pointer] = event.position;
    final from = _fromDistance;
    final now = _distance;
    if (now == null) return;
    if (from == null) {
      _begin();
      return;
    }
    widget.onScale(_fromScale * now / from);
  }

  void _up(int pointer) {
    _points.remove(pointer);
    if (_points.length < 2) _fromDistance = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: widget.child,
    );
  }
}
