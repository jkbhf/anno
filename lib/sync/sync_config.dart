/// Compiled in with `--dart-define=ANNO_RELAY_URL=wss://...`.
///
/// Empty by default, and then the whole second screen stays out of the app:
/// no entry on the setup screen, nothing to pair with. The same arrangement
/// the in-app player has with its client id - a build without it is a build
/// that works, only with less in it.
///
/// It has to be `wss://`: the page is served over https, and a browser refuses
/// a plain socket from there.
const String annoRelayUrl = String.fromEnvironment('ANNO_RELAY_URL');

bool get hasRelay => annoRelayUrl.isNotEmpty;
