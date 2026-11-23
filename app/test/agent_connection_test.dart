import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deskpilot/agent_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows the PC name, then sends Play/Pause to the PC', () async {
    final pc = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => pc.close(force: true));
    final received = Completer<String>();
    pc.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(
        jsonEncode({'type': 'hello', 'name': 'GAMING-PC', 'version': 1}),
      );
      socket.listen((message) => received.complete(message as String));
    });

    final agent = await AgentConnection.connect('127.0.0.1', port: pc.port);
    addTearDown(agent.close);
    final firstStatus = Completer<String>();
    agent.statuses.listen((status) {
      if (!firstStatus.isCompleted) firstStatus.complete(status);
    });

    expect(await firstStatus.future, 'Connected to GAMING-PC');
    agent.playPause();
    expect(jsonDecode(await received.future), {
      'type': 'media',
      'action': 'playPause',
    });
  });

  test('connecting to a PC that is not running fails', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();

    await expectLater(
      AgentConnection.connect('127.0.0.1', port: port),
      throwsA(isA<Exception>()),
    );
  });

  test('shows errors from the PC and ignores anything else', () {
    expect(
      describe('{"type":"error","message":"Play/Pause works on Windows."}'),
      'Play/Pause works on Windows.',
    );
    expect(describe('not json'), 'Unexpected message from the PC');
    expect(describe('[1, 2]'), 'Unexpected message from the PC');
    expect(describe('{"type":"surprise"}'), 'Unexpected message from the PC');
  });
}
