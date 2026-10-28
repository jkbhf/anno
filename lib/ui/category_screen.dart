import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/csv_deck.dart';
import '../models/player.dart';
import '../models/song_category.dart';
import 'app_scope.dart';
import 'centered_body.dart';
import 'game_screen.dart';
import 'layout.dart';

/// Second screen: which decks the game is played from.
///
/// More than one is allowed - each round then draws from a category picked at
/// random among those that have a song for the scanned year, weighted by the
/// number on its card.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    required this.players,
    required this.targetScore,
    this.played = const [],
    this.initialSelection = const {},
    this.initialWeights = const {},
    this.initialFromYear,
    this.initialToYear,
    this.playedYears = const [],
    super.key,
  });

  final List<GamePlayer> players;
  final int targetScore;

  /// What the game so far has played, when the categories are changed in the
  /// middle of one - the new choice should not start those songs over.
  final List<String> played;

  /// The category ids ticked when the screen opens.
  final Set<String> initialSelection;

  /// The draw weights to open with, by category id. Missing ones start at 1.
  final Map<String, int> initialWeights;

  /// The year range of a game without cards, when the decks are changed in
  /// the middle of one: both null is a game played with the cards.
  final int? initialFromYear;
  final int? initialToYear;

  /// The years that game has drawn already, kept across the change the same
  /// way the played songs are.
  final List<int> playedYears;

  /// The range of the weight a card can be set to.
  static const int minWeight = 1;
  static const int maxWeight = 10;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late final Set<String> _selected = {...widget.initialSelection};
  late final Map<String, int> _weights = {...widget.initialWeights};

  /// Whether the game draws its own years instead of reading them off a card.
  late bool _withoutCards =
      widget.initialFromYear != null && widget.initialToYear != null;

  /// The range it draws from. Null follows the span of the chosen decks, which
  /// is what the switch starts on - a deck that only covers part of the
  /// century would otherwise be asked for years it has nothing for.
  late int? _from = widget.initialFromYear;
  late int? _to = widget.initialToYear;

  /// The ends of what the chosen decks hold together, null while nothing
  /// playable is chosen.
  (int, int)? _span(List<SongCategory> chosen) {
    final firsts = [for (final category in chosen) ?category.firstYear];
    final lasts = [for (final category in chosen) ?category.lastYear];
    if (firsts.isEmpty || lasts.isEmpty) return null;
    return (firsts.reduce(min), lasts.reduce(max));
  }

  /// The range as it stands, inside the span of the chosen decks: a deck
  /// unticked after the range was set must not leave it asking for years
  /// nobody has a song for.
  (int, int)? _range(List<SongCategory> chosen) {
    final span = _span(chosen);
    if (span == null) return null;
    final (first, last) = span;
    final from = (_from ?? first).clamp(first, last);
    final to = (_to ?? last).clamp(first, last);
    return from <= to ? (from, to) : (to, from);
  }

  /// How many years of the range some chosen deck can play. A year without a
  /// song is never drawn, so this is the length of the pass the room is in
  /// for, see `GameController.playableYears`.
  int _playableYears(List<SongCategory> chosen, (int, int) range) {
    final (from, to) = range;
    var count = 0;
    for (var year = from; year <= to; year++) {
      if (chosen.any((c) => c.songsForYear(year).isNotEmpty)) count++;
    }
    return count;
  }

  int _weightOf(SongCategory category) => (_weights[category.id] ?? 1).clamp(
    CategoryScreen.minWeight,
    CategoryScreen.maxWeight,
  );

  void _setWeight(SongCategory category, int weight) {
    setState(() => _weights[category.id] = weight);
  }

  /// The share of rounds [category] gets in a year every chosen deck holds
  /// ten songs for - a thinner year gives a deck less, one it lacks goes to
  /// the others.
  int _percentOf(SongCategory category, List<SongCategory> chosen) {
    final playable = chosen.where((c) => !c.isEmpty);
    final total = playable.fold<int>(0, (sum, c) => sum + _weightOf(c));
    if (total == 0) return 0;
    return (_weightOf(category) * 100 / total).round();
  }

  void _toggle(SongCategory category) {
    setState(() {
      if (!_selected.remove(category.id)) _selected.add(category.id);
    });
  }

  List<SongCategory> _chosen(List<SongCategory> categories) => [
    for (final category in categories)
      if (_selected.contains(category.id)) category,
  ];

  /// Reads a playlist export the player picks and keeps it as a deck of its
  /// own on this device. The rows are taken as they are.
  Future<void> _import() async {
    final scope = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      // No extension filter: a phone's picker matches `.csv` against the
      // MIME type the file was saved with, and an export downloaded on
      // Android or iOS is often stored as text/plain or octet-stream - it
      // then shows greyed out and cannot be picked at all. What is not an
      // export is refused by [CsvDeck.parse] with a message instead.
      final picked = await FilePicker.pickFiles(type: FileType.any);
      if (picked.isEmpty) return;
      final file = picked.first;
      final bytes = await file.readAsBytes();
      final deck = CsvDeck.parse(
        utf8.decode(bytes, allowMalformed: true),
        name: CsvDeck.nameOf(file.name),
      );
      await scope.onImport?.call(deck);
      message = '${deck.name}: ${deck.songs.length} songs imported';
    } on FormatException catch (error) {
      message = error.message;
    } on Object catch (error) {
      message = 'Import failed: $error';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start(List<SongCategory> categories) async {
    final chosen = _chosen(categories);
    if (!canCarryGame(chosen)) return;
    final range = _withoutCards ? _range(chosen) : null;

    await openGame(
      context,
      categories: chosen,
      players: widget.players,
      targetScore: widget.targetScore,
      weights: {
        for (final category in chosen) category.id: _weightOf(category),
      },
      played: widget.played,
      fromYear: range?.$1,
      toYear: range?.$2,
      playedYears: widget.playedYears,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = AppScope.of(context).categories;
    final playable = categories.where((c) => !c.isEmpty).length;
    final chosen = _chosen(categories);
    final ready = canCarryGame(chosen);

    // Sideways the deck cards stand in two columns: the list is long, and a
    // landscape screen has the width to show twice as much of it at once -
    // the same reason the game screen splits. The cap goes up with it, or the
    // two columns would be two narrow strips in the middle.
    final wide = isWideScreen(MediaQuery.sizeOf(context));

    final cards = [
      for (final category in categories)
        _CategoryCard(
          category: category,
          selected: _selected.contains(category.id),
          weight: _weightOf(category),
          percent: chosen.length > 1 ? _percentOf(category, chosen) : null,
          onWeight: (weight) => _setWeight(category, weight),
          onTap: category.isEmpty ? null : () => _toggle(category),
          onRemove: category.imported
              ? () {
                  setState(() => _selected.remove(category.id));
                  AppScope.of(context).onRemoveImported?.call(category.id);
                }
              : null,
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: CenteredBody(
        maxWidth: wide ? 1040 : 560,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  Text(
                    '${widget.players.length} '
                    '${widget.players.length == 1 ? 'player' : 'players'} '
                    '· to ${widget.targetScore} points',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    playable > 1
                        ? 'Pick one or several - every round then draws from '
                              'one of them at random. The number on a card '
                              'makes it come up more often.'
                        : 'Pick what you want to play.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (wide)
                    _TwoColumns(cards: cards)
                  else
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: card,
                      ),
                  if (AppScope.of(context).onImport != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import a playlist (.csv)'),
                      ),
                    ),
                  // Last, because it is a question about the decks above it:
                  // the range it opens on is their span.
                  if (_range(chosen) case final range?)
                    _WithoutCardsCard(
                      on: _withoutCards,
                      span: _span(chosen)!,
                      range: range,
                      playableYears: _playableYears(chosen, range),
                      onToggle: (on) => setState(() => _withoutCards = on),
                      onRange: (from, to) => setState(() {
                        _from = from;
                        _to = to;
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: ready ? () => _start(categories) : null,
                    child: Text(
                      _withoutCards
                          ? 'Start without cards'
                          : _selected.length <= 1
                          ? 'Start'
                          : 'Start with ${_selected.length} categories',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The game without the printed cards: the device draws the year itself.
///
/// For a car, a sofa, a flat the box is not in. The room still guesses a year
/// and still gets points for it; what goes is the camera, and with it the one
/// thing that cannot be improvised.
///
/// The range opens on the span of the chosen decks, because that is the widest
/// one that is never a dead round - K-Pop alone asked for 1950 would have
/// nothing to play. Inside it, years no deck has a song for are skipped rather
/// than drawn, so the count under the slider is what the room is in for.
class _WithoutCardsCard extends StatelessWidget {
  const _WithoutCardsCard({
    required this.on,
    required this.span,
    required this.range,
    required this.playableYears,
    required this.onToggle,
    required this.onRange,
  });

  final bool on;

  /// The ends of what the chosen decks hold, and the part of it in play.
  final (int, int) span;
  final (int, int) range;

  /// How many years of [range] can actually be drawn.
  final int playableYears;

  final ValueChanged<bool> onToggle;
  final void Function(int from, int to) onRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (spanFrom, spanTo) = span;
    final (from, to) = range;
    // A span of one year has nothing to drag.
    final draggable = spanTo > spanFrom;

    return Card(
      color: on ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: onToggle,
              title: const Text('Play without cards'),
              subtitle: Text(
                'The device draws the year, and a tap after the reveal '
                'draws the next one.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: on
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (on) ...[
              Row(
                children: [
                  Text('$from', style: theme.textTheme.titleMedium),
                  Expanded(
                    child: draggable
                        ? RangeSlider(
                            min: spanFrom.toDouble(),
                            max: spanTo.toDouble(),
                            divisions: spanTo - spanFrom,
                            labels: RangeLabels('$from', '$to'),
                            values: RangeValues(from.toDouble(), to.toDouble()),
                            onChanged: (values) => onRange(
                              values.start.round(),
                              values.end.round(),
                            ),
                          )
                        : const SizedBox(height: 48),
                  ),
                  Text('$to', style: theme.textTheme.titleMedium),
                ],
              ),
              Text(
                playableYears == 1
                    ? 'One year to play'
                    : '$playableYears years, each one once before any '
                          'comes again',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: on
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The deck cards in two columns, read across: first card top left, second
/// top right.
///
/// Two columns rather than a grid, because the cards are not the same height -
/// a selected one carries its weight row, an empty one a line saying so - and
/// a grid would cut them to the tallest in the row.
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final side in [0, 1]) ...[
          if (side == 1) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, card) in cards.indexed)
                  if (index % 2 == side)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: card,
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.weight,
    required this.onWeight,
    this.percent,
    this.onTap,
    this.onRemove,
  });

  final SongCategory category;
  final bool selected;

  /// The draw weight, shown and changeable only while the card is selected.
  final int weight;
  final ValueChanged<int> onWeight;

  /// The card's share of the rounds; null with only one deck chosen, where
  /// a share would always read 100 %.
  final int? percent;

  final VoidCallback? onTap;

  /// Set for an imported deck: takes it off the device again.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final subtitle = category.isEmpty
        ? 'No songs yet'
        : '${category.songs.length} songs · ${category.yearSpan}';

    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        category.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : enabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled && selected && percent != null)
                  _WeightStepper(
                    weight: weight,
                    percent: percent!,
                    onChanged: onWeight,
                  ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove this playlist',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                if (enabled)
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The draw weight of a selected card, with its share of the rounds.
class _WeightStepper extends StatelessWidget {
  const _WeightStepper({
    required this.weight,
    required this.percent,
    required this.onChanged,
  });

  final int weight;
  final int percent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Less often',
                visualDensity: VisualDensity.compact,
                color: color,
                onPressed: weight > CategoryScreen.minWeight
                    ? () => onChanged(weight - 1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  '$weight',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
              IconButton(
                tooltip: 'More often',
                visualDensity: VisualDensity.compact,
                color: color,
                onPressed: weight < CategoryScreen.maxWeight
                    ? () => onChanged(weight + 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text(
            '$percent %',
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
