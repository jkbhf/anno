import 'package:flutter/material.dart';

import '../models/player.dart';
import '../models/song_category.dart';
import 'app_scope.dart';
import 'centered_body.dart';
import 'game_screen.dart';

/// Second screen: which decks the game is played from.
///
/// More than one is allowed - each round then draws from a category picked at
/// random among those that have a song for the scanned year.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    required this.players,
    required this.targetScore,
    this.played = const [],
    this.initialSelection = const {},
    super.key,
  });

  final List<GamePlayer> players;
  final int targetScore;

  /// What the game so far has played, when the categories are changed in the
  /// middle of one - the new choice should not start those songs over.
  final List<String> played;

  /// The category ids ticked when the screen opens.
  final Set<String> initialSelection;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late final Set<String> _selected = {...widget.initialSelection};

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

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: CenteredBody(
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
                              'one of them at random.'
                        : 'Pick what you want to play.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CategoryCard(
                        category: category,
                        selected: _selected.contains(category.id),
                        onTap: category.isEmpty
                            ? null
                            : () => _toggle(category),
                      ),
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    this.onTap,
  });

  final SongCategory category;
  final bool selected;
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
