import 'spotify_playback.dart';

/// Android, iOS, desktop: no Web Playback SDK, so no in-app player.
SpotifySession createSpotifySession() => NoSpotifySession();
