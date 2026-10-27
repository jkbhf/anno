import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../models/song.dart';
import 'spotify_api.dart';
import 'spotify_auth.dart';
import 'spotify_auth_web.dart';
import 'spotify_config.dart';
import 'spotify_connect.dart';
import 'spotify_playback.dart';

/// The session for this device, and the one place the two players are chosen
/// between.
///
/// The Web Playback SDK is a desktop thing: Spotify does not support it in a
/// mobile browser, and where it loads at all it answers the first track with a
/// `playback_error`. A phone therefore goes straight to Spotify Connect, which
/// commands the Spotify app the phone already has - that is also the player a
/// phone needs when it is the remote control for a TV. The laptop keeps the
/// SDK, where the song comes out of the tab itself.
///
/// Both end at the link where they cannot play - see `InAppSpotifyLauncher`.
SpotifySession createSpotifySession() {
  if (spotifyClientId.isEmpty) return NoSpotifySession();
  return _isPhone
      ? ConnectSpotifySession(auth: WebSpotifyAuth())
      : WebSpotifySession();
}

/// On the web `defaultTargetPlatform` is the operating system, so a phone and
/// a tablet say Android or iOS and every laptop says something else - the same
/// reading `hasKeyboard` makes in `lib/ui/layout.dart`.
bool get _isPhone =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// `new Spotify.Player(...)`, the device the SDK builds inside the page.
@JS('Spotify.Player')
extension type _SdkPlayer._(JSObject _) implements JSObject {
  external factory _SdkPlayer(JSObject options);

  external JSPromise<JSBoolean> connect();
  external void disconnect();
  external void addListener(String event, JSFunction callback);
  external JSPromise<JSAny?> pause();
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> seek(int positionMs);

  /// Hands the media element a user gesture, which is what mobile browsers
  /// want before a page may make sound.
  external JSPromise<JSAny?> activateElement();
}

/// The in-app player: Spotify's Web Playback SDK plus the login it needs.
class WebSpotifySession extends SpotifySession {
  WebSpotifySession({SpotifyAuth? auth}) : _auth = auth ?? WebSpotifyAuth();

  final SpotifyAuth _auth;

  SpotifyConnection _connection = SpotifyConnection.disconnected;
  String? _error;
  bool _isPlaying = false;
  String? _playbackError;

  /// The last position the player reported, and when. Between two reports the
  /// position is carried forward by the clock, see [position].
  int _positionMs = 0;
  int _durationMs = 0;
  DateTime _positionAt = DateTime.now();

  _SdkPlayer? _player;
  String? _deviceId;

  /// True once this page has given its device up, see [releaseDevice]. A
  /// `restore` that is still in flight must not build the player behind it,
  /// and neither must the SDK's own ready callback.
  bool _released = false;

  @override
  SpotifyConnection get connection => _connection;

  @override
  String? get error => _error;

  @override
  bool get isPlaying => _isPlaying;

  @override
  String? get playbackError => _playbackError;

  @override
  String get offer =>
      'Connect Spotify Premium and the song comes out of this page - no '
      'new tab, no switching back.';

  @override
  Duration get duration => Duration(milliseconds: _durationMs);

  @override
  Duration get position {
    var ms = _positionMs;
    if (_isPlaying) {
      ms += DateTime.now().difference(_positionAt).inMilliseconds;
    }
    if (_durationMs > 0) ms = min(ms, _durationMs);
    return Duration(milliseconds: max(ms, 0));
  }

  /// Where Spotify sends the browser back to. Must be registered in the
  /// developer dashboard exactly as it reads here.
  static String get redirectUri => WebSpotifyAuth.redirectUri;

  void _moveTo(SpotifyConnection next, {String? error}) {
    _connection = next;
    _error = error;
    notifyListeners();
  }

  @override
  Future<void> restore() async {
    if (!_auth.hasPendingRedirect && !_auth.hasLogin) {
      _moveTo(SpotifyConnection.disconnected);
      return;
    }
    _moveTo(SpotifyConnection.connecting);
    await _after(await _auth.restore());
  }

  /// What a login that came back is worth to the player.
  Future<void> _after(LoginResult result) async {
    switch (result.state) {
      case LoginState.loggedIn:
        await _startPlayer();
      case LoginState.noLogin:
        _moveTo(SpotifyConnection.disconnected);
      case LoginState.failed:
        _moveTo(SpotifyConnection.failed, error: result.message);
    }
  }

  @override
  Future<void> connect() async {
    // "Try again" after a network failure: the login is still good, so going
    // through Spotify's login page again would only cost the room a detour.
    if (_auth.hasLogin && _player == null) {
      _moveTo(SpotifyConnection.connecting);
      await _after(await _auth.resume());
      if (_connection != SpotifyConnection.disconnected) return;
    }
    _moveTo(SpotifyConnection.connecting);
    await _auth.beginLogin();
  }

  @override
  Future<void> disconnect() async {
    await stop();
    _player?.disconnect();
    _player = null;
    _deviceId = null;
    await _auth.forget();
    _moveTo(SpotifyConnection.disconnected);
  }

  @override
  Future<void> prepare() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.activateElement().toDart;
    } on Object catch (error) {
      // Desktop browsers do not need it and some refuse it outright; the round
      // must not hang on a nicety.
      debugPrint('activateElement: $error');
    }
  }

  @override
  Future<bool> play(Song song) async {
    _playbackError = null;
    _positionMs = 0;
    _durationMs = 0;
    _positionAt = DateTime.now();

    final device = _deviceId;
    if (device == null) return false;
    try {
      final token = await _auth.freshToken();
      if (token == null) return false;

      final uri = await spotifyTrackUri(http.Client(), token, song);
      if (uri == null) return false;

      final response = await http.put(
        Uri.parse('$spotifyApiUrl/me/player/play?device_id=$device'),
        headers: spotifyHeaders(token),
        body: spotifyPlayBody(uri),
      );
      if (response.statusCode == 204 || response.statusCode == 202) {
        _isPlaying = true;
        _positionAt = DateTime.now();
        notifyListeners();
        return true;
      }
      debugPrint('Play failed (${response.statusCode}): ${response.body}');
      return false;
    } on Object catch (error) {
      // A cast on an odd answer throws an Error, not an Exception - and
      // anything that escapes here would skip the fallback to the link.
      debugPrint('Play failed: $error');
      return false;
    }
  }

  @override
  Future<void> togglePause() async {
    final player = _player;
    if (player == null) return;
    try {
      if (_isPlaying) {
        await player.pause().toDart;
      } else {
        await player.resume().toDart;
      }
    } on Object catch (error) {
      debugPrint('Pause/resume failed: $error');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null || _durationMs == 0) return;
    final ms = position.inMilliseconds.clamp(0, _durationMs);
    // Moved at once, so the bar does not jump back while the player catches
    // up - its next report puts it right if it landed elsewhere.
    _positionMs = ms;
    _positionAt = DateTime.now();
    notifyListeners();
    try {
      await player.seek(ms).toDart;
    } on Object catch (error) {
      debugPrint('Seek failed: $error');
    }
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null || !_isPlaying) return;
    try {
      await player.pause().toDart;
    } on Object catch (error) {
      debugPrint('Stop failed: $error');
    }
  }

  @override
  Future<void> releaseDevice() async {
    _released = true;
    await stop();
    _player?.disconnect();
    _player = null;
    _deviceId = null;
    _isPlaying = false;
    _moveTo(SpotifyConnection.disconnected);
  }

  // --- the SDK --------------------------------------------------------------

  Future<void> _startPlayer() async {
    if (_released) return;
    _moveTo(SpotifyConnection.connecting);
    if (_player != null) {
      // Already built - a reconnect only needed a fresh token.
      if (_deviceId != null) _moveTo(SpotifyConnection.ready);
      return;
    }
    if (globalContext.has('Spotify')) {
      _buildPlayer();
      return;
    }
    // The SDK calls this the moment it has loaded, so it has to sit on the
    // window before the script does.
    globalContext.setProperty(
      'onSpotifyWebPlaybackSDKReady'.toJS,
      (() => _buildPlayer()).toJS,
    );
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.src = 'https://sdk.scdn.co/spotify-player.js';
    script.async = true;
    // Offline, or an ad blocker that knows the host: without this the card
    // would say "connecting" forever.
    script.onerror = ((web.Event _) {
      script.remove();
      _moveTo(
        SpotifyConnection.failed,
        error:
            'The Spotify player could not be loaded. Check the connection, '
            'or whether an ad blocker holds it back.',
      );
    }).toJS;
    web.document.head!.appendChild(script);
  }

  void _buildPlayer() {
    if (_released) return;
    final options = JSObject();
    options.setProperty('name'.toJS, 'Anno'.toJS);
    options.setProperty('volume'.toJS, 0.8.toJS);
    // Called by the SDK on connect and whenever its token runs out - which is
    // exactly when the cached one is dead, so it has to be refreshed here, not
    // handed back stale. Stale, the SDK fails with `authentication_error` an
    // hour into the evening and every round after goes out by link.
    options.setProperty(
      'getOAuthToken'.toJS,
      ((JSFunction give) {
        unawaited(
          _auth.freshToken().then((token) {
            give.callAsFunction(null, (token ?? '').toJS);
          }),
        );
      }).toJS,
    );

    final player = _SdkPlayer(options);
    _player = player;

    player.addListener(
      'ready',
      ((JSObject device) {
        _deviceId = (device.getProperty('device_id'.toJS) as JSString).toDart;
        _moveTo(SpotifyConnection.ready);
      }).toJS,
    );
    player.addListener(
      'not_ready',
      ((JSObject _) {
        _deviceId = null;
        _moveTo(SpotifyConnection.connecting);
      }).toJS,
    );
    player.addListener(
      'player_state_changed',
      ((JSObject? state) => _onState(state)).toJS,
    );

    for (final failure in const [
      'initialization_error',
      'authentication_error',
      'account_error',
      'playback_error',
    ]) {
      player.addListener(
        failure,
        ((JSObject problem) => _onSdkError(failure, problem)).toJS,
      );
    }

    unawaited(
      player.connect().toDart.then(
        (connected) {
          if (connected.toDart) return;
          _moveTo(
            SpotifyConnection.failed,
            error: 'The Spotify player would not connect.',
          );
        },
        onError: (Object error) {
          _moveTo(SpotifyConnection.failed, error: 'Spotify player: $error');
        },
      ),
    );
  }

  void _onState(JSObject? state) {
    if (state == null) {
      // Playback moved to another device, or ended there.
      _isPlaying = false;
      notifyListeners();
      return;
    }
    final paused = state.getProperty('paused'.toJS) as JSBoolean?;
    final position = state.getProperty('position'.toJS) as JSNumber?;
    final duration = state.getProperty('duration'.toJS) as JSNumber?;
    _isPlaying = !(paused?.toDart ?? true);
    _positionMs = position?.toDartInt ?? 0;
    _durationMs = duration?.toDartInt ?? _durationMs;
    _positionAt = DateTime.now();
    notifyListeners();
  }

  void _onSdkError(String kind, JSObject problem) {
    final raw = (problem.getProperty('message'.toJS) as JSString?)?.toDart;
    // The one everybody hits: the SDK is a Premium-only feature.
    final message = kind == 'account_error'
        ? 'Spotify Premium is needed to play in the app.'
        : raw ?? 'Spotify player: $kind';
    if (kind == 'playback_error') {
      // One track that will not play must not tear the session down - but the
      // round it belongs to has to hear about it, see [playbackError].
      debugPrint('Playback error: $message');
      _playbackError = message;
      _isPlaying = false;
      notifyListeners();
      return;
    }
    _moveTo(SpotifyConnection.failed, error: message);
  }

  @override
  void dispose() {
    _player?.disconnect();
    super.dispose();
  }
}
