import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which camera the scanner opens with, kept per device.
///
/// A laptop has one camera and it points at the room; a phone has two and the
/// back one is the one a card is held up to. Whichever it is, the choice is
/// made once for the evening and has to survive the next scan - the inline
/// camera in the side column builds a controller of its own every time it
/// opens, so without this a flip would last exactly one round.
///
/// Read synchronously ([facing]) because that is when a controller is built,
/// and filled by [preload] at startup. A device that has never been flipped
/// starts on the back camera, which is what the plugin would do anyway.
class CameraFacingStore {
  static const String _key = 'camera.front';

  static bool _front = false;

  /// What a new scanner controller should start on.
  static CameraFacing get facing =>
      _front ? CameraFacing.front : CameraFacing.back;

  static bool get isFront => _front;

  /// Reads the saved side into memory. Awaited once, at startup.
  static Future<void> preload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _front = prefs.getBool(_key) ?? false;
    } on Object catch (error) {
      debugPrint('Camera side not readable: $error');
    }
  }

  static Future<void> save({required bool front}) async {
    _front = front;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, front);
    } on Object catch (error) {
      debugPrint('Could not save the camera side: $error');
    }
  }
}
