import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../music/lyrics.dart';
import '../music/spotify_playback.dart';

/// Opens the text of [song] over the round.
///
/// [session] is the player in this tab, passed only where the round plays in
/// it: then a synced text follows the song, and a tap on a line jumps there.
/// For a song handed over by link the sheet is the words and nothing more.
///
/// [hideSong] keeps title and artist off the sheet while the room is still
/// guessing - the words are the hint the room asked for, the name would be the
/// answer.
Future<void> showLyricsSheet(
  BuildContext context, {
  required Song song,
  required LyricsSource source,
  SpotifySession? session,
  bool hideSong = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.85,
      child: LyricsSheet(
        song: song,
        source: source,
        session: session,
        hideSong: hideSong,
      ),
    ),
  );
}

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({
    required this.song,
    required this.source,
    this.session,
    this.hideSong = false,
    super.key,
  });

  final Song song;
  final LyricsSource source;
  final SpotifySession? session;
  final bool hideSong;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  late Future<Lyrics?> _lyrics = _load();

  Future<Lyrics?> _load() =>
      widget.source.find(widget.song, duration: widget.session?.duration);

  /// The player reports on changes only; between two reports the line moves on
  /// the clock - the same tick as the seek bar.
  Timer? _ticker;

  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _lineKeys = [];
  int _current = -1;

  @override
  void initState() {
    super.initState();
    if (widget.session != null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _follow(),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Lyrics? _loaded;

  void _follow() {
    final lyrics = _loaded;
    final session = widget.session;
    if (!mounted || lyrics == null || session == null || !lyrics.isSynced) {
      return;
    }
    final line = lyrics.lineAt(session.position);
    if (line == _current) return;
    setState(() => _current = line);
    if (line < 0 || line >= _lineKeys.length) return;
    final target = _lineKeys[line].currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        alignment: 0.35,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            widget.hideSong ? 'Lyrics' : '${song.title} · ${song.artist}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: FutureBuilder<Lyrics?>(
            future: _lyrics,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _failed(context);
              }
              final lyrics = snapshot.data;
              if (lyrics == null || lyrics.lines.isEmpty) {
                return _message(
                  context,
                  lyrics?.instrumental ?? false
                      ? 'This one has no words.'
                      : 'No lyrics found for this song.',
                );
              }
              _loaded = lyrics;
              return _lines(context, lyrics);
            },
          ),
        ),
      ],
    );
  }

  Widget _message(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// The source did not answer - not the same as a song without words, so
  /// the sheet says so and asks again on a tap instead of on a reopen.
  Widget _failed(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The lyrics could not be loaded.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => setState(() {
              _lyrics = _load();
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _lines(BuildContext context, Lyrics lyrics) {
    final theme = Theme.of(context);
    final session = widget.session;
    final follows = session != null && lyrics.isSynced;
    while (_lineKeys.length < lyrics.lines.length) {
      _lineKeys.add(GlobalKey());
    }

    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lyrics.lines.length; i++)
            _line(
              context,
              lyrics.lines[i],
              key: _lineKeys[i],
              state: !follows
                  ? _LineState.plain
                  : i == _current
                  ? _LineState.current
                  : i < _current
                  ? _LineState.past
                  : _LineState.coming,
              onTap: follows ? () => session.seek(lyrics.lines[i].time!) : null,
            ),
          if (!follows && session != null) ...[
            const SizedBox(height: 16),
            Text(
              'No timed text for this recording - the words do not follow '
              'the song.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    LyricsLine line, {
    required Key key,
    required _LineState state,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final base = theme.textTheme.titleLarge!;
    final style = switch (state) {
      _LineState.current => base.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
      _LineState.past => base.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      _LineState.coming => base.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      _LineState.plain => base,
    };

    // An empty line in a text is a break between verses.
    if (line.text.isEmpty) return SizedBox(key: key, height: 20);

    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: style,
          child: Text(line.text, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

enum _LineState { plain, current, past, coming }
