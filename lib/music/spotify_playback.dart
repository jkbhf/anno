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

/// One of the places a session could play the round, for the picker on the
/// remote control.
///
/// Only a session that commands another app has more than one of these - the
/// SDK is its own device and the link has none - so the list is empty
/// everywhere but in `ConnectSpotifySession`.
class PlaybackDevice {
  const PlaybackDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
  });

  final String id;

  /// What Spotify calls it, which is what the room calls it: `Jakobs iPhone`,
  /// `Samsung TV`, `Küche`.
  final String name;

  /// Spotify's own word - `Smartphone`, `TV`, `Speaker`, `Computer`. Only used
  /// to put an icon next to the name.
  final String type;

  /// Whether Spotify is playing on it right now.
  final bool isActive;
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

  /// How far into the running song the player is. Zero before it has said.
  Duration get position;

  /// How long the running song is. Zero while it is not known, which is also
  /// what tells the playing screen there is nothing to seek in yet.
  Duration get duration;

  /// Why the last song that went out did not play after all, or null.
  ///
  /// Spotify accepts a track first and only then finds it cannot play it - a
  /// DRM stack that refuses, a market that does not carry it. `play` has long
  /// returned true by then, so this is how the round learns that its music
  /// never came. Cleared by the next `play`.
  String? get playbackError;

  /// What connecting buys the room, in words for the card that offers it.
  ///
  /// The two sessions buy different things - the SDK plays the song out of
  /// this page, Connect commands the Spotify app next to it - and a card that
  /// promises the wrong one is a card that lies on half the devices.
  String get offer;

  /// Something the player has to do before a song can play here, although
  /// the login is fine. Null when there is nothing to say.
  String? get hint => null;

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

  /// Jumps to [position] in the running song.
  Future<void> seek(Duration position);

  /// Ends the round's music.
  Future<void> stop();

  /// Whether where the song comes out of is a question at all - and so
  /// whether the remote shows the button that asks it. True only for a
  /// session that commands another app: the SDK is the device itself.
  bool get canPickDevice => false;

  /// The devices the round could come out of, as they were last looked up.
  List<PlaybackDevice> get devices => const [];

  /// The one that was picked by hand, null while the game picks for itself.
  String? get pickedDeviceId => null;

  /// Asks the service for its devices again. The picker does it as it opens,
  /// because a device is only listed while its app is running.
  Future<void> refreshDevices() async {}

  /// Plays on [id] from here on - a running song moves over - or, with null,
  /// hands the choice back to the game.
  Future<void> pickDevice(String? id) async {}

  /// The game is over: stop the music and let go of the device it came out of.
  ///
  /// Not the same as [stop], which ends a round. A speaker or a television
  /// that the game was playing on must not stay coupled to a game that has
  /// finished - the next one looks the device up again, and the room gets its
  /// speaker back.
  Future<void> releasePlayback() => stop();

  /// Takes this page off the account as a speaker, and keeps the login.
  ///
  /// The television is a mirror: it runs the same app, so where the app would
  /// build the Web Playback SDK it registers a device called `Anno` on the
  /// account - and the phone's Connect session then sees a device it may
  /// command and plays the round out of the television's tab. The music has to
  /// stay on the phone, so the screen gives the device up as it becomes a
  /// screen. A session that is no device anyway does nothing here.
  Future<void> releaseDevice() async {}
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
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  String? get playbackError => null;

  @override
  String get offer => '';

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
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}
}
