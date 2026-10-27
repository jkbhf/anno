import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/lyrics_sync_store.dart';
import 'beep/beep.dart';

/// Sets how far the words run ahead of the song, by making the thing that is
/// out of step visible and audible at once.
///
/// Once a second the dialog plays a click and lights a panel in the same
/// instant. The click is heard where the laptop is; the panel is seen wherever
/// the screen is being cast to, which is later. Press more until the two land
/// together on the wall, and the number that does it is the number the words
/// need - the same pipeline delays them.
///
/// Returns the value that was set, or null if it was left alone.
Future<int?> showLyricsSyncDialog(
  BuildContext context, {
  required int offsetMs,
}) => showDialog<int>(
  context: context,
  builder: (context) => _LyricsSyncDialog(offsetMs: offsetMs),
);

class _LyricsSyncDialog extends StatefulWidget {
  const _LyricsSyncDialog({required this.offsetMs});

  final int offsetMs;

  @override
  State<_LyricsSyncDialog> createState() => _LyricsSyncDialogState();
}

class _LyricsSyncDialogState extends State<_LyricsSyncDialog> {
  /// A second apart, which is slow enough to judge one against the other and
  /// quick enough to try a new number without waiting for it.
  static const Duration _beat = Duration(seconds: 1);

  /// How long the panel stays lit. Long enough to see across a room, short
  /// enough that its beginning is still a point in time.
  static const Duration _flash = Duration(milliseconds: 120);

  late int _offset = LyricsSyncStore.clamp(widget.offsetMs);
  Timer? _metronome;
  Timer? _off;
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    // The first one comes with the dialog rather than a second later: the tap
    // that opened it is also what lets the page make a sound at all.
    _tick();
    _metronome = Timer.periodic(_beat, (_) => _tick());
  }

  @override
  void dispose() {
    _metronome?.cancel();
    _off?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    Beep.play();
    setState(() => _lit = true);
    _off?.cancel();
    _off = Timer(_flash, () {
      if (mounted) setState(() => _lit = false);
    });
  }

  void _set(int ms) {
    final next = LyricsSyncStore.clamp(ms);
    if (next == _offset) return;
    setState(() => _offset = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CallbackShortcuts(
      // A dialog is a route of its own, so the game's keys are not in the way
      // here and the obvious ones are free: the arrows nudge, enter is done.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _set(_offset - LyricsSyncStore.step),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _set(_offset + LyricsSyncStore.step),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.pop(context, _offset),
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: const Text('Sync the words'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  Beep.isSupported
                      ? 'The click and the flash happen at the same moment '
                            'here. On a cast screen the flash arrives later - '
                            'press more until the two meet over there.'
                      : 'Casting delays the picture. The words leave that '
                            'much earlier, so they arrive with the song.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _FlashPanel(lit: _lit),
                const SizedBox(height: 20),
                _Amount(offset: _offset),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _offset <= LyricsSyncStore.min
                            ? null
                            : () => _set(_offset - LyricsSyncStore.step),
                        icon: const Icon(Icons.remove),
                        label: const Text('100 ms'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _offset >= LyricsSyncStore.max
                            ? null
                            : () => _set(_offset + LyricsSyncStore.step),
                        icon: const Icon(Icons.add),
                        label: const Text('100 ms'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Cable (0)'),
                      selected: _offset == LyricsSyncStore.none,
                      onSelected: (_) => _set(LyricsSyncStore.none),
                    ),
                    ChoiceChip(
                      label: const Text('Casting (300)'),
                      selected: _offset == LyricsSyncStore.casting,
                      onSelected: (_) => _set(LyricsSyncStore.casting),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _offset),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The seen half of the beat.
///
/// Big and plain on purpose: what has to be judged is the moment it starts,
/// from across a room and through whatever the cast does to the picture, so
/// it is a field of colour rather than anything with a shape to read.
class _FlashPanel extends StatelessWidget {
  const _FlashPanel({required this.lit});

  final bool lit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lit
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.volume_up_rounded,
        size: 40,
        color: lit
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

/// The number, in words anybody can check against what they just did.
class _Amount extends StatelessWidget {
  const _Amount({required this.offset});

  final int offset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          '$offset ms',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          switch (offset) {
            0 => 'The words run with the song',
            < 0 => 'The words run behind the song',
            _ => 'The words run ahead of the song',
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
