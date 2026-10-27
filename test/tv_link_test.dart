import 'package:anno/game/game_controller.dart';
import 'package:anno/sync/sync_messages.dart';
import 'package:anno/sync/tv_link.dart';
import 'package:anno_relay/anno_relay.dart';
import 'package:flutter_test/flutter_test.dart';

/// The link against the real relay rather than against a fake socket: what
/// matters here is the handshake between the two, and a fake of one of them
/// would only prove that the fake agrees with itself.
void main() {
  late RelayServer relay;
  late String url;

  setUp(() async {
    relay = RelayServer();
    await relay.start(port: 0);
    url = 'ws://127.0.0.1:${relay.port}/';
  });

  tearDown(() async => relay.stop());

  TvLink link() {
    final made = TvLink(url: url);
    addTearDown(made.dispose);
    return made;
  }

  Future<void> until(bool Function() done) async {
    for (var waited = 0; waited < 400; waited++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('never happened');
  }

  const snapshot = GameSnapshot(
    phase: RoundPhase.playing,
    players: [(name: 'Anthony', score: 3)],
    targetScore: 10,
    showScores: true,
    year: 1974,
    title: 'Waterloo',
    artist: 'ABBA',
    deck: 'ESC',
  );

  test('the screen opens a room and the phone joins its code', () async {
    final screen = link();
    await screen.host();
    await until(() => screen.code != null);
    expect(screen.state, LinkState.waiting);

    final phone = link();
    await phone.join(screen.code!.toLowerCase());
    await until(() => phone.isPaired && screen.isPaired);
  });

  test('the round goes to the screen, and the screen asks for it', () async {
    final screen = link();
    final seen = <SyncMessage>[];
    var peers = 0;
    screen.onMessage = seen.add;
    await screen.host();
    await until(() => screen.code != null);

    final phone = link();
    phone.onPeer = () => peers++;
    await phone.join(screen.code!);
    await until(() => phone.isPaired);

    phone.send(snapshot);
    await until(() => seen.isNotEmpty);
    final arrived = seen.single as GameSnapshot;
    expect(arrived.title, 'Waterloo');
    expect(arrived.year, 1974);
    expect(arrived.players.single.score, 3);
    expect(arrived.phase, RoundPhase.playing);

    // Pairing is what asks the phone for everything, whichever end arrived
    // last: a screen knows only what it was told.
    expect(peers, 1);
    await until(() => screen.isPaired);
  });

  test('a snapshot survives the trip unchanged', () {
    final there = GameSnapshot.fromJson(snapshot.toJson().cast());
    expect(there.toJson(), snapshot.toJson());
    expect(there.song?.title, 'Waterloo');
    expect(there.category?.name, 'ESC');
  });

  test('a tick says where the song is', () async {
    final screen = link();
    final seen = <SyncMessage>[];
    screen.onMessage = seen.add;
    await screen.host();
    await until(() => screen.code != null);

    final phone = link();
    await phone.join(screen.code!);
    await until(() => phone.isPaired);

    phone.send(
      const PlaybackTick(positionMs: 42000, durationMs: 180000, playing: true),
    );
    await until(() => seen.isNotEmpty);
    final tick = seen.single as PlaybackTick;
    expect(tick.positionMs, 42000);
    expect(tick.durationMs, 180000);
    expect(tick.playing, isTrue);
  });

  test('a step for the screen goes over as a step', () async {
    final screen = link();
    final seen = <SyncMessage>[];
    screen.onMessage = seen.add;
    await screen.host();
    await until(() => screen.code != null);

    final phone = link();
    await phone.join(screen.code!);
    await until(() => phone.isPaired);

    phone.send(const RemoteCommand(RemoteStep.wordsEarlier));
    await until(() => seen.isNotEmpty);
    expect((seen.single as RemoteCommand).step, RemoteStep.wordsEarlier);
  });

  test('a code nobody is waiting for says so and stops trying', () async {
    final phone = link();
    await phone.join('ZZZZZZ');
    await until(() => phone.state == LinkState.failed);
    expect(phone.problem, contains('No screen'));

    // And it stays failed rather than spinning: the code is wrong, and no
    // number of retries makes it right.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(phone.state, LinkState.failed);
  });

  test('nothing is sent while nobody is listening', () async {
    final screen = link();
    await screen.host();
    await until(() => screen.code != null);
    // No throw, no socket write: the snapshot that counts is the one sent
    // when a peer turns up.
    screen.send(snapshot);
    expect(screen.state, LinkState.waiting);
  });

  test('a build without a relay says so instead of trying', () async {
    final none = TvLink(url: '');
    addTearDown(none.dispose);
    expect(none.isAvailable, isFalse);
    await none.host();
    expect(none.state, LinkState.failed);
  });

  test('the phone hears the screen come back and is asked again', () async {
    final screen = link();
    await screen.host();
    await until(() => screen.code != null);
    final code = screen.code!;

    final phone = link();
    var asked = 0;
    phone.onPeer = () => asked++;
    await phone.join(code);
    await until(() => phone.isPaired);
    expect(asked, 1);

    await screen.leave();
    await until(() => !phone.isPaired);

    final second = link();
    await second.host(code: code);
    await until(() => phone.isPaired);
    expect(asked, 2, reason: 'a fresh screen knows nothing yet');
    expect(second.code, code);
  });
}
