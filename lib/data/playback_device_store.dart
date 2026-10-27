import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which of the account's Spotify devices the round plays on, kept per device.
///
/// It is a statement about the room - the television in front of the sofa, the
/// speaker in the kitchen - and not about a game, so it outlives every game
/// the way the music service and the size of the words do. Null means nobody
/// has picked: `pickConnectDevice` then chooses, which is the phone.
///
/// The id can go stale, and that is fine: Spotify only lists a device while
/// its app is running, so a television that is switched off is simply not
/// there and the automatic pick takes the round. The name is kept beside it so
/// the picker can say what it is waiting for.
///
/// Read synchronously ([id]) because the session asks for it in the middle of
/// handing a song over, and filled by [preload] at startup.
class PlaybackDeviceStore {
  static const String _idKey = 'playback.device.id';
  static const String _nameKey = 'playback.device.name';

  static String? _id;
  static String? _name;

  /// The device picked by hand, or null for whatever the game picks.
  static String? get id => _id;

  /// What that device was called when it was picked.
  static String? get name => _name;

  /// Reads the saved device into memory. Awaited once, at startup.
  static Future<void> preload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _id = prefs.getString(_idKey);
      _name = prefs.getString(_nameKey);
    } on Object catch (error) {
      debugPrint('Playback device not readable: $error');
    }
  }

  static Future<void> save({String? id, String? name}) async {
    _id = id;
    _name = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_idKey);
        await prefs.remove(_nameKey);
        return;
      }
      await prefs.setString(_idKey, id);
      await prefs.setString(_nameKey, name ?? '');
    } on Object catch (error) {
      debugPrint('Could not save the playback device: $error');
    }
  }
}
