import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The code of the room this device was last in, per device.
///
/// It is kept for one reason: a code only exists in the relay's room and on
/// the two devices in it. A television that reloads - a browser that reaped
/// the tab, somebody who pressed the wrong button on the remote - would
/// otherwise come back with a new code while the phone is still holding the
/// old one, and the evening would need re-pairing from both ends.
///
/// On the phone it is worth the same for the opposite reason: the code typed
/// in once is still there next week, so an evening starts by pressing
/// reconnect rather than by reading six characters off the wall again.
class TvRoomStore {
  static const String _key = 'tv.room';

  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      return (saved == null || saved.isEmpty) ? null : saved;
    } on Object catch (error) {
      debugPrint('TV room not readable: $error');
      return null;
    }
  }

  static Future<void> save(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
    } on Object catch (error) {
      debugPrint('Could not save the TV room: $error');
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } on Object catch (error) {
      debugPrint('Could not clear the TV room: $error');
    }
  }
}
