import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'song_launcher.dart';
import 'spotify_launcher.dart';
import 'spotify_playback.dart';

/// Plays through the in-app player where there is one, and hands the song to
/// Spotify by link where there is not.
///
/// The fallback is not an edge case: it is what runs on Android and iOS, what
/// runs without a client id, and what runs for everybody without Premium. The
/// in-app player is the better path when it is there, never a requirement.
class InAppSpotifyLauncher implements SongLauncher {
  const InAppSpotifyLauncher(
    this.session, {
    this.fallback = const UrlSpotifyLauncher(),
  });

  final SpotifySession session;
  final SongLauncher fallback;

  @override
  Future<LaunchResult> open(Song song) async {
    if (session.isReady && await _plays(song)) {
      return const LaunchResult.inTab();
    }
    return fallback.open(song);
  }

  /// A player that throws has not played - and that must still end at the
  /// link, not skip past it.
  Future<bool> _plays(Song song) async {
    try {
      return await session.play(song);
    } on Object catch (error) {
      debugPrint('In-app play failed: $error');
      return false;
    }
  }
}
