import 'dart:convert';

import 'package:anno/models/song.dart';
import 'package:anno/music/spotify_auth.dart';
import 'package:anno/music/spotify_connect.dart';
import 'package:anno/music/spotify_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A login that is simply there. The real one is PKCE in a browser; nothing
/// about the player depends on how the token was got.
class _FakeAuth implements SpotifyAuth {
  _FakeAuth({this.token = 'token'});

  final String? token;
  int logins = 0;

  @override
  bool get hasLogin => true;

  @override
  bool get hasPendingRedirect => false;

  @override
  Future<LoginResult> restore() async => const LoginResult.loggedIn();

  @override
  Future<LoginResult> resume() async => const LoginResult.loggedIn();

  @override
  Future<void> beginLogin() async => logins++;

  @override
  Future<void> forget() async {}

  @override
  Future<String?> freshToken() async => token;
}

const _song = Song(
  title: 'Waterloo',
  artist: 'ABBA',
  year: 1974,
  spotifyTrackId: 'abc123',
);

ConnectDevice _device(
  String id, {
  String type = 'Computer',
  bool active = false,
  bool restricted = false,
}) => ConnectDevice(
  id: id,
  name: id,
  type: type,
  isActive: active,
  isRestricted: restricted,
);

String _devicesBody(List<Map<String, Object?>> devices) =>
    jsonEncode({'devices': devices});

Map<String, Object?> _deviceJson(
  String id, {
  String type = 'Smartphone',
  bool active = false,
  bool restricted = false,
}) => {
  'id': id,
  'name': 'Phone',
  'type': type,
  'is_active': active,
  'is_restricted': restricted,
};

void main() {
  group('pickConnectDevice', () {
    test('the device that is already playing wins', () {
      final picked = pickConnectDevice([
        _device('phone', type: 'Smartphone'),
        _device('speaker', type: 'Speaker', active: true),
      ]);
      expect(picked?.id, 'speaker');
    });

    test('a phone beats a computer where none is active', () {
      final picked = pickConnectDevice([
        _device('laptop'),
        _device('phone', type: 'Smartphone'),
      ]);
      expect(picked?.id, 'phone');
    });

    test('a restricted device is never picked', () {
      final picked = pickConnectDevice([
        _device('car', type: 'Automobile', active: true, restricted: true),
        _device('laptop'),
      ]);
      expect(picked?.id, 'laptop');
    });

    test('nothing usable is null, which is what sends the round to the link', () {
      expect(pickConnectDevice(const []), isNull);
      expect(
        pickConnectDevice([_device('car', restricted: true), _device('')]),
        isNull,
      );
    });
  });

  group('play', () {
    test('starts the track on the device it found', () async {
      final calls = <http.BaseRequest>[];
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      expect(await session.play(_song), isTrue);
      expect(session.isPlaying, isTrue);

      final play = calls.last;
      expect(play.method, 'PUT');
      expect(play.url.path, '/v1/me/player/play');
      expect(play.url.queryParameters['device_id'], 'dev1');
      expect(
        jsonDecode((play as http.Request).body),
        {'uris': ['spotify:track:abc123']},
      );
    });

    test('no device at all does not play, and asks for no track', () async {
      var plays = 0;
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody(const []), 200);
          }
          plays++;
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      expect(await session.play(_song), isFalse);
      expect(session.isPlaying, isFalse);
      expect(plays, 0);
    });

    test('a device that has gone away is looked up once more', () async {
      var probes = 0;
      var attempts = 0;
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            probes++;
            return http.Response(
              _devicesBody([_deviceJson(probes == 1 ? 'gone' : 'fresh')]),
              200,
            );
          }
          attempts++;
          return http.Response('', attempts == 1 ? 404 : 204);
        }),
      );
      addTearDown(session.dispose);

      expect(await session.play(_song), isTrue);
      expect(probes, 2);
      expect(attempts, 2);
    });

    test('a refusal says why and still falls back', () async {
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          return http.Response('{"error":{"reason":"PREMIUM_REQUIRED"}}', 403);
        }),
      );
      addTearDown(session.dispose);

      expect(await session.play(_song), isFalse);
      expect(session.error, contains('Premium'));
    });

    test('a token that cannot be had plays nothing', () async {
      final session = ConnectSpotifySession(
        auth: _FakeAuth(token: null),
        client: MockClient((request) async => http.Response('', 204)),
      );
      addTearDown(session.dispose);

      expect(await session.play(_song), isFalse);
    });
  });

  group('the clock', () {
    test('runs on between two answers and stands still while paused', () async {
      var now = DateTime(2026, 10, 27, 20);
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        now: () => now,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.play(_song);
      expect(session.position, Duration.zero);

      now = now.add(const Duration(seconds: 4));
      expect(session.position, const Duration(seconds: 4));

      await session.togglePause();
      now = now.add(const Duration(seconds: 10));
      expect(session.isPlaying, isFalse);
      expect(session.position, const Duration(seconds: 4));

      await session.togglePause();
      now = now.add(const Duration(seconds: 2));
      expect(session.position, const Duration(seconds: 6));
    });

    test('the poll brings the length, and with it something to seek in', () async {
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        poll: const Duration(milliseconds: 5),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'is_playing': true,
                'progress_ms': 30000,
                'item': {'duration_ms': 150000},
                'device': {'id': 'dev1', 'name': 'Phone'},
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.play(_song);
      expect(session.duration, Duration.zero);

      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(session.duration, const Duration(milliseconds: 150000));
      expect(session.position.inSeconds, greaterThanOrEqualTo(30));
    });

    test('seek needs a length, and never leaves the song', () async {
      final seeks = <String?>[];
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        poll: const Duration(milliseconds: 5),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          if (request.url.path.endsWith('/seek')) {
            seeks.add(request.url.queryParameters['position_ms']);
          }
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'is_playing': true,
                'progress_ms': 0,
                'item': {'duration_ms': 10000},
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.play(_song);
      await session.seek(const Duration(seconds: 5));
      expect(seeks, isEmpty, reason: 'no length known yet');

      await Future<void>.delayed(const Duration(milliseconds: 800));
      await session.seek(const Duration(seconds: 99));
      expect(seeks, ['10000']);
    });
  });

  group('the session', () {
    test('a login that is there is ready, and says what is missing', () async {
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient(
          (request) async => http.Response(_devicesBody(const []), 200),
        ),
      );
      addTearDown(session.dispose);

      await session.restore();
      expect(session.connection, SpotifyConnection.ready);
      expect(session.hint, contains('Open Spotify'));
    });

    test('with a device there is nothing to say', () async {
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient(
          (request) async =>
              http.Response(_devicesBody([_deviceJson('dev1')]), 200),
        ),
      );
      addTearDown(session.dispose);

      await session.restore();
      expect(session.hint, isNull);
    });

    test('stop pauses and ends the poll', () async {
      var gets = 0;
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        poll: const Duration(milliseconds: 5),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          if (request.method == 'GET') {
            gets++;
            return http.Response(
              jsonEncode({'is_playing': true, 'progress_ms': 1}),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.play(_song);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(gets, greaterThan(0));

      await session.stop();
      final after = gets;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(gets, after);
      expect(session.isPlaying, isFalse);
    });
  });
}
