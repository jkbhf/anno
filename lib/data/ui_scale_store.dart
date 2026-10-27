import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A factor on the whole wide layout, for a television whose furniture -
/// fixed paddings and icon sizes sized for a projector - looks oversized or
/// undersized at the distance and resolution of this particular screen.
///
/// Kept per device like the lyrics scale and the column width: it is a
/// property of this screen and this room, not of a game, so it outlives
/// every one of them. Unlike the lyrics scale it only applies to the
/// television - the layout played directly has a mouse to drag its own
/// handles with and no furniture problem the handles do not already solve.
class UiScaleStore {
  static const String _key = 'ui.scale';

  /// The layout's own sizing, unscaled.
  static const double normal = 1;

  /// Far enough either way to be worth a button, close enough that nothing
  /// on the screen is lost at either end.
  static const double min = 0.5;
  static const double max = 1.5;

  /// One press of smaller or bigger. A factor rather than a step, so a press
  /// does the same amount of work at either end of the range.
  static const double step = 1.1;

  /// [scale] a press smaller or bigger, kept inside the range.
  static double stepped(double scale, {required bool bigger}) =>
      (bigger ? scale * step : scale / step).clamp(min, max);

  static Future<double> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_key);
      return saved == null ? normal : saved.clamp(min, max);
    } on Object catch (error) {
      debugPrint('UI scale not readable: $error');
      return normal;
    }
  }

  static Future<void> save(double scale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, scale);
    } on Object catch (error) {
      debugPrint('Could not save the UI scale: $error');
    }
  }
}
