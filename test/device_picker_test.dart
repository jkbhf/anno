import 'package:anno/music/spotify_playback.dart';
import 'package:anno/ui/device_picker.dart';
import 'package:anno/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session that commands another app, the way Spotify Connect does.
class _Picky extends NoSpotifySession {
  _Picky({this.listed = const [], this.ready = true});

  final List<PlaybackDevice> listed;
  final bool ready;

  final List<String?> picked = <String?>[];
  int lookUps = 0;

  @override
  SpotifyConnection get connection =>
      ready ? SpotifyConnection.ready : SpotifyConnection.disconnected;

  @override
  bool get canPickDevice => true;

  @override
  List<PlaybackDevice> get devices => listed;

  @override
  String? get pickedDeviceId => picked.isEmpty ? null : picked.last;

  @override
  Future<void> refreshDevices() async => lookUps++;

  @override
  Future<void> pickDevice(String? id) async {
    picked.add(id);
    notifyListeners();
  }
}

const _phone = PlaybackDevice(
  id: 'phone',
  name: 'Jakobs Phone',
  type: 'Smartphone',
  isActive: false,
);

const _tv = PlaybackDevice(
  id: 'tv',
  name: 'Living room TV',
  type: 'TV',
  isActive: true,
);

Widget wrap(NoSpotifySession session) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(
    appBar: AppBar(actions: [CastButton(session: session)]),
  ),
);

void main() {
  /// A phone, so the whole sheet is on the screen - the 800x600 the binding
  /// defaults to is wider than it is tall and cuts the list short.
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the sheet lists the devices and picks one', (tester) async {
    usePhoneScreen(tester);
    final session = _Picky(listed: const [_phone, _tv]);
    addTearDown(session.dispose);

    await tester.pumpWidget(wrap(session));
    await tester.tap(find.byTooltip('Where the song plays'));
    await tester.pumpAndSettle();

    // Asked again as it opened: Spotify lists a device only while its app is
    // running, so the list from five minutes ago is not the list.
    expect(session.lookUps, 1);
    expect(find.text('This phone, automatically'), findsOne);
    expect(find.text('Jakobs Phone'), findsOne);
    expect(find.text('Living room TV'), findsOne);
    // The one Spotify is on right now says so.
    expect(find.text('Playing now'), findsOne);

    await tester.tap(find.text('Living room TV'));
    await tester.pumpAndSettle();

    expect(session.picked, ['tv']);
    // Closed on the tap: the transfer is a request to Spotify, and the room
    // is in the middle of a song.
    expect(find.text('This phone, automatically'), findsNothing);
  });

  testWidgets('the automatic pick is one of the choices', (tester) async {
    usePhoneScreen(tester);
    final session = _Picky(listed: const [_phone]);
    addTearDown(session.dispose);

    await tester.pumpWidget(wrap(session));
    await tester.tap(find.byTooltip('Where the song plays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jakobs Phone'));
    await tester.pumpAndSettle();
    expect(session.picked, ['phone']);

    await tester.tap(find.byTooltip('Where the song plays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This phone, automatically'));
    await tester.pumpAndSettle();
    expect(session.picked, ['phone', null]);
  });

  testWidgets('an empty list says what is missing', (tester) async {
    usePhoneScreen(tester);
    final session = _Picky();
    addTearDown(session.dispose);

    await tester.pumpWidget(wrap(session));
    await tester.tap(find.byTooltip('Where the song plays'));
    await tester.pumpAndSettle();

    // The reason a list can look short, and the one thing nobody can guess.
    expect(find.textContaining('Open the app there once'), findsOne);

    await tester.tap(find.byTooltip('Look again'));
    await tester.pumpAndSettle();
    expect(session.lookUps, 2);
  });

  testWidgets('no login, no button', (tester) async {
    final session = _Picky(ready: false);
    addTearDown(session.dispose);

    await tester.pumpWidget(wrap(session));
    await tester.pumpAndSettle();

    // Nothing to pick between until the account is there.
    expect(find.byTooltip('Where the song plays'), findsNothing);
  });

  testWidgets('a session that is its own device draws no button', (
    tester,
  ) async {
    final session = NoSpotifySession();
    addTearDown(session.dispose);

    await tester.pumpWidget(wrap(session));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Where the song plays'), findsNothing);
  });
}
