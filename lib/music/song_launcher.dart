import '../models/song.dart';

/// Hands a song to the service that plays it.
///
/// The app does not remote control that service, it only hands over a link -
/// hence no SDK, no login, no Premium requirement and no quota limit from a
/// developer dashboard. The one exception is the in-app Spotify player on the
/// web, see [InAppSpotifyLauncher].
abstract class SongLauncher {
  Future<LaunchResult> open(Song song);
}

class LaunchResult {
  const LaunchResult({required this.opened, this.message, this.inApp = false});

  const LaunchResult.ok() : opened = true, message = null, inApp = false;

  /// The song is coming out of this page - nobody left, so there is nothing to
  /// come back from.
  const LaunchResult.inTab() : opened = true, message = null, inApp = true;

  final bool opened;
  final String? message;

  /// True only when the song really plays here. A session that reports itself
  /// ready is not the same thing: playback still fails on a track the account
  /// cannot play, and then it was the link that ran. Whoever branches on the
  /// two ways has to branch on this, not on the session.
  final bool inApp;
}
