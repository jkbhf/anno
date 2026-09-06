import 'dart:async';

import 'package:flutter/material.dart';

import '../data/game_store.dart';
import '../data/roster_store.dart';
import '../models/player.dart';
import '../models/song_category.dart';
import 'app_scope.dart';
import 'category_screen.dart';
import 'centered_body.dart';
import 'game_screen.dart';
import '../music/spotify_session.dart';
import 'spotify_card.dart';
import 'text_input_dialog.dart';
import 'year_database_screen.dart';

/// First screen: who is playing and up to how many points.
class SetupScreen extends StatefulWidget {
  const SetupScreen({this.savedGame, this.roster = const [], super.key});

  /// An interrupted game that can be resumed.
  final SavedGame? savedGame;

  /// The names of the last group, from [RosterStore].
  final List<String> roster;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const List<int> _presets = [5, 10, 15];

  late final List<TextEditingController> _names;

  int _target = 10;
  SavedGame? _savedGame;

  @override
  void initState() {
    super.initState();
    _savedGame = widget.savedGame;
    // Two empty rows are the starting point for a group that has never played
    // here; everyone else finds their names where they left them.
    _names = [
      for (final name in widget.roster) TextEditingController(text: name),
      if (widget.roster.isEmpty) ...[
        TextEditingController(),
        TextEditingController(),
      ],
    ];
  }

  @override
  void dispose() {
    for (final controller in _names) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Only the filled in fields become players - an empty row is a leftover,
  /// not a nameless player.
  List<String> get _playerNames => [
    for (final controller in _names)
      if (controller.text.trim().isNotEmpty) controller.text.trim(),
  ];

  bool get _canStart => _playerNames.isNotEmpty;

  void _addPlayer() {
    setState(() => _names.add(TextEditingController()));
  }

  void _removePlayer(int index) {
    final removed = _names.removeAt(index);
    setState(() {});
    // Disposing inside setState would kill the controller while the field
    // that still holds it is being rebuilt out of the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Future<void> _chooseCustomTarget() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Score target',
        confirmLabel: 'Apply',
        initialText: '$_target',
        suffixText: 'points',
        keyboardType: TextInputType.number,
        validator: (value) {
          final points = int.tryParse(value);
          return points == null || points < 1 ? 'At least 1 point' : null;
        },
      ),
    );
    final value = text == null ? null : int.tryParse(text);
    if (value != null && value > 0) {
      setState(() => _target = value);
    }
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'years':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const YearDatabaseScreen()),
        );
      case 'spotify':
        await AppScope.of(context).spotify.disconnect();
    }
  }

  void _start() {
    final names = _playerNames;
    // Saved on the way into a game, not on every keystroke: these are the
    // names the group settled on.
    unawaited(RosterStore.save(names));
    final players = [for (final name in names) GamePlayer(name: name)];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryScreen(players: players, targetScore: _target),
      ),
    );
  }

  Future<void> _resume(SavedGame game, List<SongCategory> categories) async {
    setState(() => _savedGame = null);
    await openGame(
      context,
      categories: categories,
      players: game.players,
      targetScore: game.targetScore,
    );
  }

  /// The saved categories that still exist. A deck removed from the assets
  /// simply drops out; only if none is left does the card disappear.
  static List<SongCategory> _resolve(
    List<SongCategory> categories,
    List<String> ids,
  ) => [
    for (final id in ids)
      for (final category in categories)
        if (category.id == id) category,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = _savedGame;
    final categories = AppScope.of(context).categories;
    final savedCategories = saved == null
        ? const <SongCategory>[]
        : _resolve(categories, saved.categoryIds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Play'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: _onMenu,
            // Built when the menu opens, so the Spotify entry is in step with
            // the connection without the app bar listening for it.
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'years', child: Text('Year database')),
              if (AppScope.of(context).spotify.connection ==
                  SpotifyConnection.ready)
                const PopupMenuItem(
                  value: 'spotify',
                  child: Text('Disconnect Spotify'),
                ),
            ],
          ),
        ],
      ),
      body: CenteredBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (saved != null && savedCategories.isNotEmpty) ...[
              _ResumeCard(
                game: saved,
                categories: savedCategories,
                onResume: () => _resume(saved, savedCategories),
                onDiscard: () async {
                  setState(() => _savedGame = null);
                  await GameStore.clear();
                },
              ),
              const SizedBox(height: 24),
            ],
            SpotifyCard(session: AppScope.of(context).spotify),
            Text("Who's playing?", style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'One device gets passed around.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final (index, controller) in _names.indexed)
              Padding(
                key: ObjectKey(controller),
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Player ${index + 1}',
                    prefixIcon: const Icon(Icons.person_outline),
                    suffixIcon: _names.length > 1
                        ? IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close),
                            onPressed: () => _removePlayer(index),
                          )
                        : null,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addPlayer,
                icon: const Icon(Icons.add),
                label: const Text('Add player'),
              ),
            ),
            const SizedBox(height: 24),
            Text('Play to', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in _presets)
                  ChoiceChip(
                    label: Text('$preset points'),
                    selected: _target == preset,
                    onSelected: (_) => setState(() => _target = preset),
                  ),
                ChoiceChip(
                  label: Text(
                    _presets.contains(_target) ? 'Other' : '$_target points',
                  ),
                  selected: !_presets.contains(_target),
                  onSelected: (_) => _chooseCustomTarget(),
                ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _canStart ? _start : null,
              child: const Text('Continue to categories'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.game,
    required this.categories,
    required this.onResume,
    required this.onDiscard,
  });

  final SavedGame game;
  final List<SongCategory> categories;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scores = game.players.map((p) => '${p.name} ${p.score}').join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Game in progress', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${categories.map((c) => c.name).join(', ')} '
              '· to ${game.targetScore} points',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(scores, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onResume,
                    child: const Text('Resume'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(onPressed: onDiscard, child: const Text('Discard')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
