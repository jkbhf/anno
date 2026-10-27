import 'dart:io';

import 'package:anno_relay/anno_relay.dart';

/// `dart run bin/relay.dart`, or the AOT binary behind a reverse proxy.
///
/// It binds the loopback by default: the page is served over https, so the
/// socket has to be wss, and the certificate belongs to the proxy in front
/// rather than in here. `ANNO_RELAY_HOST=0.0.0.0` where the proxy is on
/// another machine.
Future<void> main(List<String> args) async {
  final port = int.tryParse(
    _argument(args, '--port') ??
        Platform.environment['ANNO_RELAY_PORT'] ??
        '8787',
  );
  if (port == null) {
    stderr.writeln('--port needs a number');
    exitCode = 64;
    return;
  }
  final host =
      _argument(args, '--host') ??
      Platform.environment['ANNO_RELAY_HOST'] ??
      '127.0.0.1';

  final relay = RelayServer();
  await relay.start(address: host, port: port);

  // systemd stops a unit with SIGTERM, and the rooms should go down with a
  // close rather than with a reset the phone has to time out on.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await relay.stop();
      exit(0);
    });
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
