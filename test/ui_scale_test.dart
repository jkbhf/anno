import 'package:anno/ui/ui_scale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final factor in [0.7, 1.4]) {
    testWidgets('a factor of $factor still fills the whole screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: UiScale(
            factor: factor,
            child: const SizedBox.expand(key: Key('inner')),
          ),
        ),
      );

      // The painted box reaches the bottom and right edges, no margins.
      final rect = tester.getRect(find.byKey(const Key('inner')));
      expect(rect.width, closeTo(1000, 0.5));
      expect(rect.height, closeTo(600, 0.5));
    });
  }
}
