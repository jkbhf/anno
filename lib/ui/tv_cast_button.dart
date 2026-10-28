import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tv_room_store.dart';
import '../sync/tv_link.dart';
import 'app_scope.dart';
import 'text_input_dialog.dart';
import 'tv_screen.dart';

/// The second screen, as one button in the app bar of the setup screen.
///
/// Only where a relay was compiled in, the same arrangement the in-app player
/// has with its client id: a build without one is a build where this does not
/// exist rather than one where it fails.
///
/// It was a card in the body before (2026-10-27) and is a cast icon now, for
/// the reason every other phone app puts one there: it is a decision about the
/// room rather than about the game, it is made once an evening, and the body of
/// that screen is about who is playing. The icon is also what says whether a
/// television is on the line, which the card could only say by taking a block
/// of the screen to do it.
///
/// Which end a device is, it is told in the sheet behind the button. The
/// television takes the entry that turns *this* screen into one - a
/// television's own keyboard is a remote control with four arrows on it, so the
/// only thing anybody should have to type there is the address, and the rest is
/// one press.
class TvCastButton extends StatelessWidget {
  const TvCastButton({super.key});

  @override
  Widget build(BuildContext context) {
    final link = AppScope.of(context).link;
    if (!link.isAvailable) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => _button(context, link),
    );
  }

  Widget _button(BuildContext context, TvLink link) {
    final theme = Theme.of(context);
    final paired = link.isPaired && link.role == LinkRole.remote;
    final joining = _isJoining(link);

    final (IconData icon, String tooltip, Color? color) = switch (link.state) {
      _ when paired => (
        Icons.cast_connected,
        'Paired with a television',
        theme.colorScheme.primary,
      ),
      _ when joining => (Icons.cast, 'Looking for the television', null),
      LinkState.failed => (
        Icons.error_outline,
        'That did not pair',
        theme.colorScheme.error,
      ),
      _ => (Icons.cast, 'Play on a television', null),
    };

    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _TvSheet(),
      ),
    );
  }
}

/// A line on its way up or already up, but not yet answered by a television.
bool _isJoining(TvLink link) =>
    link.role == LinkRole.remote &&
    (link.state == LinkState.connecting || link.state == LinkState.waiting);

/// What the button opens: which end this device is, and the way out of it.
class _TvSheet extends StatefulWidget {
  const _TvSheet();

  @override
  State<_TvSheet> createState() => _TvSheetState();
}

class _TvSheetState extends State<_TvSheet> {
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
            hintText: '123456',
            monospace: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            helper: const Text(
              'Open anno on the television, press the cast button in the top '
              'bar and then "This screen is the television". It shows six '
              'digits.',
            ),
            validator: (value) => value.trim().length == 6
                ? null
                : 'Six digits, as they stand on the screen.',
          ),
        );
    if (code == null || !mounted) return;
    await link.join(code);
    await TvRoomStore.save(code.trim().toUpperCase());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _unpair(TvLink link) async {
    await link.leave();
    await TvRoomStore.clear();
    if (mounted) Navigator.of(context).pop();
  }

  void _beTheScreen() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(builder: (context) => const TvScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = AppScope.of(context).link;
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => _content(context, link),
    );
  }

  Widget _content(BuildContext context, TvLink link) {
    final theme = Theme.of(context);
    final paired = link.isPaired && link.role == LinkRole.remote;
    final joining = _isJoining(link);

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
    final accent = failed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(color: accent),
            ),
            const SizedBox(height: 20),
            // One width for all of them, stacked. Side by side the two ends of
            // the line were two buttons of different heights sitting on
            // different lines of a Wrap, which read as a layout gone wrong
            // rather than as a choice between two things.
            if (paired || joining)
              OutlinedButton.icon(
                onPressed: () => _unpair(link),
                icon: const Icon(Icons.cast_outlined),
                label: const Text('Unpair'),
              )
            else ...[
              FilledButton.icon(
                onPressed: () => _join(link),
                icon: const Icon(Icons.keyboard),
                label: const Text('Type the code'),
              ),
              if (_remembered case final code?) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _join(link, code),
                  icon: const Icon(Icons.replay),
                  label: Text('Back to $code'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _beTheScreen,
                icon: const Icon(Icons.tv),
                label: const Text('This screen is the television'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
