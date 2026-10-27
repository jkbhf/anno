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

/// A deck over several years, for the range of a game without cards.
final span = SongCategory(
  id: 'hits',
  name: 'Hits',
  description: '',
  songs: [
    for (final year in [1990, 1991, 1992, 1993])
      Song(year: year, title: 'Song $year', artist: 'B'),
  ],
);
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

  testWidgets('without cards the range opens on the deck\'s span', (
    tester,
  ) async {
    await tester.pumpWidget(wrap([span, short]));

    // Not asked for until a deck is picked, because the range it offers is
    // that deck's.
    expect(find.text('Play without cards'), findsNothing);

    await tester.tap(find.text('Hits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play without cards'));
    await tester.pumpAndSettle();

    // The span of the chosen deck, and what that means for the evening.
    expect(find.text('1990'), findsOneWidget);
    expect(find.text('1993'), findsOneWidget);
    expect(
      find.text('4 years, each one once before any comes again'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Start without cards'),
      findsOneWidget,
    );

    // A deck of one year ticked on top widens the span to hold both.
    await tester.tap(find.text('K-Pop'));
    await tester.pumpAndSettle();
    expect(find.text('2016'), findsWidgets);
    // 1990 to 2016 with songs in five of those years.
    expect(
      find.text('5 years, each one once before any comes again'),
      findsOneWidget,
    );
  });

  testWidgets('with nothing picked Start is off', (tester) async {
    await tester.pumpWidget(wrap([full, short]));

    expect(startEnabled(tester), isFalse);
  });

  testWidgets('with two decks picked each shows its weight and share', (
    tester,
  ) async {
    await tester.pumpWidget(wrap([full, short]));

    await tester.tap(find.text('ESC'));
    await tester.pump();
    // One deck alone is all of the rounds - nothing to weigh.
    expect(find.text('100 %'), findsNothing);

    await tester.tap(find.text('K-Pop'));
    await tester.pump();
    expect(find.text('50 %'), findsNWidgets(2));

    await tester.tap(find.byTooltip('More often').first);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget);
    expect(find.text('33 %'), findsOneWidget);
  });

  testWidgets('sideways the deck cards stand in two columns', (tester) async {
    // A tablet on its side: the list is the same, the shape is not.
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([full, short]));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('ESC'));
    final second = tester.getTopLeft(find.text('K-Pop'));
    // Read across: the second card is beside the first, not under it.
    expect(second.dx, greaterThan(first.dx));
    expect(second.dy, first.dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upright they stay one under the other', (tester) async {
    tester.view.physicalSize = const Size(412, 893);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([full, short]));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('ESC'));
    final second = tester.getTopLeft(find.text('K-Pop'));
    expect(second.dx, first.dx);
    expect(second.dy, greaterThan(first.dy));
  });
}
