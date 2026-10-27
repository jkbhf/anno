import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/camera_facing_store.dart';
import 'camera_streams/camera_streams.dart';
import 'text_input_dialog.dart';

/// Builds what reads a card and hands its code to [onCode]. The real one is a
/// [ScannerView]; a test hands in a stand-in.
typedef CameraBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onCode);

/// Camera screen for the QR cards. Returns the scanned raw value.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({this.camera, super.key});

  /// Null is the device camera.
  final CameraBuilder? camera;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  /// Owned here rather than by the view, because the torch sits in the app
  /// bar. None for a stand-in, which has no torch to switch.
  late final MobileScannerController? _controller = widget.camera == null
      ? ScannerView.newController()
      : null;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Scan QR code'),
        actions: [
          if (controller != null)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: controller,
              builder: (context, state, _) => IconButton(
                tooltip: 'Torch',
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flashlight_on
                      : Icons.flashlight_off,
                ),
                onPressed: state.isInitialized ? controller.toggleTorch : null,
              ),
            ),
        ],
      ),
      body:
          widget.camera?.call(context, _submit) ??
          ScannerView(controller: controller, onCode: _submit),
    );
  }

  void _submit(String code) {
    if (!mounted) return;
    Navigator.of(context).pop(code);
  }
}

/// The camera with what belongs to it: the frame to aim at, the way to type a
/// code in, and what to say when there is no camera. Reports the first code
/// it reads, once.
///
/// Fills whatever it is given - the whole phone screen, or the small box in the
/// side column of the wide layout.
///
/// The camera runs only while the view is on screen and in sight: it stops
/// when the view goes, see [CameraStreams], and while the page is out of view
/// - a hidden tab, the phone switched over to Spotify - with the scanner still
/// open.
class ScannerView extends StatefulWidget {
  const ScannerView({
    required this.onCode,
    this.ignore,
    this.controller,
    super.key,
  });

  final ValueChanged<String> onCode;

  /// Codes to read past rather than report - the card of the round that is
  /// still lying in front of the camera, see `GameScreen`.
  ///
  /// The test has to be here and not at the other end of [onCode]: this view
  /// reports one code and then stops looking, so a code thrown away after it
  /// was reported locks the camera for good. That was the bug this exists for
  /// (2026-10-27): after a reveal the preview ran and read nothing, because
  /// the one code it had reported was the card nobody had taken away yet.
  final bool Function(String code)? ignore;

  /// Null makes one of its own.
  final MobileScannerController? controller;

  /// Reports every read rather than only a code that differs from the one
  /// before it, because [ignore] has to be able to see the same card twice.
  ///
  /// `noDuplicates` was the other half of the camera that scanned nothing
  /// after a reveal (2026-10-27): the card lying in front of the lens was
  /// read once, read past, and from then on the plugin called it a duplicate -
  /// so the same card held up on purpose a second later could not be read at
  /// all, and only closing the camera and opening it again helped. One report
  /// per view is [_ScannerViewState._handled]'s job and always was.
  ///
  /// It opens on the side the device was last flipped to
  /// ([CameraFacingStore]), because every scan builds one of these: the
  /// inline camera in the side column opens and closes with the round, and a
  /// flip that only lasted that round would be no option at all.
  static MobileScannerController newController() => MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
    facing: CameraFacingStore.facing,
  );

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> with WidgetsBindingObserver {
  MobileScannerController? _own;

  MobileScannerController get _controller =>
      widget.controller ?? (_own ??= ScannerView.newController());

  /// Keeps two quick hits from reporting twice.
  bool _handled = false;

  /// The camera was stopped because the page went out of view, and starts
  /// again when it comes back.
  bool _away = false;

  @override
  void initState() {
    super.initState();
    CameraStreams.hold();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _own?.dispose();
    CameraStreams.release();
    super.dispose();
  }

  /// `mobile_scanner` would do this itself, but only for a controller it made
  /// - and every one here is handed in.
  ///
  /// Only out of view counts, not `inactive`: on the web the camera permission
  /// prompt takes the focus, and stopping there would stop a camera that is
  /// just being asked for.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        if (_away) return;
        _away = true;
        unawaited(_controller.stop());
        CameraStreams.stopAll();
      case AppLifecycleState.resumed:
        if (!_away) return;
        _away = false;
        unawaited(_restart());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _restart() async {
    try {
      await _controller.start();
    } on MobileScannerException {
      // Still starting from before, or refused - the error view says which.
    }
  }

  void _submit(String code) {
    if (_handled || !mounted) return;
    if (widget.ignore?.call(code) ?? false) return;
    _handled = true;
    widget.onCode(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _submit(value.trim());
        return;
      }
    }
  }

  /// Turns the camera around: the front one on a phone held out over the
  /// table, the back one for a card held up to it.
  ///
  /// The side is remembered for the next scanner rather than only for this
  /// one, see [CameraFacingStore] - otherwise the flip would be undone by the
  /// next round. The plugin reports which side it ended up on, so what is
  /// saved is what happened and not what was asked for.
  Future<void> _flip() async {
    try {
      await _controller.switchCamera();
    } on MobileScannerException {
      // One camera, or it refused - nothing to say about it, the picture is
      // still the one it was.
      return;
    }
    if (!mounted) return;
    await CameraFacingStore.save(
      front: _controller.value.cameraDirection == CameraFacing.front,
    );
  }

  Future<void> _enterManually() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const TextInputDialog(
        title: 'Enter code',
        confirmLabel: 'Continue',
        hintText: 'Link from the card, or a year',
      ),
    );
    if (code != null && code.isNotEmpty) _submit(code);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The box in the side column is a fraction of a phone screen; the
        // frame and the margins shrink with it rather than filling it up.
        final compact = constraints.biggest.shortestSide < 400;
        final controller = _controller;

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _ScannerError(
                  message: _explain(error),
                  onManual: _enterManually,
                  compact: compact,
                ),
              ),
              // The frame and the second button belong to a working camera.
              // Over the error they cut through the message and say the same
              // thing twice.
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: controller,
                builder: (context, state, _) => state.error != null
                    ? const SizedBox.shrink()
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          _ScanFrame(
                            size: min(
                              240,
                              constraints.biggest.shortestSide * 0.6,
                            ),
                          ),
                          Align(
                            // In the small box of the side column the whole
                            // sentence lies across the frame; there the way
                            // to type a code is the keyboard alone, in a
                            // corner, with the words in its tooltip.
                            alignment: compact
                                ? Alignment.bottomRight
                                : Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(compact ? 4 : 24),
                              child: compact
                                  ? IconButton(
                                      tooltip: 'Enter the code by hand',
                                      onPressed: _enterManually,
                                      icon: const Icon(Icons.keyboard),
                                      color: Colors.white,
                                    )
                                  : TextButton.icon(
                                      onPressed: _enterManually,
                                      icon: const Icon(Icons.keyboard),
                                      label: const Text(
                                        'Enter the code by hand',
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          // The other camera, where the device has one: a
                          // phone pointed at a card wants the back one, a
                          // phone lying on the table between people the
                          // front. Opposite corner from the keyboard, so
                          // neither is hit by accident in the small box.
                          if (state.availableCameras == null ||
                              state.availableCameras! > 1)
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: EdgeInsets.all(compact ? 4 : 24),
                                child: IconButton(
                                  tooltip: 'Turn the camera around',
                                  onPressed: _flip,
                                  icon: const Icon(Icons.cameraswitch),
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What went wrong, in words for whoever is holding the phone - not the name
/// of an enum value.
String _explain(MobileScannerException error) => switch (error.errorCode) {
  MobileScannerErrorCode.permissionDenied =>
    'The camera is not allowed for this page. Allow it in the browser\'s site '
        'settings and open the scanner again.',
  MobileScannerErrorCode.unsupported =>
    'This browser offers no camera here. The page needs https, and a browser '
        'that may use the camera.',
  _ => error.errorDetails?.message ?? 'The camera could not be started.',
};

class _ScanFrame extends StatelessWidget {
  const _ScanFrame({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70, width: 3),
          borderRadius: BorderRadius.circular(size / 10),
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({
    required this.message,
    required this.onManual,
    required this.compact,
  });

  final String message;
  final VoidCallback onManual;

  /// In the small box the message would not fit at full size; it scales down
  /// together with its button rather than being cut off.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.no_photography, size: 48, color: Colors.white54),
        const SizedBox(height: 16),
        Text(
          'Camera unavailable\n$message',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onManual,
          icon: const Icon(Icons.keyboard),
          label: const Text('Enter the code by hand'),
        ),
      ],
    );

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 32),
          child: compact
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(width: 320, child: content),
                )
              : content,
        ),
      ),
    );
  }
}
