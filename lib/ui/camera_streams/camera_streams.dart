import 'camera_streams_native.dart'
    if (dart.library.js_interop) 'camera_streams_web.dart'
    as platform;

/// Makes sure the camera is off whenever no scanner shows it.
///
/// `mobile_scanner` 7.4.0 never ends a camera stream on the web: `stop` and
/// `dispose` let go of the stream without stopping its tracks, so the camera
/// runs on after the scanner has closed - the light stays on, and every scan
/// opens one more stream beside the ones still running. Measured in Chrome on
/// 2026-10-26: two scans, two live camera tracks, no scanner on screen. 7.4.1
/// and 7.4.2 do not touch it.
///
/// Every scanner holds the camera while it is on screen and releases it when
/// it goes; with none left, every stream the page opened is stopped.
abstract final class CameraStreams {
  /// A scanner is about to ask for the camera.
  static void hold() => platform.holdCamera();

  /// That scanner is gone. A stream it asked for that only arrives now is
  /// stopped as it arrives.
  static void release() => platform.releaseCamera();

  /// Stops every stream now, with the scanner still on screen - for a page
  /// that went out of view. The scanner asks for a new one when it starts
  /// again.
  static void stopAll() => platform.stopCameraStreams();
}
