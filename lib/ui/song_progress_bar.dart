import 'dart:async';

import 'package:flutter/material.dart';

import '../music/spotify_playback.dart';

/// Where the song is, and a way to move around in it - for a round played in
/// this tab.
///
/// The room often wants the chorus, or the intro once more: the track is
/// dragged to the middle, or started over. Only the in-app player can do this;
/// a song handed to Spotify by link is out of reach.
///
/// Drawn quiet on purpose. It sits under the reveal panel, which is the one
/// thing on the screen the room is meant to go for.
class SongProgressBar extends StatefulWidget {
  const SongProgressBar({required this.session, super.key});

  final SpotifySession session;

  /// How far the skip buttons jump.
  static const Duration skip = Duration(seconds: 10);

  @override
  State<SongProgressBar> createState() => _SongProgressBarState();
}

class _SongProgressBarState extends State<SongProgressBar> {
  /// The player only reports on changes; between two reports the position is
  /// the clock's, so the bar has to be redrawn on a tick of its own.
  Timer? _ticker;

  /// Where the thumb is while a finger holds it. The song only jumps on
  /// release - seeking on every pixel of a drag would stutter the audio.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final session = widget.session;
      if (mounted &&
          session.isPlaying &&
          session.duration > Duration.zero &&
          _dragMs == null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _seekBy(Duration offset) {
    final session = widget.session;
    final target = session.position + offset;
    unawaited(session.seek(target < Duration.zero ? Duration.zero : target));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final durationMs = session.duration.inMilliseconds.toDouble();
    final known = durationMs > 0;
    final positionMs = (_dragMs ?? session.position.inMilliseconds.toDouble())
        .clamp(0.0, known ? durationMs : 0.0);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
            thumbColor: theme.colorScheme.primary,
          ),
          child: Slider(
            value: positionMs,
            max: known ? durationMs : 1,
            onChanged: known
                ? (value) => setState(() => _dragMs = value)
                : null,
            onChangeEnd: known
                ? (value) {
                    setState(() => _dragMs = null);
                    unawaited(
                      session.seek(Duration(milliseconds: value.round())),
                    );
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                _format(Duration(milliseconds: positionMs.round())),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
              const Spacer(),
              Text(
                known ? _format(session.duration) : '--:--',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'From the start',
              onPressed: known ? () => session.seek(Duration.zero) : null,
              icon: const Icon(Icons.skip_previous_rounded),
              color: muted,
            ),
            IconButton(
              tooltip: '10 seconds back',
              onPressed: known ? () => _seekBy(-SongProgressBar.skip) : null,
              icon: const Icon(Icons.replay_10_rounded),
              color: muted,
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: session.isPlaying ? 'Pause' : 'Play on',
              onPressed: session.togglePause,
              iconSize: 32,
              icon: Icon(
                session.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '10 seconds ahead',
              onPressed: known ? () => _seekBy(SongProgressBar.skip) : null,
              icon: const Icon(Icons.forward_10_rounded),
              color: muted,
            ),
            IconButton(
              tooltip: 'To the middle',
              onPressed: known
                  ? () => session.seek(session.duration ~/ 2)
                  : null,
              icon: const Icon(Icons.align_horizontal_center_rounded),
              color: muted,
            ),
          ],
        ),
      ],
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
