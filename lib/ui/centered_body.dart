import 'package:flutter/widgets.dart';

/// Caps the content width.
///
/// The game is built for a phone held in a group; in a desktop browser window
/// the same layout would otherwise stretch across the whole screen.
class CenteredBody extends StatelessWidget {
  const CenteredBody({required this.child, this.maxWidth = 560, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
