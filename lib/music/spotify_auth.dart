/// The Spotify login, apart from what is done with it.
///
/// Two sessions need the same token: the Web Playback SDK, which turns a
/// desktop tab into a Spotify device, and Spotify Connect, which commands a
/// device the player already has - the phone's own Spotify app. The login is
/// the delicate part of both (PKCE, a rotating refresh token, the difference
/// between a token Spotify refused and one it never saw), so it lives here
/// once instead of twice.
library;

/// How a login that was picked back up came out.
enum LoginState {
  /// There is a token and it works.
  loggedIn,

  /// Nobody is logged in, and nothing failed - the normal first visit.
  noLogin,

  /// Something went wrong, see [LoginResult.message].
  failed,
}

class LoginResult {
  const LoginResult(this.state, [this.message]);

  const LoginResult.loggedIn() : state = LoginState.loggedIn, message = null;
  const LoginResult.noLogin() : state = LoginState.noLogin, message = null;
  const LoginResult.failed(String this.message) : state = LoginState.failed;

  final LoginState state;

  /// Words for the player, where the state is [LoginState.failed].
  final String? message;
}

abstract class SpotifyAuth {
  /// True while a refresh token from an earlier visit is around. Asked before
  /// anything is awaited, so a session can tell a first visit from a return.
  bool get hasLogin;

  /// True when the browser just came back from the login page and the query
  /// still holds its answer. Only then is a [restore] worth a "connecting".
  bool get hasPendingRedirect;

  /// Picks up the redirect the page came back with, or the stored token.
  Future<LoginResult> restore();

  /// Refreshes the stored token without touching the address bar - the "try
  /// again" after a wobbly connection, which must not cost a login detour.
  Future<LoginResult> resume();

  /// Sends the browser off to Spotify's login page. The page leaves and comes
  /// back to [restore], so nothing after this call runs.
  Future<void> beginLogin();

  /// Drops the token, here and in storage.
  Future<void> forget();

  /// A token good for the next minute, or null when there is none to be had.
  Future<String?> freshToken();
}
