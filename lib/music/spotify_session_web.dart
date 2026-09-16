import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../models/song.dart';
import 'spotify_config.dart';
import 'spotify_playback.dart';

SpotifySession createSpotifySession() =>
    spotifyClientId.isEmpty ? NoSpotifySession() : WebSpotifySession();

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

/// How a request to the token endpoint ended.
///
/// Two ways of failing, and they must not be confused: a token Spotify refused
/// is spent and has to go, while a request that never got an answer says
/// nothing about the token - dropping it there logs the room out over a
/// wobbly Wi-Fi.
enum _TokenResult { ok, rejected, unreachable }

/// The in-app player: Spotify's Web Playback SDK plus the login it needs.
///
/// The login is Authorization Code with PKCE. A browser cannot keep a client
/// secret, so PKCE replaces it with a one-shot verifier: the app sends the
/// hash on the way out and the verifier itself when redeeming the code, and
/// only the page that started the login can finish it.
class WebSpotifySession extends SpotifySession {
  static const String _authorizeUrl = 'https://accounts.spotify.com/authorize';
  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const String _apiUrl = 'https://api.spotify.com/v1';

  /// `streaming` is what makes the tab a device; the player endpoints need the
  /// two `playback-state` scopes, and the SDK insists on the profile pair.
  static const String _scopes =
      'streaming user-read-email user-read-private '
      'user-modify-playback-state user-read-playback-state';

  static const String _refreshKey = 'spotify.refresh_token';
  static const String _verifierKey = 'spotify.pkce_verifier';
  static const String _stateKey = 'spotify.auth_state';

  static const String _unreachable =
      'Spotify is not reachable right now. Check the connection and try again.';

  SpotifyConnection _connection = SpotifyConnection.disconnected;
  String? _error;
  bool _isPlaying = false;
  String? _playbackError;

  /// The last position the player reported, and when. Between two reports the
  /// position is carried forward by the clock, see [position].
  int _positionMs = 0;
  int _durationMs = 0;
  DateTime _positionAt = DateTime.now();

  String? _accessToken;
  DateTime? _expiresAt;
  String? _refreshToken;

  /// The refresh that is on its way. Two at once would send the same refresh
  /// token twice, and Spotify rotates it - the second one would come back
  /// refused and log the session out.
  Future<String?>? _refreshing;

  _SdkPlayer? _player;
  String? _deviceId;

  @override
  SpotifyConnection get connection => _connection;

  @override
  String? get error => _error;

  @override
  bool get isPlaying => _isPlaying;

  @override
  String? get playbackError => _playbackError;

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
  static String get redirectUri =>
      web.window.location.origin + web.window.location.pathname;

  void _moveTo(SpotifyConnection next, {String? error}) {
    _connection = next;
    _error = error;
    notifyListeners();
  }

  @override
  Future<void> restore() async {
    final params = Uri.parse(web.window.location.href).queryParameters;

    if (params['error'] != null) {
      _clearQuery();
      _moveTo(
        SpotifyConnection.failed,
        error: 'Spotify login: ${params['error']}',
      );
      return;
    }

    final code = params['code'];
    if (code != null) {
      final expected = _read(_stateKey);
      final verifier = _read(_verifierKey);
      _remove(_stateKey);
      _remove(_verifierKey);
      _clearQuery();

      if (verifier == null || expected == null || params['state'] != expected) {
        _moveTo(SpotifyConnection.failed, error: 'Login came back mismatched.');
        return;
      }
      _moveTo(SpotifyConnection.connecting);
      final ok = await _redeem(code, verifier);
      if (ok) await _startPlayer();
      return;
    }

    _refreshToken = _read(_refreshKey);
    if (_refreshToken == null) {
      _moveTo(SpotifyConnection.disconnected);
      return;
    }
    await _resume();
  }

  /// Picks the stored login back up. A refresh token that is still there
  /// afterwards means Spotify was not reached rather than refused, and that is
  /// worth a "try again" instead of a new login.
  Future<void> _resume() async {
    _moveTo(SpotifyConnection.connecting);
    if (await _refresh() != null) {
      await _startPlayer();
    } else if (_refreshToken != null) {
      _moveTo(SpotifyConnection.failed, error: _unreachable);
    } else {
      _moveTo(SpotifyConnection.disconnected);
    }
  }

  @override
  Future<void> connect() async {
    // "Try again" after a network failure: the login is still good, so going
    // through Spotify's login page again would only cost the room a detour.
    _refreshToken ??= _read(_refreshKey);
    if (_refreshToken != null && _player == null) {
      await _resume();
      if (_connection != SpotifyConnection.disconnected) return;
    }

    final verifier = _randomString(64);
    final state = _randomString(16);
    _write(_verifierKey, verifier);
    _write(_stateKey, state);

    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');

    final target = Uri.parse(_authorizeUrl).replace(
      queryParameters: {
        'client_id': spotifyClientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': _scopes,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
      },
    );
    _moveTo(SpotifyConnection.connecting);
    web.window.location.href = target.toString();
  }

  @override
  Future<void> disconnect() async {
    await stop();
    _player?.disconnect();
    _player = null;
    _deviceId = null;
    _accessToken = null;
    _expiresAt = null;
    _refreshToken = null;
    _remove(_refreshKey);
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
      final token = await _freshToken();
      if (token == null) return false;

      final uri = song.spotifyTrackId != null
          ? 'spotify:track:${song.spotifyTrackId}'
          : await _searchUri(token, song);
      if (uri == null) return false;

      final response = await http.put(
        Uri.parse('$_apiUrl/me/player/play?device_id=$device'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'uris': [uri],
        }),
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

  /// The song for a catalog entry that has no track id yet - the same search
  /// the reveal would otherwise send the player to by hand.
  ///
  /// Quoted like the resolver's: `track:Diese Welt` unquoted searches for
  /// "Diese" alone and would play some other song in the tab.
  Future<String?> _searchUri(String token, Song song) async {
    final query = Uri.encodeQueryComponent(
      'track:"${song.title}" artist:"${song.artist}"',
    );
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/search?q=$query&type=track&limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return null;
      final items = (jsonDecode(response.body)['tracks']['items'] as List)
          .cast<Map<String, dynamic>>();
      return items.isEmpty ? null : items.first['uri'] as String;
    } on Object catch (error) {
      debugPrint('Search failed: $error');
      return null;
    }
  }

  // --- tokens ---------------------------------------------------------------

  Future<String?> _freshToken() async {
    final token = _accessToken;
    final expires = _expiresAt;
    if (token != null && expires != null && DateTime.now().isBefore(expires)) {
      return token;
    }
    return _refresh();
  }

  Future<bool> _redeem(String code, String verifier) async {
    final result = await _token({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': spotifyClientId,
      'code_verifier': verifier,
    });
    switch (result) {
      case _TokenResult.ok:
        return true;
      case _TokenResult.rejected:
        _moveTo(SpotifyConnection.failed, error: 'Spotify refused the login.');
      case _TokenResult.unreachable:
        _moveTo(SpotifyConnection.failed, error: _unreachable);
    }
    return false;
  }

  Future<String?> _refresh() {
    return _refreshing ??= _refreshOnce().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<String?> _refreshOnce() async {
    final sent = _refreshToken;
    if (sent == null) return null;

    switch (await _refreshWith(sent)) {
      case _TokenResult.ok:
        return _accessToken;
      case _TokenResult.unreachable:
        // Nothing is known about the token - keep it for the next attempt.
        return null;
      case _TokenResult.rejected:
        break;
    }

    // Another tab of the game may have rotated the token in the meantime and
    // stored the new one. That one is good, and deleting it would log both out.
    final stored = _read(_refreshKey);
    if (stored != null && stored != sent) {
      _refreshToken = stored;
      final retry = await _refreshWith(stored);
      if (retry == _TokenResult.ok) return _accessToken;
      if (retry == _TokenResult.unreachable) return null;
    }

    // The stored token is spent or was revoked - back to a fresh login.
    _refreshToken = null;
    if (_read(_refreshKey) == stored) _remove(_refreshKey);
    return null;
  }

  Future<_TokenResult> _refreshWith(String token) => _token({
    'grant_type': 'refresh_token',
    'refresh_token': token,
    'client_id': spotifyClientId,
  });

  Future<_TokenResult> _token(Map<String, String> body) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      if (response.statusCode != 200) {
        debugPrint('Token failed (${response.statusCode}): ${response.body}');
        // 400 is `invalid_grant` - the token is spent. Anything else, a 5xx or
        // a rate limit, is Spotify having a moment.
        return response.statusCode == 400 || response.statusCode == 401
            ? _TokenResult.rejected
            : _TokenResult.unreachable;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _accessToken = json['access_token'] as String;
      _expiresAt = DateTime.now().add(
        // A minute of slack, so a token never expires mid-round.
        Duration(seconds: (json['expires_in'] as int) - 60),
      );
      // Spotify rotates the refresh token; keeping the old one locks us out.
      final rotated = json['refresh_token'] as String?;
      if (rotated != null) {
        _refreshToken = rotated;
        _write(_refreshKey, rotated);
      }
      return _TokenResult.ok;
    } on Object catch (error) {
      debugPrint('Token failed: $error');
      return _TokenResult.unreachable;
    }
  }

  // --- the SDK --------------------------------------------------------------

  Future<void> _startPlayer() async {
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
          _freshToken().then((token) {
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

  // --- browser bits ---------------------------------------------------------

  /// Takes `?code=...` back out of the address bar, so a reload does not try
  /// to redeem a code that is already spent.
  void _clearQuery() => web.window.history.replaceState(null, '', redirectUri);

  String? _read(String key) => web.window.localStorage.getItem(key);

  void _write(String key, String value) =>
      web.window.localStorage.setItem(key, value);

  void _remove(String key) => web.window.localStorage.removeItem(key);

  static String _randomString(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < length; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
  }

  @override
  void dispose() {
    _player?.disconnect();
    super.dispose();
  }
}
