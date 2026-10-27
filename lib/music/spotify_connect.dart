import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/playback_device_store.dart';
import '../models/song.dart';
import 'spotify_api.dart';
import 'spotify_auth.dart';
import 'spotify_playback.dart';

/// One of the devices the account can play on, as the API lists them.
class ConnectDevice extends PlaybackDevice {
  const ConnectDevice({
    required super.id,
    required super.name,
    required super.type,
    required super.isActive,
    required this.isRestricted,
  });

  factory ConnectDevice.fromJson(Map<String, dynamic> json) => ConnectDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? '',
    isActive: json['is_active'] as bool? ?? false,
    isRestricted: json['is_restricted'] as bool? ?? false,
  );

  /// Spotify says this device refuses commands from the Web API - a car, a
  /// games console, some speakers. Playing to it answers 204 and then nothing
  /// happens, which is worse than falling back to the link.
  final bool isRestricted;

  bool get isUsable => id.isNotEmpty && !isRestricted;
}

/// Which of the account's devices the round should come out of.
///
/// **A phone wins, even over a device that is already playing**, because this
/// session exists for exactly one device: the Spotify app on the phone that is
/// running the game. The room is at the phone, and the alternative is worse
/// than it looks - a television with Spotify on it, or a second screen running
/// this very page, is a device the account has lying around, and the round
/// then comes out of the wall while the phone holds the controls. After the
/// phone comes whatever is active, then a tablet and a speaker; a computer is
/// last rather than excluded, because a laptop without Premium in the tab can
/// still command its own desktop app.
///
/// So a Connect speaker is not picked while a phone is listed. That is the
/// deliberate half of it: the way to play through a speaker is the speaker
/// being the phone's own output, which sits below Spotify and is none of this
/// function's business.
ConnectDevice? pickConnectDevice(Iterable<ConnectDevice> devices) {
  final usable = devices.where((device) => device.isUsable).toList();
  if (usable.isEmpty) return null;

  ConnectDevice? firstWhere(bool Function(ConnectDevice) test) {
    for (final device in usable) {
      if (test(device)) return device;
    }
    return null;
  }

  bool ofType(ConnectDevice device, String type) =>
      device.type.toLowerCase() == type;

  return firstWhere((device) => ofType(device, 'smartphone')) ??
      firstWhere((device) => device.isActive) ??
      firstWhere((device) => ofType(device, 'tablet')) ??
      firstWhere((device) => ofType(device, 'speaker')) ??
      usable.first;
}

/// Plays through Spotify Connect: the song comes out of a device the account
/// already has, and this page only commands it.
///
/// The device that matters is the phone's own Spotify app, which is why this
/// is the session a phone gets - Spotify's Web Playback SDK does not run in a
/// mobile browser. What it buys is the same as the SDK buys: the game knows
/// the position, can seek and pause, and so the words can follow the song and
/// the seek bar means something. The sound just comes out of another app
/// instead of out of the page.
///
/// Three things are different from the SDK and each is load-bearing:
///
/// - **There has to be a device.** Spotify lists an app that has been open
///   recently; one that has never run in this session is not there. A round
///   with no device falls back to the link, which opens the Spotify app - and
///   from the next round on there is a device. So the first round of an
///   evening may go out by link and the rest play here.
/// - **Nothing is pushed, so the position is polled** every [poll] and carried
///   forward by the clock in between, the same way the SDK's reports are.
/// - **A failure is an HTTP status, not an event.** There is no
///   `playback_error` after the fact: either the command was taken or it was
///   not, and what was not taken ends at the link.
class ConnectSpotifySession extends SpotifySession {
  ConnectSpotifySession({
    required SpotifyAuth auth,
    http.Client? client,
    DateTime Function() now = DateTime.now,
    this.poll = const Duration(seconds: 2),
  }) : _auth = auth,
       _client = client ?? http.Client(),
       _now = now;

  /// How often the running song is asked where it is. Far slower than the
  /// words need - they read [position], which runs on the clock between two
  /// answers - and slow enough that an evening stays well inside Spotify's
  /// rate limit.
  final Duration poll;

  final SpotifyAuth _auth;
  final http.Client _client;
  final DateTime Function() _now;

  SpotifyConnection _connection = SpotifyConnection.disconnected;
  String? _error;
  bool _isPlaying = false;

  int _positionMs = 0;
  int _durationMs = 0;
  late DateTime _positionAt = _now();

  String? _deviceId;
  String? _deviceName;

  /// The account's devices as they were last listed, for the picker on the
  /// remote. Only the usable ones get out, see [devices].
  List<ConnectDevice> _listed = const [];

  /// True from a song that started until the round's music is stopped. The
  /// poll runs only then: nothing else on this page wants the position, and a
  /// timer that outlives the round is a request a minute for nothing.
  bool _tracking = false;
  Timer? _timer;

  @override
  SpotifyConnection get connection => _connection;

  @override
  String? get error => _error;

  @override
  bool get isPlaying => _isPlaying;

  /// Always null: Connect answers a command it cannot carry out with a status,
  /// so a round that got this far really is playing. The after-the-fact
  /// failure this reports is the SDK's alone.
  @override
  String? get playbackError => null;

  @override
  Duration get duration => Duration(milliseconds: _durationMs);

  @override
  Duration get position {
    var ms = _positionMs;
    if (_isPlaying) ms += _now().difference(_positionAt).inMilliseconds;
    if (_durationMs > 0) ms = min(ms, _durationMs);
    return Duration(milliseconds: max(ms, 0));
  }

  @override
  String get offer =>
      'Connect Spotify Premium and the game runs the song in your Spotify '
      'app - the words follow along and you can skip through it from here.';

  /// The one thing a player has to know and cannot guess: Spotify only lists
  /// an app that is running. Said while the login is fine and no device
  /// answered, which is exactly when the next round would go out by link.
  ///
  /// And once there is one, it says which one. The account can have a
  /// television and a speaker on it, and the round coming out of the wrong one
  /// is the kind of evening nobody can debug from the game screen - so the
  /// name of the device is on the card before the first card is scanned.
  @override
  String? get hint {
    if (_connection != SpotifyConnection.ready) return null;
    if (_deviceId == null) {
      return 'Open Spotify on this phone once, then the game can play the '
          'song there itself.';
    }
    final name = _deviceName;
    return name == null ? null : 'The song plays on $name.';
  }

  /// The device the round plays on, for whoever wants to know which speaker
  /// just lit up. Null until one was found.
  String? get deviceName => _deviceName;

  /// This is the session where it is a question: the song comes out of another
  /// app, and the account can have several that could take it.
  @override
  bool get canPickDevice => true;

  @override
  List<PlaybackDevice> get devices => [
    for (final device in _listed)
      if (device.isUsable) device,
  ];

  @override
  String? get pickedDeviceId => PlaybackDeviceStore.id;

  @override
  Future<void> refreshDevices() async {
    final token = await _auth.freshToken();
    if (token == null) return;
    await _lookUp(token);
  }

  /// Plays on [id] from here on, or hands the choice back to
  /// [pickConnectDevice] with null.
  ///
  /// A song that is running moves over rather than starting again: Spotify's
  /// transfer keeps the position, and the room is in the middle of a round.
  @override
  Future<void> pickDevice(String? id) async {
    ConnectDevice? device;
    for (final listed in _listed) {
      if (listed.id == id) device = listed;
    }
    await PlaybackDeviceStore.save(id: id, name: device?.name);

    if (id == null) {
      // Not simply cleared: the round that is on could still be moved, and
      // the next one has to find something.
      final token = await _auth.freshToken();
      if (token == null) {
        _deviceId = null;
        _deviceName = null;
        notifyListeners();
        return;
      }
      final next = await _lookUp(token);
      if (next != null && _isPlaying) await _transfer(next, token: token);
      return;
    }

    _deviceId = id;
    _deviceName = device?.name;
    notifyListeners();
    if (_isPlaying) await _transfer(id);
  }

  /// Hands the running song over to [id], which is how a pick mid-round
  /// reaches the new speaker. The poll puts the position right either way.
  Future<void> _transfer(String id, {String? token}) async {
    final bearer = token ?? await _auth.freshToken();
    if (bearer == null) return;
    final status = await _put(
      '/me/player',
      token: bearer,
      body: jsonEncode({
        'device_ids': [id],
        'play': true,
      }),
    );
    // 404 is a device that has gone away between the list and the tap. The
    // round goes on where it is rather than falling silent.
    if (status == 404) await _lookUp(bearer);
  }

  /// The game is over: the music stops and the device is let go of, so a
  /// television or a speaker is not still held by a game nobody is playing.
  /// What was picked by hand stays picked - that is a setting of the room's.
  @override
  Future<void> releasePlayback() async {
    await stop();
    if (_deviceId == null && _deviceName == null) return;
    _deviceId = null;
    _deviceName = null;
    notifyListeners();
  }

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

  Future<void> _after(LoginResult result) async {
    switch (result.state) {
      case LoginState.loggedIn:
        _moveTo(SpotifyConnection.ready);
        // Not awaited by the caller's reckoning either way: the card is ready
        // now, and the device only decides what the first round does.
        await _findDevice();
      case LoginState.noLogin:
        _moveTo(SpotifyConnection.disconnected);
      case LoginState.failed:
        _moveTo(SpotifyConnection.failed, error: result.message);
    }
  }

  @override
  Future<void> connect() async {
    if (_auth.hasLogin) {
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
    _deviceId = null;
    _deviceName = null;
    await _auth.forget();
    _moveTo(SpotifyConnection.disconnected);
  }

  /// Nothing to unlock - the sound comes out of another app, so no browser is
  /// holding it back. The gesture is spent looking for the device instead, so
  /// the round itself does not have to wait for that answer.
  @override
  Future<void> prepare() async {
    if (_connection == SpotifyConnection.ready) await _findDevice();
  }

  @override
  Future<bool> play(Song song) async {
    _positionMs = 0;
    _durationMs = 0;
    _positionAt = _now();
    _isPlaying = false;

    final token = await _auth.freshToken();
    if (token == null) return false;

    final uri = await spotifyTrackUri(_client, token, song);
    if (uri == null) return false;

    var device = _deviceId ?? await _findDevice(token: token);
    if (device == null) return false;

    var status = await _put(
      '/me/player/play?device_id=$device',
      token: token,
      body: spotifyPlayBody(uri),
    );
    if (status == 404) {
      // The app this id belonged to has gone away since it was listed. Worth
      // one more look - a phone that woke up has a new id, not none.
      device = await _findDevice(token: token, again: true);
      if (device == null) return false;
      status = await _put(
        '/me/player/play?device_id=$device',
        token: token,
        body: spotifyPlayBody(uri),
      );
    }
    if (status != 204 && status != 202) {
      if (status == 403) {
        _error = 'Spotify Premium is needed to play the song from here.';
        notifyListeners();
      }
      return false;
    }

    _isPlaying = true;
    _positionAt = _now();
    _tracking = true;
    notifyListeners();
    // Soon, not at the full interval: the duration arrives with the first
    // answer, and until it is known there is nothing to seek in.
    _schedule(const Duration(milliseconds: 600));
    return true;
  }

  @override
  Future<void> togglePause() async {
    final token = await _auth.freshToken();
    if (token == null) return;
    final wasPlaying = _isPlaying;
    // Moved at once, so the button and the words do not wait for a round trip.
    // The next poll puts it right if Spotify disagreed.
    _positionMs = position.inMilliseconds;
    _positionAt = _now();
    _isPlaying = !wasPlaying;
    notifyListeners();
    await _put(
      wasPlaying ? '/me/player/pause' : '/me/player/play',
      token: token,
    );
    if (_isPlaying) _schedule(const Duration(milliseconds: 600));
  }

  @override
  Future<void> seek(Duration to) async {
    if (_durationMs == 0) return;
    final token = await _auth.freshToken();
    if (token == null) return;
    final ms = to.inMilliseconds.clamp(0, _durationMs);
    _positionMs = ms;
    _positionAt = _now();
    notifyListeners();
    await _put('/me/player/seek?position_ms=$ms', token: token);
  }

  @override
  Future<void> stop() async {
    _tracking = false;
    _timer?.cancel();
    _timer = null;
    if (!_isPlaying) return;
    _isPlaying = false;
    notifyListeners();
    final token = await _auth.freshToken();
    if (token == null) return;
    await _put('/me/player/pause', token: token);
  }

  // --- the device -----------------------------------------------------------

  /// Looks the playable device up, and keeps it. Returns its id, or null when
  /// the account has nothing running that the API may command.
  Future<String?> _findDevice({String? token, bool again = false}) async {
    if (_deviceId != null && !again) return _deviceId;
    final bearer = token ?? await _auth.freshToken();
    if (bearer == null) return null;
    return _lookUp(bearer);
  }

  /// Lists the account's devices, keeps the list for the picker and settles on
  /// one: what was picked by hand where it is there, otherwise
  /// [pickConnectDevice].
  ///
  /// A pick that is not in the list is a device whose app is not running - a
  /// television that is off, a phone that has not been touched since this
  /// morning. It stays saved and the round goes to the automatic pick, which
  /// is the phone: better the wrong speaker than a round with no sound.
  Future<String?> _lookUp(String token) async {
    final body = await _get('/me/player/devices', token: token);
    if (body == null) return null;

    final list = (body['devices'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ConnectDevice.fromJson)
        .toList();
    _listed = list;

    final want = PlaybackDeviceStore.id;
    ConnectDevice? device;
    if (want != null) {
      for (final listed in list) {
        if (listed.id == want && listed.isUsable) device = listed;
      }
    }
    device ??= pickConnectDevice(list);

    _deviceId = device?.id;
    _deviceName = device?.name;
    notifyListeners();
    return _deviceId;
  }

  // --- the poll -------------------------------------------------------------

  void _schedule(Duration delay) {
    if (!_tracking) return;
    _timer?.cancel();
    _timer = Timer(delay, _tick);
  }

  /// One look at the player, then the next look - a chain rather than a
  /// periodic timer, so a slow answer never stacks two requests.
  Future<void> _tick() async {
    _timer = null;
    if (!_tracking) return;

    final token = await _auth.freshToken();
    if (token == null) return;
    final body = await _get('/me/player', token: token);
    if (!_tracking) return;

    // 204: nothing is playing anywhere. Spotify also answers that for a few
    // hundred milliseconds right after a track was handed over, so it only
    // means the round is over once a position has been seen.
    if (body != null) {
      final playing = body['is_playing'] as bool? ?? false;
      final progress = body['progress_ms'] as int? ?? 0;
      final item = body['item'] as Map<String, dynamic>?;
      final length = item?['duration_ms'] as int? ?? _durationMs;
      final device = body['device'] as Map<String, dynamic>?;
      final deviceId = device?['id'] as String?;

      // What the page would have shown without asking. Anything inside a
      // second is the clock doing its job, and a rebuild for it is noise.
      final drift = (progress - position.inMilliseconds).abs();
      final changed =
          playing != _isPlaying || length != _durationMs || drift > 1000;

      _isPlaying = playing;
      _positionMs = progress;
      _durationMs = length;
      _positionAt = _now();
      if (deviceId != null && deviceId != _deviceId) {
        // The room moved the music to another speaker. Follow it, or every
        // command after this would go to a device nobody is listening to.
        _deviceId = deviceId;
        _deviceName = device?['name'] as String?;
      }
      if (changed) notifyListeners();
    }

    _schedule(poll);
  }

  // --- requests -------------------------------------------------------------

  Future<Map<String, dynamic>?> _get(
    String path, {
    required String token,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$spotifyApiUrl$path'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 204 || response.body.isEmpty) return null;
      if (response.statusCode != 200) {
        debugPrint('Connect GET $path (${response.statusCode})');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Object catch (error) {
      debugPrint('Connect GET $path failed: $error');
      return null;
    }
  }

  /// The status, or 0 where the request never got an answer - which a caller
  /// must treat as "did not play" and never as "played".
  Future<int> _put(String path, {required String token, String? body}) async {
    try {
      final response = await _client.put(
        Uri.parse('$spotifyApiUrl$path'),
        headers: spotifyHeaders(token),
        body: body,
      );
      if (response.statusCode >= 400) {
        debugPrint('Connect PUT $path (${response.statusCode})');
      }
      return response.statusCode;
    } on Object catch (error) {
      debugPrint('Connect PUT $path failed: $error');
      return 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
