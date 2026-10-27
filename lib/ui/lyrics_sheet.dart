import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../music/lyrics.dart';
import '../music/spotify_playback.dart';
import 'pinch_scale.dart';

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
  int syncMs = 0,
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
        syncMs: syncMs,
        hideSong: hideSong,
      ),
    ),
  );
}

/// The sheet: the words under a line that names the song once it is no
/// secret any more.
class LyricsSheet extends StatefulWidget {
  const LyricsSheet({
    required this.song,
    required this.source,
    this.session,
    this.syncMs = 0,
    this.hideSong = false,
    super.key,
  });

  final Song song;
  final LyricsSource source;
  final SpotifySession? session;

  /// Handed to [LyricsView.syncMs].
  final int syncMs;
  final bool hideSong;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  /// What two fingers asked for, for as long as the sheet is up.
  ///
  /// Not kept like the stage's size ([LyricsScaleStore]): that one is a
  /// property of the room - how far the sofa is from the wall - while this is
  /// arm's length whatever the room looks like, so what is set here is set
  /// for a song and not for an evening.
  double _scale = 1;

  /// Far enough either way to be worth the gesture.
  static const double _min = 0.7;
  static const double _max = 2.2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;
    final base = theme.textTheme.titleLarge!;

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
          child: LyricsView(
            song: song,
            source: widget.source,
            session: widget.session,
            syncMs: widget.syncMs,
            scaleOf: () => _scale,
            onScale: (scale) =>
                setState(() => _scale = scale.clamp(_min, _max)),
            lineStyle: base.copyWith(
              fontSize: (base.fontSize ?? 22) * _scale,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// The words of [song], line by line - in the sheet, and on the stage of the
/// wide layout, where they stay up for the whole round.
///
/// With a [session] a synced text follows the player and a tap on a line seeks
/// there. The session can turn up after the view does: the stage is built as
/// soon as the round is, and only the launch says a moment later whether the
/// song plays in this tab. It can go again too, when Spotify takes the song and
/// then cannot play it.
class LyricsView extends StatefulWidget {
  const LyricsView({
    required this.song,
    required this.source,
    this.session,
    this.syncMs = 0,
    this.lineStyle,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 48),
    this.scaleOf,
    this.onScale,
    super.key,
  });

  final Song song;
  final LyricsSource source;
  final SpotifySession? session;

  /// How far ahead of the song the lines run, on top of [_lead] - what a cast
  /// screen costs on its way to the wall, set in the menu and kept per device
  /// (`LyricsSyncStore`).
  final int syncMs;

  /// The size of a line. Null is the sheet's; the stage is read across a room.
  final TextStyle? lineStyle;

  /// Around the lines, inside the scrolling.
  final EdgeInsets padding;

  /// Two fingers on the words, where somebody can do something with it: the
  /// factor in force now, and where the new one goes. Both null leaves the
  /// text at the size it was given.
  ///
  /// The gesture is handled in here rather than around it, because the list
  /// that must hold still while two fingers are on it is this one's.
  final double Function()? scaleOf;
  final ValueChanged<double>? onScale;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<Lyrics?> _lyrics = _load();

  /// The recording length the text was picked for. A synced text is only laid
  /// over a recording of its own length, and that length is only known once
  /// the player has said - so the pick is made again when it does.
  Duration? _pickedFor;

  Future<Lyrics?> _load() {
    _pickedFor = _knownDuration;
    return widget.source.find(widget.song, duration: _pickedFor);
  }

  Duration? get _knownDuration {
    final duration = widget.session?.duration;
    return duration == null || duration == Duration.zero ? null : duration;
  }

  /// How often the line being sung is looked up. The seek bar is happy with
  /// 250ms, a line of a song is not: a quarter of a second is the difference
  /// between a text that follows the singing and one that trails it.
  static const Duration _tick = Duration(milliseconds: 80);

  /// How far ahead of the singing a line lights up.
  ///
  /// [Lyrics.lineAt] switches exactly on the timestamp, which is the moment
  /// the word is sung - too late to read along to. Every karaoke player leads
  /// a little; this one by a sixth of a second, enough to have read the line
  /// before it starts and not enough to look wrong.
  static const Duration _lead = Duration(milliseconds: 160);

  /// The player reports on changes only; between two reports the line moves on
  /// the clock, so it is looked up on a tick of its own.
  Timer? _ticker;

  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _lineKeys = [];
  int _current = -1;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.key != widget.song.key ||
        oldWidget.source != widget.source) {
      _loaded = null;
      _current = -1;
      _lyrics = _load();
    }
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session?.removeListener(_onSession);
      _ticker?.cancel();
      _ticker = null;
      _current = -1;
      _attach();
      if (_pickIsStale) _lyrics = _load();
    }
  }

  void _attach() {
    final session = widget.session;
    if (session == null) return;
    session.addListener(_onSession);
    _ticker = Timer.periodic(_tick, (_) => _follow());
  }

  bool get _pickIsStale {
    final duration = _knownDuration;
    return duration != null && duration != _pickedFor;
  }

  void _onSession() {
    if (_pickIsStale) setState(() => _lyrics = _load());
  }

  @override
  void dispose() {
    widget.session?.removeListener(_onSession);
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
    final line = lyrics.lineAt(
      session.position + _lead + Duration(milliseconds: widget.syncMs),
    );
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
    return FutureBuilder<Lyrics?>(
      future: _lyrics,
      builder: (context, snapshot) {
        // A pick made again for the length of the recording keeps the
        // words up while it runs, instead of a spinner over them.
        final ready = snapshot.connectionState == ConnectionState.done;
        if (!ready && _loaded == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (ready && snapshot.hasError) {
          return _failed(context);
        }
        final lyrics = ready ? snapshot.data : _loaded;
        if (lyrics == null || lyrics.lines.isEmpty) {
          _loaded = null;
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

  /// True while two fingers are resizing the words. The list then stops
  /// scrolling: two fingers moving are a drag to it, and the words slipping
  /// away under the pinch means letting go somewhere other than where it
  /// started (2026-10-27).
  bool _pinching = false;

  Widget _lines(BuildContext context, Lyrics lyrics) {
    final scaleOf = widget.scaleOf;
    final onScale = widget.onScale;
    final list = _list(context, lyrics);
    if (scaleOf == null || onScale == null) return list;

    return PinchScale(
      scaleOf: scaleOf,
      onScale: onScale,
      onActive: (active) {
        if (active != _pinching) setState(() => _pinching = active);
      },
      child: list,
    );
  }

  Widget _list(BuildContext context, Lyrics lyrics) {
    final theme = Theme.of(context);
    final session = widget.session;
    final follows = session != null && lyrics.isSynced;
    while (_lineKeys.length < lyrics.lines.length) {
      _lineKeys.add(GlobalKey());
    }

    return SingleChildScrollView(
      controller: _scroll,
      physics: _pinching ? const NeverScrollableScrollPhysics() : null,
      padding: widget.padding,
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
    final base = widget.lineStyle ?? theme.textTheme.titleLarge!;
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
    if (line.text.isEmpty) return SizedBox(key: key, height: 24);

    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        // Air between the lines, on top of the leading inside them: the whole
        // text at once is what the room has to read, and packed tight it is a
        // wall rather than lines somebody can follow.
        padding: const EdgeInsets.symmetric(vertical: 11),
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
