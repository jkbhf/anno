// The saved game is read before the first frame. Whatever is in storage, a
// value that does not read as a game has to end as "no game" - a throw there is
// a page that never starts.
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/game_store.dart';
import 'package:anno/data/recent_songs_store.dart';
import 'package:anno/models/player.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a game survives a round trip, played songs included', () async {
    await GameStore.save(
      SavedGame(
        players: [GamePlayer(name: 'Anna', score: 3)],
        categoryIds: const ['esc', 'hits'],
        targetScore: 10,
        played: const ['esc|a', 'hits|b'],
      ),
    );

    final game = await GameStore.load();

    expect(game!.players.single.name, 'Anna');
    expect(game.players.single.score, 3);
    expect(game.categoryIds, ['esc', 'hits']);
    expect(game.targetScore, 10);
    expect(game.played, ['esc|a', 'hits|b']);
  });

  test('a game saved before played songs were kept still loads', () async {
    SharedPreferences.setMockInitialValues({
      'game.current':
          '{"players":[{"name":"Anna","score":1}],"categoryId":"esc",'
          '"targetScore":5}',
    });

    final game = await GameStore.load();

    expect(game!.categoryIds, ['esc']);
    expect(game.played, isEmpty);
  });

  test('a value of the wrong shape is no game, not a crash', () async {
    for (final broken in [
      'not json',
      '[]',
      '{"players":[{"name":"Anna","score":1}],"categoryIds":["esc"],'
          '"targetScore":"10"}',
      '{"players":[{"name":"Anna","score":1}],"targetScore":10}',
      '{"players":{"a":1},"categoryIds":["esc"],"targetScore":10}',
      '{"players":[{"name":7,"score":1}],"categoryIds":["esc"],'
          '"targetScore":10}',
    ]) {
      SharedPreferences.setMockInitialValues({'game.current': broken});
      expect(await GameStore.load(), isNull, reason: broken);
    }
  });

  group('recent songs', () {
    test('a song played again moves to the end instead of twice', () {
      expect(RecentSongsStore.remember(['a', 'b', 'c'], 'a'), ['b', 'c', 'a']);
    });

    test('the oldest fall out beyond the capacity', () {
      final full = [for (var i = 0; i < RecentSongsStore.capacity; i++) '$i'];

      final next = RecentSongsStore.remember(full, 'new');

      expect(next, hasLength(RecentSongsStore.capacity));
      expect(next.first, '1');
      expect(next.last, 'new');
    });

    test('they survive a round trip', () async {
      await RecentSongsStore.add('esc|a');
      await RecentSongsStore.add('esc|b');

      expect(await RecentSongsStore.load(), ['esc|a', 'esc|b']);
    });

    test('a broken value is an empty memory', () async {
      SharedPreferences.setMockInitialValues({'songs.recent': '{"a":1}'});
      expect(await RecentSongsStore.load(), isEmpty);
    });
  });
}
