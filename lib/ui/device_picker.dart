import 'package:flutter/material.dart';

import '../music/spotify_session.dart';

/// The cast button on the remote, and the sheet behind it: where the song
/// comes out of.
///
/// The game runs on the phone and the music does not have to - a television
/// with Spotify on it, a speaker in the kitchen. Which one is a decision about
/// the room, so it is made here and remembered (`PlaybackDeviceStore`), and the
/// automatic pick (the phone, see `pickConnectDevice`) is one of the choices
/// rather than the only rule.
///
/// Only a session that commands another app has anything to pick, so the
/// button is drawn only where [SpotifySession.canPickDevice] and the login is
/// through. A laptop playing in its own tab is its own device, and the link
/// path has none.
class CastButton extends StatelessWidget {
  const CastButton({required this.session, super.key});

  final SpotifySession session;

  @override
  Widget build(BuildContext context) {
    if (!session.canPickDevice) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.connection != SpotifyConnection.ready) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: 'Where the song plays',
          icon: Icon(
            session.pickedDeviceId == null
                ? Icons.cast_outlined
                : Icons.cast_connected,
          ),
          onPressed: () => showDevicePicker(context, session),
        );
      },
    );
  }
}

/// Opens the picker. Asks the service for its devices as it opens, because
/// Spotify lists a device only while its app is running - the list from five
/// minutes ago is not the list.
Future<void> showDevicePicker(
  BuildContext context,
  SpotifySession session,
) async {
  final refresh = session.refreshDevices();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // The sheet sizes itself to the list instead of to nine sixteenths of the
    // screen: a handful of devices does not fill that, and more than a
    // handful would overflow it.
    isScrollControlled: true,
    builder: (context) => _DeviceSheet(session: session, first: refresh),
  );
}

class _DeviceSheet extends StatefulWidget {
  const _DeviceSheet({required this.session, required this.first});

  final SpotifySession session;

  /// The look-up that was started as the sheet opened, so the spinner can
  /// wait for that one instead of asking a second time.
  final Future<void> first;

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  late Future<void> _loading = widget.first;

  Future<void> _reload() async {
    final again = widget.session.refreshDevices();
    setState(() {
      _loading = again;
    });
    await again;
  }

  Future<void> _pick(String? id) async {
    final navigator = Navigator.of(context);
    // Closed on the tap rather than after the round trip: the transfer is a
    // request to Spotify and the room is in the middle of a song.
    navigator.pop();
    await widget.session.pickDevice(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final devices = widget.session.devices;
          final picked = widget.session.pickedDeviceId;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Where the song plays',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Look again',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              // A column in a scroll view rather than a list: an account has
              // a handful of devices, and a lazy list in a sheet that sizes
              // itself to its content builds only the first of them.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        onTap: () => _pick(null),
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('This phone, automatically'),
                        subtitle: const Text(
                          'The phone when Spotify is open on it, otherwise '
                          'whatever the account has running.',
                        ),
                        trailing: picked == null
                            ? const Icon(Icons.check)
                            : null,
                      ),
                      for (final device in devices)
                        ListTile(
                          onTap: () => _pick(device.id),
                          leading: Icon(_iconFor(device.type)),
                          title: Text(device.name),
                          subtitle: device.isActive
                              ? const Text('Playing now')
                              : null,
                          trailing: picked == device.id
                              ? const Icon(Icons.check)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
              // The one thing nobody can guess, and the reason a list can look
              // short: a device Spotify has not heard from is not on it.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: FutureBuilder<void>(
                  future: _loading,
                  builder: (context, snapshot) => Text(
                    snapshot.connectionState == ConnectionState.waiting
                        ? 'Looking for devices...'
                        : 'Only a device with Spotify open on it is listed. '
                              'Open the app there once, then look again.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Spotify's own word for the device, which is all there is to go on.
IconData _iconFor(String type) => switch (type.toLowerCase()) {
  'smartphone' => Icons.smartphone,
  'tablet' => Icons.tablet,
  'computer' => Icons.laptop,
  'tv' => Icons.tv,
  'castvideo' => Icons.cast,
  'castaudio' => Icons.speaker,
  'speaker' => Icons.speaker,
  'avr' || 'stb' => Icons.settings_input_hdmi,
  'automobile' => Icons.directions_car,
  _ => Icons.devices_other,
};
