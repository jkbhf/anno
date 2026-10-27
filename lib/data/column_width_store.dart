import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How wide the side column of the wide layout is, as a share of the screen.
///
/// Kept per device like the lyrics scale and the scores: it depends on the
/// screen the game is run from and on what that room wants to see of the
/// words, not on a game, so it outlives every one of them.
class ColumnWidthStore {
  static const String _key = 'column.share';

  /// What it was before it could be dragged.
  static const double normal = 0.28;

  /// Narrow enough that the camera still reads a card, wide enough that the
  /// stage is still a stage.
  static const double min = 0.16;
  static const double max = 0.5;

  /// One step of a remote command - a television has no pointer to drag the
  /// handle with, so the phone's menu steps it instead.
  static const double step = 0.02;

  static double clamp(double share) => share.clamp(min, max);

  static double stepped(double share, {required bool wider}) =>
      clamp(share + (wider ? step : -step));

  static Future<double> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_key);
      return saved == null ? normal : clamp(saved);
    } on Object catch (error) {
      debugPrint('Column width not readable: $error');
      return normal;
    }
  }

  static Future<void> save(double share) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, share);
    } on Object catch (error) {
      debugPrint('Could not save the column width: $error');
    }
  }
}
