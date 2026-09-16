// A deck that covers only part of the century - K-Pop from 2016 on - is a
// game of its own like any other: its span stands on the card, and a card
// outside it only brings up a note. The rule lives in `canCarryGame`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/category_screen.dart';
import 'package:anno/ui/theme.dart';

SongCategory deck(String id, String name) => SongCategory(
  id: id,
  name: name,
  description: '',
  songs: [Song(year: 2016, title: 'A', artist: 'B')],
);

final full = deck('esc', 'ESC');
final short = deck('kpop', 'K-Pop');
final empty = SongCategory(
  id: 'rock_pop',
  name: 'Rock & Pop',
  description: '',
  songs: const [],
);

Widget wrap(List<SongCategory> categories) => AppScope(
  years: YearDatabase.inMemory(),
  categories: categories,
  spotify: NoSpotifySession(),
  service: ValueNotifier(MusicService.spotify),
  child: MaterialApp(
    theme: buildTheme(),
    home: CategoryScreen(players: [GamePlayer(name: 'Jakob')], targetScore: 10),
  ),
);

bool startEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start'))
        .onPressed !=
    null;

void main() {
  group('canCarryGame', () {
    test('any deck with songs carries a game, on its own too', () {
      expect(canCarryGame([full]), isTrue);
      expect(canCarryGame([short]), isTrue);
      expect(canCarryGame([full, short]), isTrue);
    });

    test('nothing selected does not', () {
      expect(canCarryGame(const <SongCategory>[]), isFalse);
    });

    test('an empty deck does not', () {
      expect(canCarryGame([empty]), isFalse);
      expect(canCarryGame([empty, short]), isTrue);
    });
  });

  testWidgets('a short deck starts on its own', (tester) async {
    await tester.pumpWidget(wrap([full, short]));

    await tester.tap(find.text('K-Pop'));
    await tester.pump();

    expect(startEnabled(tester), isTrue);
  });

  testWidgets('the card shows the years the deck covers', (tester) async {
    await tester.pumpWidget(wrap([full, short]));

    expect(find.text('1 songs · 2016'), findsNWidgets(2));
    expect(find.textContaining('another deck'), findsNothing);
  });

  testWidgets('with nothing picked Start is off', (tester) async {
    await tester.pumpWidget(wrap([full, short]));

    expect(startEnabled(tester), isFalse);
  });
}
