import 'dart:async';

import 'package:flutter/material.dart';

import '../data/tv_room_store.dart';
import '../sync/tv_link.dart';
import 'app_scope.dart';
import 'text_input_dialog.dart';
import 'tv_screen.dart';

/// The two ends of the second screen, offered on the setup screen.
///
/// Only where a relay was compiled in, the same arrangement the in-app player
/// has with its client id: a build without one is a build where this does not
/// exist rather than one where it fails.
///
/// Which end a device is, it is told here. The television takes the button
/// that turns *this* screen into one - a television's own keyboard is a remote
/// control with four arrows on it, so the only thing anybody should have to
/// type there is the address, and the rest is one press.
class TvCard extends StatefulWidget {
  const TvCard({super.key});

  @override
  State<TvCard> createState() => _TvCardState();
}

class _TvCardState extends State<TvCard> {
  /// The code this device last used, so an evening starts with one press
  /// instead of six characters read off the wall again.
  String? _remembered;

  @override
  void initState() {
    super.initState();
    unawaited(_recall());
  }

  Future<void> _recall() async {
    final code = await TvRoomStore.load();
    if (mounted) setState(() => _remembered = code);
  }

  Future<void> _join(TvLink link, [String? known]) async {
    final code =
        known ??
        await showDialog<String>(
          context: context,
          builder: (context) => TextInputDialog(
            title: 'Code from the television',
            confirmLabel: 'Pair',
            hintText: 'ABC123',
            monospace: true,
            helper: const Text(
              'Open anno on the television and press "This screen is the '
              'television". It shows six characters.',
            ),
            validator: (value) => value.trim().length == 6
                ? null
                : 'Six characters, as they stand on the screen.',
          ),
        );
    if (code == null || !mounted) return;
    await link.join(code);
    await TvRoomStore.save(code.trim().toUpperCase());
    if (mounted) setState(() => _remembered = code.trim().toUpperCase());
  }

  Future<void> _unpair(TvLink link) async {
    await link.leave();
    await TvRoomStore.clear();
    if (mounted) setState(() => _remembered = null);
  }

  void _beTheScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const TvScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = AppScope.of(context).link;
    if (!link.isAvailable) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => _content(context, link),
    );
  }

  Widget _content(BuildContext context, TvLink link) {
    final theme = Theme.of(context);
    final paired = link.isPaired && link.role == LinkRole.remote;
    final joining =
        link.role == LinkRole.remote &&
        (link.state == LinkState.connecting ||
            link.state == LinkState.waiting);

    final (IconData icon, String title, String body) = switch (link.state) {
      _ when paired => (
        Icons.cast_connected,
        'Paired with a television',
        'Code ${link.code}. The television shows the round, this phone runs '
            'it - the camera, the reveal, the song and the points.',
      ),
      _ when joining => (
        Icons.cast,
        'Looking for the television',
        'Code ${link.code}. It turns up as soon as the game is open on it.',
      ),
      LinkState.failed => (
        Icons.error_outline,
        'That did not pair',
        link.problem ?? 'Unknown reason.',
      ),
      _ => (
        Icons.tv,
        'Play on a television',
        'The television shows the words, the year and the scores; this phone '
            'is the remote and the music comes out of it.',
      ),
    };

    final failed = link.state == LinkState.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: failed
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: paired || joining
                          ? [
                              OutlinedButton.icon(
                                onPressed: () => _unpair(link),
                                icon: const Icon(Icons.cast_outlined),
                                label: const Text('Unpair'),
                              ),
                            ]
                          : [
                              FilledButton.icon(
                                onPressed: () => _join(link),
                                icon: const Icon(Icons.keyboard),
                                label: const Text('Type the code'),
                              ),
                              if (_remembered case final code?)
                                OutlinedButton.icon(
                                  onPressed: () => _join(link, code),
                                  icon: const Icon(Icons.replay),
                                  label: Text('Back to $code'),
                                ),
                              TextButton.icon(
                                onPressed: _beTheScreen,
                                icon: const Icon(Icons.tv),
                                label: const Text(
                                  'This screen is the television',
                                ),
                              ),
                            ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
