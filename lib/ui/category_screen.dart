import 'package:flutter/material.dart';

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

  /// The range of the weight a card can be set to.
  static const int minWeight = 1;
  static const int maxWeight = 10;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late final Set<String> _selected = {...widget.initialSelection};
  late final Map<String, int> _weights = {...widget.initialWeights};

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

  Future<void> _start(List<SongCategory> categories) async {
    final chosen = _chosen(categories);
    if (!canCarryGame(chosen)) return;

    await openGame(
      context,
      categories: chosen,
      players: widget.players,
      targetScore: widget.targetScore,
      weights: {
        for (final category in chosen) category.id: _weightOf(category),
      },
      played: widget.played,
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
                      _selected.length <= 1
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
