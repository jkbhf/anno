import 'dart:math';

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
/// The scrollable still gets the pointers, though, and two fingers moving are
/// a drag to it - so [onActive] says when a pinch is on and whoever owns the
/// list holds it still for that moment. Without it the words slid away under
/// the fingers and ended up somewhere else than they started (2026-10-27).
class PinchScale extends StatefulWidget {
  const PinchScale({
    required this.scaleOf,
    required this.onScale,
    required this.child,
    this.onActive,
    super.key,
  });

  /// The factor in force when a pinch starts - what the gesture multiplies.
  final double Function() scaleOf;

  /// The factor the fingers are asking for. Clamping is the receiver's.
  final ValueChanged<double> onScale;

  /// True while two fingers are down, so whatever scrolls under this can hold
  /// still - see [_damping] for why that matters.
  final ValueChanged<bool>? onActive;

  final Widget child;

  /// How much of the fingers' movement reaches the size.
  ///
  /// Pulled apart to twice the distance, a raw pinch doubles the type in one
  /// go, which overshoots every time: the words are set once for a room and
  /// what is wanted is a nudge. At 0.45 the same gesture is about a third
  /// bigger, so the size can be walked up to rather than jumped past.
  static const double _damping = 0.45;

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
    if (_points.length >= 2) widget.onActive?.call(true);
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
    // Damped, see [PinchScale._damping].
    widget.onScale(
      _fromScale * pow(now / from, PinchScale._damping).toDouble(),
    );
  }

  void _up(int pointer) {
    _points.remove(pointer);
    if (_points.length < 2) {
      _fromDistance = null;
      widget.onActive?.call(false);
    }
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
