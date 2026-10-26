import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Every stream `getUserMedia` handed out that has not been stopped yet.
final List<web.MediaStream> _streams = [];

/// How many scanners are on screen.
int _held = 0;

bool _watching = false;

void holdCamera() {
  _watch();
  _held++;
}

void releaseCamera() {
  if (_held > 0) _held--;
  if (_held == 0) stopCameraStreams();
}

void stopCameraStreams() {
  for (final stream in _streams) {
    _stop(stream);
  }
  _streams.clear();
}

void _stop(web.MediaStream stream) {
  for (final track in stream.getTracks().toDart) {
    track.stop();
  }
}

/// Wraps `navigator.mediaDevices.getUserMedia`, so the streams it hands to the
/// scanner are known here. The plugin keeps them to itself.
///
/// The game asks for nothing else - the Spotify player plays, it does not
/// record - so every stream is the camera.
void _watch() {
  if (_watching) return;
  // Undefined outside a secure context: plain http has no camera to stop.
  final devices = web.window.navigator.getProperty<JSObject?>(
    'mediaDevices'.toJS,
  );
  final original = devices?.getProperty<JSFunction?>('getUserMedia'.toJS);
  if (devices == null || original == null) return;
  _watching = true;

  JSPromise<web.MediaStream> getUserMedia(JSAny? constraints) {
    final opened =
        original.callAsFunction(devices, constraints)
            as JSPromise<web.MediaStream>;
    return opened.toDart.then((stream) {
      // Closed again before the camera came up.
      if (_held == 0) {
        _stop(stream);
      } else {
        _streams.add(stream);
      }
      return stream;
    }).toJS;
  }

  devices.setProperty('getUserMedia'.toJS, getUserMedia.toJS);
}
