// The saved game is read before the first frame. Whatever is in storage, a
// value that does not read as a game has to end as "no game" - a throw there is
// a page that never starts.
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/game_store.dart';
import 'package:anno/data/lyrics_scale_store.dart';
import 'package:anno/data/played_songs_store.dart';
import 'package:anno/data/skipped_songs_store.dart';
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
        categoryWeights: const {'esc': 3, 'hits': 1},
        played: const ['esc|a', 'hits|b'],
      ),
    );

    final game = await GameStore.load();

    expect(game!.players.single.name, 'Anna');
    expect(game.players.single.score, 3);
    expect(game.categoryIds, ['esc', 'hits']);
    expect(game.targetScore, 10);
    expect(game.played, ['esc|a', 'hits|b']);
    expect(game.categoryWeights, {'esc': 3, 'hits': 1});
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
    expect(game.categoryWeights, isEmpty);
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

  group('played songs', () {
    test('they survive a round trip', () async {
      await PlayedSongsStore.save({'esc|a', 'esc|b'});

      expect(await PlayedSongsStore.load(), {'esc|a', 'esc|b'});
    });

    test('the memory of the last 300 is carried over', () async {
      SharedPreferences.setMockInitialValues({
        'songs.recent': '["esc|a","esc|b"]',
      });
      expect(await PlayedSongsStore.load(), {'esc|a', 'esc|b'});
    });

    test('a broken value is an empty memory', () async {
      SharedPreferences.setMockInitialValues({'songs.recent': '{"a":1}'});
      expect(await PlayedSongsStore.load(), isEmpty);
    });
  });

  group('skipped songs', () {
    test('they survive a round trip', () async {
      await SkippedSongsStore.save({'a', 'b'});

      expect(await SkippedSongsStore.load(), {'a', 'b'});
    });

    test('a broken value is an empty memory', () async {
      SharedPreferences.setMockInitialValues({'songs.skipped': '{"a":1}'});
      expect(await SkippedSongsStore.load(), isEmpty);
    });
  });

  group('lyrics scale', () {
    test('it survives a round trip', () async {
      await LyricsScaleStore.save(1.44);

      expect(await LyricsScaleStore.load(), closeTo(1.44, 0.001));
    });

    test('a press does the same work at either end', () {
      const normal = LyricsScaleStore.normal;

      expect(
        LyricsScaleStore.stepped(normal, bigger: true),
        closeTo(1.2, 0.001),
      );
      expect(
        LyricsScaleStore.stepped(normal, bigger: false),
        closeTo(1 / 1.2, 0.001),
      );
    });

    test('the range holds, pressed and saved', () async {
      var scale = LyricsScaleStore.normal;
      for (var i = 0; i < 20; i++) {
        scale = LyricsScaleStore.stepped(scale, bigger: true);
      }
      expect(scale, LyricsScaleStore.max);

      for (var i = 0; i < 20; i++) {
        scale = LyricsScaleStore.stepped(scale, bigger: false);
      }
      expect(scale, LyricsScaleStore.min);

      // A value from an older build, or one edited by hand.
      SharedPreferences.setMockInitialValues({'lyrics.scale': 9.0});
      expect(await LyricsScaleStore.load(), LyricsScaleStore.max);
    });

    test('a broken value is the stage\'s own size', () async {
      SharedPreferences.setMockInitialValues({'lyrics.scale': 'big'});
      expect(await LyricsScaleStore.load(), LyricsScaleStore.normal);
    });
  });
}
