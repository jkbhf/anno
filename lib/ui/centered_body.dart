import 'package:flutter/widgets.dart';

import 'layout.dart';

/// Caps the content width.
///
/// The game is built for a phone held in a group; in a desktop browser window
/// the same layout would otherwise stretch across the whole screen.
class CenteredBody extends StatelessWidget {
  const CenteredBody({required this.child, this.maxWidth = 560, super.key});

  final Widget child;

  /// The cap for a screen taller than wide. A short landscape screen - a phone
  /// turned over, which is not the wide layout's device - gets more than this:
  /// a 560 strip in the middle of it leaves a third of the screen empty on
  /// either side, and the blocks of the upright layout have to be squeezed
  /// into its little height rather than being allowed the width that is
  /// standing there unused.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cap = isShortLandscape(size)
        ? (size.width * 0.8).clamp(maxWidth, 860.0)
        : maxWidth;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: child,
      ),
    );
  }
}
