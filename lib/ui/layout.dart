import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Whether a screen gets a layout built sideways: the game's stage and side
/// column, the category screen's two columns of cards.
///
/// Landscape is the whole question, there is no size floor under it. The
/// upright layouts are built for a screen taller than wide; laid out sideways
/// they keep their capped column and leave a sixth of the screen empty on
/// either side, while the height they want is what a turned phone has least
/// of. The 1.2 rather than a plain `width > height` keeps a nearly square
/// browser window on one column, where two things side by side would both be
/// too narrow.
bool isWideScreen(Size size) => size.width >= size.height * 1.2;

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
