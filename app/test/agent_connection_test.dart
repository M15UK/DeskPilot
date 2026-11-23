import 'dart:io';

import 'package:deskpilot/agent_connection.dart';
import 'package:deskpilot/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pc.dart';

const hello = {'type': 'hello', 'name': 'GAMING-PC', 'version': 2};

void main() {
  FakePc? pc;
  tearDown(() => pc?.stop());

  PcInfo infoFor(FakePc pc, {String? fingerprint}) => PcInfo(
    name: 'GAMING-PC',
    hosts: const ['127.0.0.1'],
    port: pc.port,
    fingerprint: fingerprint ?? pc.fingerprint,
  );

  test('pairs with the QR code and keeps the new key', () async {
    final fake = pc = await FakePc.start(
      (_) => [
        {'type': 'paired', 'key': 'new-key'},
        hello,
      ],
    );

    final agent = await AgentConnection.pair((
      pc: infoFor(fake),
      code: 'code123',
    ));
    addTearDown(agent.close);

    expect(agent.key, 'new-key');
    expect(agent.pcName, 'GAMING-PC');
    expect(await fake.nextMessage(), {'type': 'pair', 'code': 'code123'});
    agent.playPause();
    expect(await fake.nextMessage(), {'type': 'media', 'action': 'playPause'});
  });

  test('signs in with the saved key', () async {
    final fake = pc = await FakePc.start((_) => [hello]);

    final agent = await AgentConnection.signIn((
      pc: infoFor(fake),
      key: 'saved-key',
    ));
    addTearDown(agent.close);

    expect(agent.key, 'saved-key');
    expect(await fake.nextMessage(), {'type': 'auth', 'key': 'saved-key'});
  });

  test('shows why the PC refused', () async {
    const why = 'This phone is not paired with this PC. Pair it again.';
    final fake = pc = await FakePc.start(
      (_) => [
        {'type': 'error', 'message': why},
      ],
    );

    await expectLater(
      AgentConnection.signIn((pc: infoFor(fake), key: 'old-key')),
      throwsA(isA<AgentRefused>().having((e) => e.message, 'message', why)),
    );
  });

  test('never talks to a PC with a different certificate', () async {
    final fake = pc = await FakePc.start((_) => [hello]);

    await expectLater(
      AgentConnection.signIn((
        pc: infoFor(fake, fingerprint: '0' * 64),
        key: 'saved-key',
      )),
      throwsA(isA<AgentRefused>()),
    );
    expect(fake.receivedCount, 0);
  });

  test('a PC that is not running gives a clear error', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();
    final pc = PcInfo(
      name: 'GAMING-PC',
      hosts: const ['127.0.0.1'],
      port: port,
      fingerprint: '0' * 64,
    );

    await expectLater(
      AgentConnection.signIn((pc: pc, key: 'saved-key')),
      throwsA(
        isA<AgentRefused>().having(
          (e) => e.message,
          'message',
          contains("Couldn't reach GAMING-PC"),
        ),
      ),
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
