/// Compiled in with `--dart-define=SPOTIFY_CLIENT_ID=...`.
///
/// Empty by default, and then the in-app player simply stays unavailable and
/// the app hands songs to Spotify by link as it always did. The client id is
/// public by design - the login runs as Authorization Code with PKCE, which
/// needs no client secret and must never carry one in a browser.
const String spotifyClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
