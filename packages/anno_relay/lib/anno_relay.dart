import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// The relay between the phone that runs the game and the screen that shows
/// it.
///
/// It forwards and nothing else. **It does not know the game's messages**, on
/// purpose: a field added to a snapshot must not mean a service to redeploy on
/// a machine in a cupboard. All it reads is the room a socket asked for; the
/// payload goes through as it came.
///
/// There is no state to keep either. A room is its sockets and dies with the
/// last of them - a room that outlived an evening would be a code somebody
/// else's phone could walk into.
class RelayServer {
  RelayServer({
    this.maxRooms = 100,
    this.maxPerRoom = 8,
    this.codeLength = 6,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// A code of six digits is what somebody reads off a television across
  /// the room and types into a number pad - digits only, so the phone never
  /// has to open a full keyboard for it.
  static const String alphabet = '0123456789';

  /// Above this a message is dropped rather than forwarded. A snapshot is a
  /// few hundred bytes; anything near this is not the game.
  static const int maxMessageBytes = 64 * 1024;

  /// Keeps the socket alive through whatever sits between it and here. An
  /// idle WebSocket is closed by most proxies after a minute or two, and a
  /// round can easily be quiet for longer than that.
  static const Duration pingEvery = Duration(seconds: 25);

  final int maxRooms;
  final int maxPerRoom;
  final int codeLength;
  final Random _random;

  final Map<String, Set<WebSocket>> _rooms = {};

  HttpServer? _server;

  int get roomCount => _rooms.length;

  Future<void> start({Object address = '127.0.0.1', int port = 8787}) async {
    final server = await HttpServer.bind(address, port);
    _server = server;
    stdout.writeln('anno relay on ${server.address.address}:${server.port}');
    unawaited(_serve(server));
  }

  /// The port it really got, which is what a test that bound port 0 needs.
  int? get port => _server?.port;

  Future<void> stop() async {
    for (final sockets in _rooms.values.toList()) {
      for (final socket in sockets.toList()) {
        await socket.close(WebSocketStatus.goingAway);
      }
    }
    _rooms.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        // Something to answer a health check with, and a word for whoever
        // opens the address in a browser to see whether it is up.
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('anno relay, $roomCount rooms\n');
        await request.response.close();
        continue;
      }
      unawaited(_accept(request));
    }
  }

  Future<void> _accept(HttpRequest request) async {
    final asked = request.uri.queryParameters['room']?.toUpperCase();
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object catch (error) {
      stderr.writeln('upgrade failed: $error');
      return;
    }
    socket.pingInterval = pingEvery;

    final isHost = request.uri.queryParameters['host'] == '1';

    final String code;
    if (isHost && asked != null && _looksLikeCode(asked)) {
      // The screen coming back to the room it had: a dropped socket must not
      // cost the code, or the phone is left holding a number nobody answers.
      code = asked;
      _rooms.putIfAbsent(code, () => <WebSocket>{});
      if (_rooms.length > maxRooms) {
        _rooms.remove(code);
        await _refuse(socket, 'The relay is full.');
        return;
      }
    } else if (asked == null || asked.isEmpty) {
      // The screen opens the room, because the screen is where the code is
      // read off.
      final fresh = _freshCode();
      if (fresh == null) {
        await _refuse(socket, 'The relay is full.');
        return;
      }
      code = fresh;
      _rooms[code] = <WebSocket>{};
    } else {
      final room = _rooms[asked];
      if (room == null) {
        // Said rather than closed silently: a code typed in wrong is the
        // normal failure here, and the phone has to be able to say so.
        await _refuse(socket, 'No screen is waiting for that code.');
        return;
      }
      if (room.length >= maxPerRoom) {
        await _refuse(socket, 'That screen has enough devices on it.');
        return;
      }
      code = asked;
    }

    final room = _rooms[code]!;
    room.add(socket);
    _tell(socket, {'t': 'room', 'code': code, 'peers': room.length});
    // Everyone but the one that just arrived - it has the count in its own
    // welcome, and a device hearing about its own arrival would be noise.
    _announce(code, except: socket);

    socket.listen(
      (dynamic data) {
        if (data is! String || data.length > maxMessageBytes) return;
        for (final peer in room) {
          if (peer == socket) continue;
          _raw(peer, data);
        }
      },
      onDone: () => _drop(code, socket),
      onError: (Object _) => _drop(code, socket),
      cancelOnError: true,
    );
  }

  void _drop(String code, WebSocket socket) {
    final room = _rooms[code];
    if (room == null) return;
    room.remove(socket);
    if (room.isEmpty) {
      _rooms.remove(code);
      return;
    }
    _announce(code);
  }

  /// How many devices are on this screen now. The phone sends a full snapshot
  /// when it hears a new one, which is also what a reconnect looks like.
  void _announce(String code, {WebSocket? except}) {
    final room = _rooms[code];
    if (room == null) return;
    for (final socket in room) {
      if (socket == except) continue;
      _tell(socket, {'t': 'peers', 'count': room.length});
    }
  }

  Future<void> _refuse(WebSocket socket, String why) async {
    _tell(socket, {'t': 'refused', 'why': why});
    await socket.close(WebSocketStatus.normalClosure);
  }

  void _tell(WebSocket socket, Map<String, Object?> message) =>
      _raw(socket, jsonEncode(message));

  void _raw(WebSocket socket, String data) {
    try {
      socket.add(data);
    } on Object catch (error) {
      // A socket that died between the loop and here is not worth an
      // exception on the room it was in.
      stderr.writeln('send failed: $error');
    }
  }

  bool _looksLikeCode(String code) =>
      code.length == codeLength && code.split('').every(alphabet.contains);

  String? _freshCode() {
    if (_rooms.length >= maxRooms) return null;
    for (var attempt = 0; attempt < 50; attempt++) {
      final code = String.fromCharCodes([
        for (var i = 0; i < codeLength; i++)
          alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ]);
      if (!_rooms.containsKey(code)) return code;
    }
    return null;
  }
}
