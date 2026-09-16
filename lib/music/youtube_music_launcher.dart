import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/song.dart';
import 'song_launcher.dart';

/// Opens songs in YouTube Music.
///
/// There is no custom scheme to go through: the https link is the deep link.
/// Android and iOS hand `music.youtube.com` to the app where it is installed,
/// everywhere else it opens in the browser. So one url serves every platform,
/// and there is no in-app player to fall back from.
class YouTubeMusicLauncher implements SongLauncher {
  const YouTubeMusicLauncher();

  static Uri uri(Song song) {
    final id = song.youtubeVideoId;
    if (id != null) return Uri.parse('https://music.youtube.com/watch?v=$id');
    return Uri.https('music.youtube.com', '/search', {
      'q': '${song.title} ${song.artist}',
    });
  }

  /// Like [UrlSpotifyLauncher.open], a success on the web says nothing: a
  /// swallowed popup reports back the same way, hence the manual button on
  /// the playing screen.
  @override
  Future<LaunchResult> open(Song song) async {
    try {
      if (await launchUrl(uri(song), mode: LaunchMode.externalApplication)) {
        return LaunchResult(
          opened: true,
          message: song.youtubeVideoId == null
              ? 'No video on file - YouTube Music shows the search.'
              : null,
        );
      }
    } on Exception catch (error) {
      debugPrint('Could not open ${uri(song)}: $error');
    }
    return const LaunchResult(
      opened: false,
      message: 'YouTube Music would not open. Look the song up by hand.',
    );
  }
}
