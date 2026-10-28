import 'package:flutter/widgets.dart';

/// Scales [child] by [factor] without leaving blank space around it or
/// clipping it - unlike a bare `Transform.scale`, which changes how big the
/// child paints but not how big a box it is given to lay out in.
///
/// Handing the child a box of `size / factor` and then painting that box at
/// `factor` keeps anything sized as a *share* of the box exactly as big as it
/// was - shares are still shares of the same physical screen either way - and
/// shrinks or grows only what was sized in fixed pixels: a projector's
/// padding or icon size, which is exactly the furniture a Fire TV Stick's
/// screen finds oversized.
class UiScale extends StatelessWidget {
  const UiScale({required this.factor, required this.child, super.key});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (factor == 1) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return ClipRect(
          child: Transform.scale(
            scale: factor,
            alignment: Alignment.topLeft,
            // An OverflowBox, not a SizedBox: a SizedBox is clamped to the
            // constraints it is given, so below 1 the box stayed at the
            // screen's size and the scaled picture left empty margins at the
            // bottom and the right.
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: size.width / factor,
              maxWidth: size.width / factor,
              minHeight: size.height / factor,
              maxHeight: size.height / factor,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
