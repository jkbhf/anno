import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/song.dart';
import 'song_launcher.dart';

/// Opens songs in Spotify, in the app where there is one.
class UrlSpotifyLauncher implements SongLauncher {
  const UrlSpotifyLauncher();

  /// Deep link into the installed app - plays the track directly.
  static Uri? appUri(Song song) {
    final id = song.spotifyTrackId;
    return id == null ? null : Uri.parse('spotify:track:$id');
  }

  /// Fallback through the browser or the redirect of open.spotify.com.
  static Uri webUri(Song song) {
    final id = song.spotifyTrackId;
    if (id != null) return Uri.parse('https://open.spotify.com/track/$id');
    final query = Uri.encodeComponent('${song.title} ${song.artist}');
    return Uri.parse('https://open.spotify.com/search/$query');
  }

  /// On the web the result says nothing about success: url_launcher_web calls
  /// `window.open` with `noopener`, which cannot report back whether the popup
  /// blocker swallowed the tab. Hence the manual button on the playing screen.
  @override
  Future<LaunchResult> open(Song song) async {
    // url_launcher only knows http(s) on the web, and a browser would not hand
    // `spotify:` to the desktop app from a background tab anyway.
    final direct = kIsWeb ? null : appUri(song);
    if (direct != null && await _tryLaunch(direct)) {
      return const LaunchResult.ok();
    }
    if (await _tryLaunch(webUri(song))) {
      return LaunchResult(
        opened: true,
        message: song.spotifyTrackId == null
            ? 'No track on file - Spotify shows the search.'
            : null,
      );
    }
    return const LaunchResult(
      opened: false,
      message: 'Spotify would not open. Look the song up by hand.',
    );
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception catch (error) {
      debugPrint('Could not open $uri: $error');
      return false;
    }
  }
}
