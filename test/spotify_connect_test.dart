import 'dart:convert';

import 'package:anno/data/playback_device_store.dart';
import 'package:anno/models/song.dart';
import 'package:anno/music/spotify_auth.dart';
import 'package:anno/music/spotify_connect.dart';
import 'package:anno/music/spotify_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // The picked device lives in a static store, so every test starts from
  // nobody having picked one.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlaybackDeviceStore.preload();
  });

  group('pickConnectDevice', () {
    // The phone is what this session exists for, and the account's other
    // devices are a television and a speaker standing around: the round has to
    // come out of the thing the room is holding.
    test('the phone wins, even over a device that is playing', () {
      final picked = pickConnectDevice([
        _device('speaker', type: 'Speaker', active: true),
        _device('phone', type: 'Smartphone'),
      ]);
      expect(picked?.id, 'phone');
    });

    test('what is playing wins where no phone is listed', () {
      final picked = pickConnectDevice([
        _device('laptop'),
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

    test(
      'nothing usable is null, which is what sends the round to the link',
      () {
        expect(pickConnectDevice(const []), isNull);
        expect(
          pickConnectDevice([_device('car', restricted: true), _device('')]),
          isNull,
        );
      },
    );
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
      expect(jsonDecode((play as http.Request).body), {
        'uris': ['spotify:track:abc123'],
      });
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

    test(
      'the poll brings the length, and with it something to seek in',
      () async {
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
      },
    );

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

    test('with a device it says which one', () async {
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient(
          (request) async =>
              http.Response(_devicesBody([_deviceJson('dev1')]), 200),
        ),
      );
      addTearDown(session.dispose);

      await session.restore();
      // Which device the round comes out of is the one thing nobody can work
      // out from the game screen when it turns out to be the wrong one.
      expect(session.hint, 'The song plays on Phone.');
    });

    test('a device picked by hand takes the round', () async {
      final plays = <String?>[];
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(
              _devicesBody([
                _deviceJson('phone'),
                _deviceJson('tv', type: 'TV'),
              ]),
              200,
            );
          }
          if (request.url.path.endsWith('/play')) {
            plays.add(request.url.queryParameters['device_id']);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.restore();
      expect(session.devices.map((device) => device.id), ['phone', 'tv']);
      // Without a pick the phone takes it, see `pickConnectDevice`.
      await session.play(_song);
      expect(plays, ['phone']);

      await session.pickDevice('tv');
      expect(session.pickedDeviceId, 'tv');
      expect(PlaybackDeviceStore.id, 'tv');

      // And it survives the look-up the next round starts with.
      await session.releasePlayback();
      await session.play(_song);
      expect(plays.last, 'tv');

      // Handing the choice back goes to the phone again.
      await session.pickDevice(null);
      expect(PlaybackDeviceStore.id, isNull);
      await session.releasePlayback();
      await session.play(_song);
      expect(plays.last, 'phone');
    });

    test('a pick mid-song moves the song over', () async {
      final transfers = <String>[];
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(
              _devicesBody([
                _deviceJson('phone'),
                _deviceJson('tv', type: 'TV'),
              ]),
              200,
            );
          }
          if (request.url.path == '/v1/me/player') {
            transfers.add(request.body);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.restore();
      await session.play(_song);
      await session.pickDevice('tv');

      // The room is in the middle of a round: Spotify's transfer keeps the
      // position, where a fresh play would start the song again.
      expect(transfers, [
        jsonEncode({
          'device_ids': ['tv'],
          'play': true,
        }),
      ]);
      expect(session.isPlaying, isTrue);
    });

    test(
      'a pick survives the poll catching up slower than the transfer',
      () async {
        // Spotify's own report of "who is playing" still says the old
        // speaker for a moment after the transfer - moving to a phone in
        // particular can take longer to take hold than an always-on speaker
        // does. A poll landing in that window must not bounce the pick back.
        final session = ConnectSpotifySession(
          auth: _FakeAuth(),
          poll: const Duration(milliseconds: 5),
          followGrace: const Duration(milliseconds: 40),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/devices')) {
              return http.Response(
                _devicesBody([
                  {
                    'id': 'speaker',
                    'name': 'Speaker',
                    'type': 'Speaker',
                    'is_active': true,
                    'is_restricted': false,
                  },
                  {
                    'id': 'phone',
                    'name': 'Phone',
                    'type': 'Smartphone',
                    'is_active': false,
                    'is_restricted': false,
                  },
                ]),
                200,
              );
            }
            if (request.method == 'GET') {
              return http.Response(
                jsonEncode({
                  'is_playing': true,
                  'progress_ms': 0,
                  'item': {'duration_ms': 10000},
                  'device': {'id': 'speaker', 'name': 'Speaker'},
                }),
                200,
              );
            }
            return http.Response('', 204);
          }),
        );
        addTearDown(session.dispose);

        await session.restore();
        await session.play(_song);
        // Past play()'s own one-off delay before its first poll, so what is
        // left to measure is the grace window and not that start-up wait.
        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(session.deviceName, 'Speaker');

        await session.pickDevice('phone');
        expect(session.deviceName, 'Phone');

        // A poll or two still reporting the old speaker, inside the grace
        // window, must not undo the pick.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(session.deviceName, 'Phone');

        // Past the grace window the old speaker is still reported, which by
        // then really does mean the room moved it back by hand - so it is
        // followed.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(session.deviceName, 'Speaker');
      },
    );

    test('the end of the game lets the device go', () async {
      final calls = <String>[];
      final session = ConnectSpotifySession(
        auth: _FakeAuth(),
        poll: const Duration(milliseconds: 5),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/devices')) {
            return http.Response(_devicesBody([_deviceJson('dev1')]), 200);
          }
          if (request.method == 'PUT') calls.add(request.url.path);
          return http.Response('', 204);
        }),
      );
      addTearDown(session.dispose);

      await session.play(_song);
      expect(session.deviceName, 'Phone');

      await session.releasePlayback();
      // The speaker is paused and not held any more: the next game looks a
      // device up again instead of playing to one nobody is sitting at.
      expect(calls.last, '/v1/me/player/pause');
      expect(session.isPlaying, isFalse);
      expect(session.deviceName, isNull);
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
