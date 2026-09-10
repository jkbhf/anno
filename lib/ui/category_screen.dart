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
///
/// A deck with [SongCategory.needsCompanion] can be picked freely but not on
/// its own: it only covers part of the century, so alone it would answer most
/// cards with nothing. [canCarryGame] is the check, and the button says why it
/// is off rather than just going grey.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    required this.players,
    required this.targetScore,
    super.key,
  });

  final List<GamePlayer> players;
  final int targetScore;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final Set<String> _selected = <String>{};

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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = AppScope.of(context).categories;
    final playable = categories.where((c) => !c.isEmpty).length;
    final chosen = _chosen(categories);
    final ready = canCarryGame(chosen);
    // Picked something, but all of it needs a companion - the one case where
    // the disabled button needs a sentence to go with it.
    final companionOnly = chosen.isNotEmpty && !ready;

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
                  if (companionOnly) ...[
                    Text(
                      chosen.length == 1
                          ? '${chosen.single.name} only covers part of the '
                                'years - pick another deck to go with it.'
                          : 'These decks only cover part of the years - pick '
                                'another one to go with them.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
        : '${category.songs.length} songs · ${category.yearSpan}'
              '${category.needsCompanion ? ' · only with another deck' : ''}';

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
