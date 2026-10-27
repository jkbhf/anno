import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'sync_config.dart';
import 'sync_messages.dart';

/// Which end of the link this device is.
enum LinkRole {
  /// The screen: it opens the room and shows the code.
  screen,

  /// The phone: it joins a code and runs the game.
  remote,
}

enum LinkState {
  /// Nothing is paired and nothing is being tried.
  off,

  /// A socket is on its way, or a dropped one is being picked back up.
  connecting,

  /// Connected to the relay, waiting for the other end.
  waiting,

  /// Both ends are on the line.
  paired,

  /// Refused, and not worth retrying by itself - a code nobody is waiting
  /// for, or a relay that is full. [TvLink.problem] says which.
  failed,
}

/// The line between the phone that runs the game and the screen that shows it.
///
/// Both ends use this class; [LinkRole] is the whole difference. The screen
/// opens a room and reads the code off it, the phone joins that code, and from
/// then on the phone talks and the screen listens.
///
/// A dropped socket is the normal case, not a failure: a television sleeps, a
/// phone changes cell, a relay restarts. So it reconnects on its own, and the
/// screen comes back **to the code it had** rather than to a new one - the
/// code is written on nothing, it is only in the room and on the phone.
class TvLink extends ChangeNotifier {
  TvLink({
    this.url = annoRelayUrl,
    WebSocketChannel Function(Uri)? connector,
    this.retryFrom = const Duration(seconds: 1),
    this.retryTo = const Duration(seconds: 10),
  }) : _connect = connector ?? WebSocketChannel.connect;

  /// A line that is up without a socket under it, for the widget tests.
  ///
  /// The socket itself is tested against the real relay in `tv_link_test`;
  /// what a screen does with a line that is already paired is a different
  /// question, and waiting on real I/O inside a widget test answers it
  /// slower and less reliably.
  @visibleForTesting
  factory TvLink.paired({
    required LinkRole role,
    String code = 'ABC123',
    void Function(SyncMessage message)? onSend,
  }) {
    final link = TvLink(url: 'test');
    link._role = role;
    link._code = code;
    link._peers = 2;
    link._left = false;
    link._sent = onSend;
    link._state = LinkState.paired;
    return link;
  }

  final String url;
  final WebSocketChannel Function(Uri) _connect;

  /// Where [send] goes when there is no socket, see [TvLink.paired].
  void Function(SyncMessage message)? _sent;

  /// How long after a dropped socket the next try is, doubling up to the cap.
  final Duration retryFrom;
  final Duration retryTo;

  /// What arrived from the other end. On the screen that is the round; on the
  /// phone it is nothing, because nothing comes back.
  void Function(SyncMessage message)? onMessage;

  /// The other end turned up - a first pairing, or a screen that came back
  /// from a reload. The phone answers it with a full snapshot: everything the
  /// screen knows, it knows because it was told, so a new screen knows
  /// nothing until it is told again.
  VoidCallback? onPeer;

  LinkState _state = LinkState.off;
  LinkRole _role = LinkRole.screen;
  String? _code;
  String? _problem;
  int _peers = 1;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _listening;
  Timer? _retry;
  Duration _nextRetry = const Duration(seconds: 1);

  /// True while [leave] has taken the line down on purpose: then a closing
  /// socket is the point rather than something to pick back up.
  bool _left = true;

  LinkState get state => _state;
  LinkRole get role => _role;

  /// The room's code, six characters. Known on the screen the moment the
  /// relay answers, and on the phone from the moment it was typed in.
  String? get code => _code;

  /// Why it will not work, in words for the player.
  String? get problem => _problem;

  bool get isPaired => _state == LinkState.paired;

  /// Whether this build has a relay to talk to at all.
  bool get isAvailable => url.isNotEmpty;

  /// Opens a room and waits for a phone. [code] is for coming back to a room
  /// this screen had before - a reload, or a socket that dropped.
  Future<void> host({String? code}) => _start(LinkRole.screen, code);

  /// Joins the code read off a screen.
  Future<void> join(String code) =>
      _start(LinkRole.remote, code.trim().toUpperCase());

  Future<void> _start(LinkRole role, String? code) async {
    await leave();
    if (!isAvailable) {
      _fail('This build has no relay to pair through.');
      return;
    }
    _left = false;
    _role = role;
    _code = code;
    _problem = null;
    _nextRetry = retryFrom;
    await _open();
  }

  Future<void> _open() async {
    _move(LinkState.connecting);
    final target = Uri.parse(url).replace(
      queryParameters: {
        'room': ?_code,
        if (_role == LinkRole.screen && _code != null) 'host': '1',
      },
    );

    try {
      final channel = _connect(target);
      _channel = channel;
      await channel.ready;
      if (_left) {
        await channel.sink.close();
        return;
      }
      _listening = channel.stream.listen(
        _incoming,
        onDone: _closed,
        onError: (Object error) {
          debugPrint('Link error: $error');
          _closed();
        },
        cancelOnError: true,
      );
      _move(LinkState.waiting);
    } on Object catch (error) {
      debugPrint('Link could not open: $error');
      _closed();
    }
  }

  void _incoming(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } on Object catch (error) {
      debugPrint('Link got nonsense: $error');
      return;
    }

    switch (json['t']) {
      case 'room':
        _code = json['code'] as String? ?? _code;
        // A reconnect that worked is the moment to forget the backoff, or an
        // evening of brief drops ends up ten seconds behind.
        _nextRetry = retryFrom;
        _peersAre(json['peers'] as int? ?? 1);
      case 'peers':
        _peersAre(json['count'] as int? ?? 1);
      case 'refused':
        // Not retried: a code typed in wrong would loop forever, and the
        // player has to see the answer rather than a spinner.
        _fail(json['why'] as String? ?? 'The relay refused the connection.');
        _left = true;
        unawaited(_drop());
      default:
        final message = SyncMessage.fromJson(json);
        if (message != null) onMessage?.call(message);
    }
  }

  void _peersAre(int count) {
    final arrived = count > _peers;
    _peers = count;
    _move(count > 1 ? LinkState.paired : LinkState.waiting);
    if (arrived && count > 1) onPeer?.call();
  }

  void _closed() {
    _listening?.cancel();
    _listening = null;
    _channel = null;
    if (_left) {
      _move(LinkState.off);
      return;
    }
    _move(LinkState.connecting);
    _retry?.cancel();
    _retry = Timer(_nextRetry, () {
      if (_left) return;
      unawaited(_open());
    });
    final doubled = _nextRetry * 2;
    _nextRetry = doubled > retryTo ? retryTo : doubled;
  }

  /// Sends a message to the other end. Dropped on the floor while nobody is
  /// there - the snapshot that matters is the one sent when a peer turns up.
  void send(SyncMessage message) {
    if (_state != LinkState.paired) return;
    final test = _sent;
    if (test != null) {
      test(message);
      return;
    }
    try {
      _channel?.sink.add(jsonEncode(message.toJson()));
    } on Object catch (error) {
      debugPrint('Link could not send: $error');
    }
  }

  Future<void> leave() async {
    _left = true;
    _retry?.cancel();
    _retry = null;
    await _drop();
    _peers = 1;
    _move(LinkState.off);
  }

  Future<void> _drop() async {
    await _listening?.cancel();
    _listening = null;
    final channel = _channel;
    _channel = null;
    try {
      await channel?.sink.close();
    } on Object catch (error) {
      debugPrint('Link could not close: $error');
    }
  }

  void _fail(String why) {
    _problem = why;
    _move(LinkState.failed);
  }

  /// Always tells, even where the state did not move: the code and the number
  /// of devices change under an unchanged state, and both are on the screen.
  void _move(LinkState next) {
    _state = next;
    notifyListeners();
  }

  /// A socket can close after the screen that held it is gone - a retry
  /// timer, a close that was still on its way.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _left = true;
    _retry?.cancel();
    unawaited(_drop());
    super.dispose();
  }
}
