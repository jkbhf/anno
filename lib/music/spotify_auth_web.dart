import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'spotify_auth.dart';
import 'spotify_config.dart';

/// How a request to the token endpoint ended.
///
/// Two ways of failing, and they must not be confused: a token Spotify refused
/// is spent and has to go, while a request that never got an answer says
/// nothing about the token - dropping it there logs the room out over a
/// wobbly Wi-Fi.
enum _TokenResult { ok, rejected, unreachable }

/// The login in the browser: Authorization Code with PKCE.
///
/// A browser cannot keep a client secret, so PKCE replaces it with a one-shot
/// verifier: the app sends the hash on the way out and the verifier itself
/// when redeeming the code, and only the page that started the login can
/// finish it.
class WebSpotifyAuth implements SpotifyAuth {
  static const String _authorizeUrl = 'https://accounts.spotify.com/authorize';
  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';

  /// `streaming` is what makes the tab a device; the player endpoints need the
  /// two `playback-state` scopes, and the SDK insists on the profile pair.
  /// Connect needs nothing beyond them, so both sessions log in the same way
  /// and a device that switches between them never asks for consent again.
  static const String scopes =
      'streaming user-read-email user-read-private '
      'user-modify-playback-state user-read-playback-state';

  static const String _refreshKey = 'spotify.refresh_token';
  static const String _verifierKey = 'spotify.pkce_verifier';
  static const String _stateKey = 'spotify.auth_state';

  static const String unreachable =
      'Spotify is not reachable right now. Check the connection and try again.';

  String? _accessToken;
  DateTime? _expiresAt;
  String? _refreshToken;

  /// The refresh that is on its way. Two at once would send the same refresh
  /// token twice, and Spotify rotates it - the second one would come back
  /// refused and log the session out.
  Future<String?>? _refreshing;

  /// Where Spotify sends the browser back to. Must be registered in the
  /// developer dashboard exactly as it reads here.
  static String get redirectUri =>
      web.window.location.origin + web.window.location.pathname;

  @override
  bool get hasLogin => (_refreshToken ??= _read(_refreshKey)) != null;

  @override
  bool get hasPendingRedirect {
    final params = Uri.parse(web.window.location.href).queryParameters;
    return params['code'] != null || params['error'] != null;
  }

  @override
  Future<LoginResult> restore() async {
    final params = Uri.parse(web.window.location.href).queryParameters;

    if (params['error'] != null) {
      _clearQuery();
      return LoginResult.failed('Spotify login: ${params['error']}');
    }

    final code = params['code'];
    if (code != null) {
      final expected = _read(_stateKey);
      final verifier = _read(_verifierKey);
      _remove(_stateKey);
      _remove(_verifierKey);
      _clearQuery();

      if (verifier == null || expected == null || params['state'] != expected) {
        return const LoginResult.failed('Login came back mismatched.');
      }
      return _redeem(code, verifier);
    }

    if (!hasLogin) return const LoginResult.noLogin();
    return resume();
  }

  /// A refresh token that is still there afterwards means Spotify was not
  /// reached rather than refused, and that is worth a "try again" instead of
  /// a new login.
  @override
  Future<LoginResult> resume() async {
    if (await _refresh() != null) return const LoginResult.loggedIn();
    return _refreshToken != null
        ? const LoginResult.failed(unreachable)
        : const LoginResult.noLogin();
  }

  @override
  Future<void> beginLogin() async {
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
        'scope': scopes,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
      },
    );
    web.window.location.href = target.toString();
  }

  @override
  Future<void> forget() async {
    _accessToken = null;
    _expiresAt = null;
    _refreshToken = null;
    _remove(_refreshKey);
  }

  @override
  Future<String?> freshToken() async {
    final token = _accessToken;
    final expires = _expiresAt;
    if (token != null && expires != null && DateTime.now().isBefore(expires)) {
      return token;
    }
    return _refresh();
  }

  Future<LoginResult> _redeem(String code, String verifier) async {
    final result = await _token({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': spotifyClientId,
      'code_verifier': verifier,
    });
    return switch (result) {
      _TokenResult.ok => const LoginResult.loggedIn(),
      _TokenResult.rejected => const LoginResult.failed(
        'Spotify refused the login.',
      ),
      _TokenResult.unreachable => const LoginResult.failed(unreachable),
    };
  }

  Future<String?> _refresh() {
    return _refreshing ??= _refreshOnce().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<String?> _refreshOnce() async {
    final sent = _refreshToken ??= _read(_refreshKey);
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
}
