// The in-app player is optional everywhere: not the web, no client id, no
// Premium, not logged in. Each of those has to end up handing the song to
// Spotify by link instead of leaving the round without music.
import 'package:flutter_test/flutter_test.dart';
import 'package:play/models/song.dart';
import 'package:play/music/in_app_launcher.dart';
import 'package:play/music/spotify_launcher.dart';
import 'package:play/music/spotify_session.dart';

class FakeSession extends NoSpotifySession {
  FakeSession({this.state = SpotifyConnection.ready, this.plays = true});

  final SpotifyConnection state;
  final bool plays;
  final List<Song> played = [];

  @override
  SpotifyConnection get connection => state;

  @override
  Future<bool> play(Song song) async {
    played.add(song);
    return plays;
  }
}

class FakeFallback implements SpotifyLauncher {
  final List<Song> opened = [];

  @override
  Future<SpotifyLaunchResult> open(Song song) async {
    opened.add(song);
    return const SpotifyLaunchResult.ok();
  }
}

const song = Song(
  title: 'My Number One',
  artist: 'Helena Paparizou',
  year: 2005,
  spotifyTrackId: '3gSnnBf9fulK2fizqxmsXn',
);

void main() {
  test('a ready session plays the song itself', () async {
    final session = FakeSession();
    final fallback = FakeFallback();

    final result = await InAppSpotifyLauncher(
      session,
      fallback: fallback,
    ).open(song);

    expect(result.opened, isTrue);
    expect(session.played, [song]);
    expect(fallback.opened, isEmpty);
  });

  test('without a session the song goes to Spotify by link', () async {
    final session = FakeSession(state: SpotifyConnection.unavailable);
    final fallback = FakeFallback();

    await InAppSpotifyLauncher(session, fallback: fallback).open(song);

    expect(session.played, isEmpty);
    expect(fallback.opened, [song]);
  });

  test('a session that is not ready yet is skipped', () async {
    for (final state in [
      SpotifyConnection.disconnected,
      SpotifyConnection.connecting,
      SpotifyConnection.failed,
    ]) {
      final session = FakeSession(state: state);
      final fallback = FakeFallback();

      await InAppSpotifyLauncher(session, fallback: fallback).open(song);

      expect(session.played, isEmpty, reason: '$state');
      expect(fallback.opened, [song], reason: '$state');
    }
  });

  test('a song the player refuses still reaches Spotify', () async {
    final session = FakeSession(plays: false);
    final fallback = FakeFallback();

    final result = await InAppSpotifyLauncher(
      session,
      fallback: fallback,
    ).open(song);

    expect(result.opened, isTrue);
    expect(session.played, [song], reason: 'it was tried here first');
    expect(fallback.opened, [song]);
  });
}
