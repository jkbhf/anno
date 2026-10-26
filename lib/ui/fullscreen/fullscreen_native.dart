/// Android and iOS: the app is published for the web only, and a native build
/// has no browser chrome in the way. Nothing to hide, so the menu entry that
/// would offer it stays out.
bool fullscreenSupported() => false;

bool fullscreenIsOn() => false;

Future<void> toggleFullscreen() async {}
