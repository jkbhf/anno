import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How tall the top box of the side column is - the reveal button, and after
/// it the year it produced - as a share of the column's height.
///
/// Dragged rather than derived, for the same reason the column's width is
/// ([ColumnWidthStore]): how much of the screen the answer deserves depends on
/// the room it is read in. A projector wants a card that carries across it, a
/// laptop run by hand would rather have the room for the controls under it.
///
/// Kept per device, so it outlives every game.
class SlotHeightStore {
  static const String _key = 'column.slot';

  /// What it was before it could be dragged.
  static const double normal = 0.36;

  /// Small enough that the box is still a button, large enough that it can
  /// take most of the column where that is what the room wants.
  static const double min = 0.18;
  static const double max = 0.6;

  static double clamp(double share) => share.clamp(min, max);

  static Future<double> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_key);
      return saved == null ? normal : clamp(saved);
    } on Object catch (error) {
      debugPrint('Slot height not readable: $error');
      return normal;
    }
  }

  static Future<void> save(double share) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, share);
    } on Object catch (error) {
      debugPrint('Could not save the slot height: $error');
    }
  }
}
