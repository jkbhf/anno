import '../models/song.dart';
import 'spotify_launcher.dart';
import 'spotify_playback.dart';

/// Plays through the in-app player where there is one, and hands the song to
/// Spotify by link where there is not.
///
/// The fallback is not an edge case: it is what runs on Android and iOS, what
/// runs without a client id, and what runs for everybody without Premium. The
/// in-app player is the better path when it is there, never a requirement.
class InAppSpotifyLauncher implements SpotifyLauncher {
  const InAppSpotifyLauncher(
    this.session, {
    this.fallback = const UrlSpotifyLauncher(),
  });

  final SpotifySession session;
  final SpotifyLauncher fallback;

  @override
  Future<SpotifyLaunchResult> open(Song song) async {
    if (session.isReady && await session.play(song)) {
      return const SpotifyLaunchResult.ok();
    }
    return fallback.open(song);
  }
}
