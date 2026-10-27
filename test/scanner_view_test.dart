import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anno/data/camera_facing_store.dart';
import 'package:anno/ui/scanner_screen.dart';

/// Counts what the scanner asks of the camera, without one behind it.
class FakeCameraController extends MobileScannerController {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async => starts++;

  @override
  Future<void> stop() async => stops++;
}

void main() {
  Future<FakeCameraController> openScanner(WidgetTester tester) async {
    // In debug mode the scanner first asks the platform to stop whatever a
    // hot restart left running, and only starts once that is answered.
    const channel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final camera = FakeCameraController();
    await tester.pumpWidget(
      MaterialApp(
        home: ScannerView(controller: camera, onCode: (_) {}),
      ),
    );
    await tester.pump();
    return camera;
  }

  void moveTo(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('a scanner out of view stops the camera, and starts it again', (
    tester,
  ) async {
    final camera = await openScanner(tester);
    expect(camera.starts, 1);

    // The tab hidden, or the phone switched over to Spotify.
    moveTo(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(camera.stops, 1, reason: 'once, not once per state');

    moveTo(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(camera.starts, 2);
  });

  testWidgets('a moment without focus keeps the camera running', (
    tester,
  ) async {
    final camera = await openScanner(tester);

    // What the browser's camera permission prompt does to the page.
    moveTo(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);

    expect(camera.stops, 0);
    expect(camera.starts, 1);
  });

  testWidgets('a code to read past does not lock the view', (tester) async {
    // The regression this guards: the view reports one code and then stops
    // looking, so a code thrown away by the game afterwards left a running
    // preview that read nothing for the rest of the evening.
    const channel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final read = <String>[];
    var stale = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ScannerView(
          controller: FakeCameraController(),
          onCode: read.add,
          ignore: (code) => stale && code == 'the card still lying there',
        ),
      ),
    );
    await tester.pump();

    // By hand rather than by camera, which is the same way in.
    Future<void> enter(String code) async {
      await tester.tap(find.text('Enter the code by hand').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    await enter('the card still lying there');
    expect(read, isEmpty);

    await enter('the next card');
    expect(read, ['the next card']);
  });

  testWidgets('a code read past can be read again a moment later', (
    tester,
  ) async {
    // The card is picked up and held to the camera on purpose, which is the
    // normal way to try it: the same code has to get through once the game
    // stops calling it stale.
    const channel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final read = <String>[];
    var stale = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ScannerView(
          controller: FakeCameraController(),
          onCode: read.add,
          ignore: (code) => stale,
        ),
      ),
    );
    await tester.pump();

    Future<void> enter(String code) async {
      await tester.tap(find.text('Enter the code by hand').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    await enter('the same card');
    expect(read, isEmpty);

    stale = false;
    await enter('the same card');
    expect(read, ['the same card']);
  });

  testWidgets('a scanner that was closed does not come back on resume', (
    tester,
  ) async {
    final camera = await openScanner(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final starts = camera.starts;

    moveTo(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);

    expect(camera.starts, starts);
  });

  testWidgets('the camera can be turned around, and stays turned', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final camera = FlipCameraController();
    await tester.pumpWidget(
      MaterialApp(
        home: ScannerView(controller: camera, onCode: (_) {}),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Turn the camera around'));
    await tester.pumpAndSettle();

    expect(camera.started.last, CameraFacing.front);
    expect(camera.stops, 1, reason: 'stopped before it starts on the other');
    // The next scanner opens on the same side: every round builds a
    // controller of its own, so a flip that was not kept would last one card.
    expect(CameraFacingStore.isFront, isTrue);
    await CameraFacingStore.preload();
    expect(CameraFacingStore.facing, CameraFacing.front);
  });

  testWidgets(
    'a camera that cannot open the other side is said out loud, not saved',
    (tester) async {
      // The real bug (2026-10-28): `start` does not throw when the platform
      // cannot open the requested side - it stores the failure on `value`
      // and returns normally, which a `try`/`catch` around the call never
      // sees. The flip has to read `value` after the `await`.
      // The previous test leaves the store on the front side; pin it back
      // down so this test's target side does not depend on test order.
      SharedPreferences.setMockInitialValues({'camera.front': false});
      await CameraFacingStore.preload();
      const channel = MethodChannel(
        'dev.steenbakker.mobile_scanner/scanner/method',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final camera = OneSidedCameraController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScannerView(controller: camera, onCode: (_) {}),
          ),
        ),
      );
      // Let the initial auto-start settle on the back camera, so the flip
      // below has a known side to fall back to - same as a camera that was
      // actually running before the tap.
      await tester.pumpAndSettle();
      expect(camera.value.cameraDirection, CameraFacing.back);

      await tester.tap(find.byTooltip('Turn the camera around'));
      // Not pumpAndSettle: that runs through the snack bar's own animation
      // and its default auto-dismiss, so by the time it is idle again the
      // message is already gone.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No other camera: Not supported'), findsOneWidget);
      // Back to the side that was actually running.
      expect(camera.value.cameraDirection, CameraFacing.back);
      expect(CameraFacingStore.isFront, isFalse);
    },
  );
}

/// A camera with two sides, which is what a phone or a tablet has.
///
/// It answers `start` the way a platform does - with the side it ended up on -
/// because that is what the flip is driven by now: the plugin's own
/// `switchCamera` gave up silently on an Android tablet.
class FlipCameraController extends FakeCameraController {
  final List<CameraFacing> started = [];

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    starts++;
    final side = cameraDirection ?? CameraFacing.back;
    started.add(side);
    value = value.copyWith(
      cameraDirection: side,
      isInitialized: true,
      isRunning: true,
    );
  }
}

/// A camera with one side, which is what some tablets have - and which
/// `start` reports by storing an error on `value` rather than throwing, same
/// as the real plugin.
class OneSidedCameraController extends FakeCameraController {
  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    starts++;
    final side = cameraDirection ?? CameraFacing.back;
    if (side == CameraFacing.back) {
      value = value.copyWith(
        cameraDirection: side,
        isInitialized: true,
        isRunning: true,
      );
      return;
    }
    value = value.copyWith(
      cameraDirection: CameraFacing.unknown,
      isInitialized: true,
      isRunning: false,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(message: 'Not supported'),
      ),
    );
  }
}
