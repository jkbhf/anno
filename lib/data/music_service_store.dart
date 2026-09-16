import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../music/music_service.dart';

/// The service this device plays songs in, picked on the setup screen.
///
/// Kept apart from [GameStore] for the same reason as [RosterStore]: a saved
/// game is cleared when it ends, and the choice of service is worth keeping
/// across all of them.
class MusicServiceStore {
  static const String _key = 'music.service';

  static Future<MusicService> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return MusicService.fromName(prefs.getString(_key));
    } on Exception catch (error) {
      debugPrint('Music service not readable: $error');
      return MusicService.spotify;
    }
  }

  static Future<void> save(MusicService service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, service.name);
    } on Exception catch (error) {
      debugPrint('Could not save the music service: $error');
    }
  }
}
