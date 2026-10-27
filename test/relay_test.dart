import 'dart:convert';
import 'dart:io';

import 'package:anno_relay/anno_relay.dart';
import 'package:flutter_test/flutter_test.dart';

/// One device on the relay, keeping what it was sent so a test can wait for
/// the next message of a kind instead of guessing at a delay.
class _Device {
  _Device(this.socket) {
    socket.listen(
      (dynamic data) =>
          seen.add(jsonDecode(data as String) as Map<String, dynamic>),
    );
  }

  final WebSocket socket;
  final List<Map<String, dynamic>> seen = [];

  /// The next message of this kind, with everything before it thrown away -
  /// a "peers" count arriving in between is not what a test is waiting for.
  Future<Map<String, dynamic>> nextOf(String kind) async {
    for (var waited = 0; waited < 400; waited++) {
      final index = seen.indexWhere((message) => message['t'] == kind);
      if (index >= 0) {
        final message = seen[index];
        seen.removeRange(0, index + 1);
        return message;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('no "$kind" arrived, only $seen');
  }

  void send(Object message) => socket.add(jsonEncode(message));

  Future<void> close() => socket.close();
}

void main() {
  late RelayServer relay;
  late int port;

  setUp(() async {
    relay = RelayServer();
    await relay.start(port: 0);
    port = relay.port!;
  });

  tearDown(() async => relay.stop());

  Future<_Device> connect([String? code, int? onPort, bool host = false]) async {
    final query = code == null ? '' : '?room=$code${host ? '&host=1' : ''}';
    return _Device(
      await WebSocket.connect('ws://127.0.0.1:${onPort ?? port}/$query'),
    );
  }

  Future<(_Device, String)> openRoom() async {
    final screen = await connect();
    final hello = await screen.nextOf('room');
    return (screen, hello['code'] as String);
  }

  test('the screen gets a code, the phone joins it', () async {
    final (screen, code) = await openRoom();
    addTearDown(screen.close);
    expect(code, hasLength(6));
    expect(
      code.split('').every(RelayServer.alphabet.contains),
      isTrue,
      reason: 'no letters that read as each other across a room',
    );

    final phone = await connect(code);
    addTearDown(phone.close);
    expect((await phone.nextOf('room'))['code'], code);
    expect((await screen.nextOf('peers'))['count'], 2);
  });

  test('a snapshot goes to the screen and never back to the sender', () async {
    final (screen, code) = await openRoom();
    addTearDown(screen.close);
    final phone = await connect(code);
    addTearDown(phone.close);
    await screen.nextOf('peers');

    phone.send({'t': 'state', 'year': 1974});
    expect((await screen.nextOf('state'))['year'], 1974);

    // The sender hearing its own messages back would be the game applying
    // its own snapshot.
    phone.seen.clear();
    phone.send({'t': 'state', 'year': 1975});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(phone.seen, isEmpty);
  });

  test('a code nobody is waiting for is refused in words', () async {
    final stranger = await connect('ZZZZZZ');
    final answer = await stranger.nextOf('refused');
    expect(answer['why'], contains('No screen'));
  });

  test('a room dies with its last device', () async {
    final (screen, code) = await openRoom();
    expect(relay.roomCount, 1);
    await screen.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(relay.roomCount, 0);

    // And the code is gone with it, rather than letting somebody else's
    // phone walk into last week's evening.
    final late = await connect(code);
    addTearDown(late.close);
    await late.nextOf('refused');
  });

  test('the phone hears when the screen comes back', () async {
    final (screen, code) = await openRoom();
    final phone = await connect(code);
    addTearDown(phone.close);
    await phone.nextOf('room');

    await screen.close();
    expect((await phone.nextOf('peers'))['count'], 1);

    final again = await connect(code);
    addTearDown(again.close);
    await again.nextOf('room');
    expect((await phone.nextOf('peers'))['count'], 2);
  });

  test('the screen comes back to the code it had', () async {
    final (screen, code) = await openRoom();
    final phone = await connect(code);
    addTearDown(phone.close);
    await phone.nextOf('room');

    // A dropped socket must not cost the code: the phone is holding it.
    await screen.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final again = await connect(code, null, true);
    addTearDown(again.close);
    expect((await again.nextOf('room'))['code'], code);
    phone.send({'t': 'state', 'year': 1974});
    expect((await again.nextOf('state'))['year'], 1974);
  });

  test('a code made up by a joiner is not a room', () async {
    final stranger = await connect('ABCDEF');
    addTearDown(stranger.close);
    await stranger.nextOf('refused');
  });

  test('a full screen takes no more devices', () async {
    final small = RelayServer(maxPerRoom: 1);
    await small.start(port: 0);
    addTearDown(small.stop);

    final screen = await connect(null, small.port);
    addTearDown(screen.close);
    final code = (await screen.nextOf('room'))['code'] as String;

    final second = await connect(code, small.port);
    addTearDown(second.close);
    await second.nextOf('refused');
  });

  test('a full relay hands out no more codes', () async {
    final small = RelayServer(maxRooms: 1);
    await small.start(port: 0);
    addTearDown(small.stop);

    final first = await connect(null, small.port);
    addTearDown(first.close);
    await first.nextOf('room');

    final second = await connect(null, small.port);
    addTearDown(second.close);
    expect((await second.nextOf('refused'))['why'], contains('full'));
  });

  test('a plain request is answered, so it can be health checked', () async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.get('127.0.0.1', port, '/');
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(), contains('anno'));
  });
}
