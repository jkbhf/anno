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

  /// Hands the media element a user gesture, which is what mobile browsers
  /// want before a page may make sound.
  external JSPromise<JSAny?> activateElement();
}

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

  SpotifyConnection _connection = SpotifyConnection.disconnected;
  String? _error;
  bool _isPlaying = false;

  String? _accessToken;
  DateTime? _expiresAt;
  String? _refreshToken;

  _SdkPlayer? _player;
  String? _deviceId;

  @override
  SpotifyConnection get connection => _connection;

  @override
  String? get error => _error;

  @override
  bool get isPlaying => _isPlaying;

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
    _moveTo(SpotifyConnection.connecting);
    if (await _refresh() != null) {
      await _startPlayer();
    } else {
      _moveTo(SpotifyConnection.disconnected);
    }
  }

  @override
  Future<void> connect() async {
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
    final device = _deviceId;
    if (device == null) return false;
    final token = await _freshToken();
    if (token == null) return false;

    final uri = song.spotifyTrackId != null
        ? 'spotify:track:${song.spotifyTrackId}'
        : await _searchUri(token, song);
    if (uri == null) return false;

    try {
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
        notifyListeners();
        return true;
      }
      debugPrint('Play failed (${response.statusCode}): ${response.body}');
      return false;
    } on Exception catch (error) {
      debugPrint('Play failed: $error');
      return false;
    }
  }

  @override
  Future<void> togglePause() async {
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      await player.pause().toDart;
    } else {
      await player.resume().toDart;
    }
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null || !_isPlaying) return;
    await player.pause().toDart;
  }

  /// The song for a catalog entry that has no track id yet - the same search
  /// the reveal would otherwise send the player to by hand.
  Future<String?> _searchUri(String token, Song song) async {
    final query = Uri.encodeQueryComponent(
      'track:${song.title} artist:${song.artist}',
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
    } on Exception catch (error) {
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
    final ok = await _token({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': spotifyClientId,
      'code_verifier': verifier,
    });
    if (!ok) {
      _moveTo(SpotifyConnection.failed, error: 'Spotify refused the login.');
    }
    return ok;
  }

  Future<String?> _refresh() async {
    final refresh = _refreshToken;
    if (refresh == null) return null;
    final ok = await _token({
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
      'client_id': spotifyClientId,
    });
    if (!ok) {
      // The stored token is spent or was revoked - back to a fresh login.
      _refreshToken = null;
      _remove(_refreshKey);
      return null;
    }
    return _accessToken;
  }

  Future<bool> _token(Map<String, String> body) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      if (response.statusCode != 200) {
        debugPrint('Token failed (${response.statusCode}): ${response.body}');
        return false;
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
      return true;
    } on Exception catch (error) {
      debugPrint('Token failed: $error');
      return false;
    }
  }

  // --- the SDK --------------------------------------------------------------

  Future<void> _startPlayer() async {
    _moveTo(SpotifyConnection.connecting);
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
    web.document.head!.appendChild(script);
  }

  void _buildPlayer() {
    final options = JSObject();
    options.setProperty('name'.toJS, 'Play'.toJS);
    options.setProperty('volume'.toJS, 0.8.toJS);
    // Called by the SDK on connect and whenever its token runs out.
    options.setProperty(
      'getOAuthToken'.toJS,
      ((JSFunction give) {
        give.callAsFunction(null, (_accessToken ?? '').toJS);
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
      ((JSObject? state) {
        final paused = state?.getProperty('paused'.toJS) as JSBoolean?;
        _isPlaying = state != null && !(paused?.toDart ?? true);
        notifyListeners();
      }).toJS,
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

    player.connect();
  }

  void _onSdkError(String kind, JSObject problem) {
    final raw = (problem.getProperty('message'.toJS) as JSString?)?.toDart;
    // The one everybody hits: the SDK is a Premium-only feature.
    final message = kind == 'account_error'
        ? 'Spotify Premium is needed to play in the app.'
        : raw ?? 'Spotify player: $kind';
    if (kind == 'playback_error') {
      // One track that will not play must not tear the session down.
      debugPrint('Playback error: $message');
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
