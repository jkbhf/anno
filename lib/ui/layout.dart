import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Whether a screen gets a layout built sideways: the game's stage and side
/// column, the category screen's two columns of cards.
///
/// Landscape, and tall enough to be a device the layout was meant for: a
/// tablet on its side, a laptop, a projector, a television. Not a phone turned
/// over - that was tried (2026-10-26 to 27) and the column ends up 214 pixels
/// wide, which is a year card with an ellipsis in the title and a camera box
/// with its own buttons on top of each other. 500 is the line between the two:
/// a 10 inch tablet sideways is 768 high, every laptop is 600 or more, and no
/// phone sideways reaches 450.
///
/// The 1.2 rather than a plain `width > height` keeps a nearly square browser
/// window on one column, where two things side by side would both be too
/// narrow.
bool isWideScreen(Size size) =>
    size.height >= 500 && size.width >= size.height * 1.2;

/// Whether an upright layout should let its column grow past the width it is
/// built for: a screen that is wider than tall but not the wide layout's, so
/// a phone turned over, which would otherwise be a 560 pixel strip with a
/// third of the screen empty on either side.
bool isShortLandscape(Size size) =>
    !isWideScreen(size) && size.width >= size.height * 1.2;

/// Whether this device probably has a keyboard, which is the only thing the
/// shortcuts are shown for.
///
/// On the web `defaultTargetPlatform` reports the operating system, so a
/// laptop and a desktop say macOS, Windows or Linux and a phone says Android
/// or iOS. A tablet with a keyboard attached is called wrong here, and that
/// costs it the hint line - the keys themselves work wherever one is pressed.
bool get hasKeyboard => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};
