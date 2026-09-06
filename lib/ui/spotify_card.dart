import 'package:flutter/material.dart';

import '../music/spotify_session.dart';

/// The switch between the two ways of playing a song.
///
/// Only shown where there is something to switch: on the web, with a client id
/// compiled in. Everywhere else the app hands songs to Spotify by link and
/// there is nothing to decide.
class SpotifyCard extends StatelessWidget {
  const SpotifyCard({required this.session, super.key});

  final SpotifySession session;

  @override
  Widget build(BuildContext context) {
    if (!session.isAvailable) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);

    final (
      IconData icon,
      String title,
      String body,
      Widget? action,
    ) = switch (session.connection) {
      SpotifyConnection.unavailable => (Icons.link_off, '', '', null),
      SpotifyConnection.disconnected => (
        Icons.music_note_outlined,
        'Play in the app',
        'Connect Spotify Premium and the song comes out of this page - no '
            'new tab, no switching back.',
        FilledButton.icon(
          onPressed: session.connect,
          icon: const Icon(Icons.link),
          label: const Text('Connect Spotify'),
        ),
      ),
      SpotifyConnection.connecting => (
        Icons.music_note_outlined,
        'Connecting to Spotify',
        'One moment - the player is starting up.',
        null,
      ),
      // Nothing to say once it works: the way back out lives in the app
      // bar, see [SpotifyMenuButton].
      SpotifyConnection.ready => (Icons.check_circle_outline, '', '', null),
      SpotifyConnection.failed => (
        Icons.error_outline,
        'Spotify could not start',
        session.error ?? 'Unknown reason.',
        FilledButton.icon(
          onPressed: session.connect,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ),
    };

    if (title.isEmpty) return const SizedBox.shrink();
    final failed = session.connection == SpotifyConnection.failed;

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
                    if (action != null) ...[
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: action),
                    ],
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
