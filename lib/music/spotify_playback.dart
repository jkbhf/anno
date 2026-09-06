import 'package:flutter/foundation.dart';

import '../models/song.dart';

/// Where the in-app player stands.
enum SpotifyConnection {
  /// Not this platform, or no client id was compiled in.
  unavailable,

  /// Available, but nobody has logged in.
  disconnected,

  /// Login or SDK handshake is running.
  connecting,

  /// A device is up and songs can be started.
  ready,

  /// The handshake failed - [SpotifySession.error] says why.
  failed,
}

/// Plays songs inside the app instead of handing them over to Spotify.
///
/// Web only. Spotify's Web Playback SDK turns the game tab itself into a
/// Spotify Connect device, so the song comes out of the page: no tab switch,
/// no coming back, and the popup blocker is out of the picture. In exchange it
/// wants Spotify Premium and a user login.
///
/// Everything here is optional. Where there is no session - Android, iOS, no
/// client id, no Premium, not logged in - the app falls back to handing over a
/// link, which is what it did before and what needs nothing at all.
abstract class SpotifySession extends ChangeNotifier {
  SpotifyConnection get connection;

  /// Why the connection failed, in words for the player. Null while fine.
  String? get error;

  /// True while a song is running here.
  bool get isPlaying;

  bool get isReady => connection == SpotifyConnection.ready;

  bool get isAvailable => connection != SpotifyConnection.unavailable;

  /// Picks up a redirect coming back from the Spotify login, or a token kept
  /// from an earlier visit. Called once at startup.
  Future<void> restore();

  /// Sends the browser off to the Spotify login. The page leaves and comes
  /// back to [restore].
  Future<void> connect();

  /// Drops the token and the device.
  Future<void> disconnect();

  /// Unlocks playback, and must be called from inside a user gesture.
  ///
  /// Mobile browsers only let a page make sound as the direct result of a tap.
  /// The round's music starts three seconds later, after the countdown, which
  /// is far too late - so the tap that begins the round arms the player here.
  /// A no-op on desktop, where nothing is locked.
  Future<void> prepare();

  /// Starts the song here. False when it did not play - the caller then falls
  /// back to opening Spotify by link.
  Future<bool> play(Song song);

  /// Pause and resume in one, for the button on the playing screen.
  Future<void> togglePause();

  /// Ends the round's music.
  Future<void> stop();
}

/// The session for platforms without a player: permanently unavailable.
class NoSpotifySession extends SpotifySession {
  @override
  SpotifyConnection get connection => SpotifyConnection.unavailable;

  @override
  String? get error => null;

  @override
  bool get isPlaying => false;

  @override
  Future<void> restore() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<bool> play(Song song) async => false;

  @override
  Future<void> togglePause() async {}

  @override
  Future<void> stop() async {}
}
