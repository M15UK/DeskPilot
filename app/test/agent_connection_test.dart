import 'dart:io';

import 'package:deskpilot/agent_connection.dart';
import 'package:deskpilot/deck.dart';
import 'package:deskpilot/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pc.dart';

const hello = {'type': 'hello', 'name': 'GAMING-PC', 'version': 5};

// What a PC on the current DeskPilot says.
const currentHello = {'type': 'hello', 'name': 'GAMING-PC', 'version': 6};

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
    agent.press('play-pause');
    expect(await fake.nextMessage(), {'type': 'press', 'id': 'play-pause'});
    agent.saveDeck(const Deck([DeckPage(name: 'Racing', buttons: [])]));
    expect(await fake.nextMessage(), {
      'type': 'saveDeck',
      'deck': {
        'pages': [
          {'name': 'Racing', 'buttons': <Object>[]},
        ],
      },
    });
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
    expect(agent.pcIsOutOfDate, isTrue, reason: 'this PC says version 5');
  });

  test('a PC on the current DeskPilot is up to date', () async {
    final fake = pc = await FakePc.start((_) => [currentHello]);

    final agent = await AgentConnection.signIn((
      pc: infoFor(fake),
      key: 'saved-key',
    ));
    addTearDown(agent.close);

    expect(agent.pcIsOutOfDate, isFalse);
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

  test('the deck arrives after signing in', () async {
    final fake = pc = await FakePc.start(
      (_) => [
        hello,
        {
          'type': 'deck',
          'deck': {
            'pages': [
              {'name': 'Main', 'buttons': <Object>[]},
            ],
          },
        },
      ],
    );

    final agent = await AgentConnection.signIn((
      pc: infoFor(fake),
      key: 'saved-key',
    ));
    addTearDown(agent.close);

    final first = await agent.events().first;
    expect(first, isA<DeckChanged>());
    expect((first as DeckChanged).deck.pages.single.name, 'Main');
  });

  test('reads what the PC says', () {
    expect(
      readEvent('{"type":"error","message":"Key buttons work on Windows."}'),
      isA<PcSays>().having(
        (e) => e.text,
        'text',
        'Key buttons work on Windows.',
      ),
    );
    expect(
      readEvent('{"type":"deck","deck":{"pages":[]}}'),
      isA<PcSays>(),
      reason: 'a deck the app cannot show',
    );
    expect(
      readEvent(
        '{"type":"stats","stats":{"cpuLoad":12.5,"gpuTemp":41,"ramLoad":"x"}}',
      ),
      isA<StatsChanged>().having((e) => e.stats, 'stats', {
        'cpuLoad': 12.5,
        'gpuTemp': 41.0,
      }),
    );
    expect(
      readEvent(
        '{"type":"telemetry","telemetry":{"rpm":7350,"gear":3,"bestLap":102.345}}',
      ),
      isA<TelemetryChanged>().having((e) => e.telemetry, 'telemetry', {
        'rpm': 7350.0,
        'gear': 3.0,
        'bestLap': 102.345,
      }),
    );
    expect(
      readEvent('{"type":"image","id":"0123456789abcdef","data":"AQID"}'),
      isA<PictureArrived>()
          .having((e) => e.id, 'id', '0123456789abcdef')
          .having((e) => e.bytes, 'bytes', [1, 2, 3]),
    );
    expect(
      readEvent('{"type":"image","id":"0123456789abcdef"}'),
      isA<PictureArrived>().having((e) => e.bytes, 'bytes', isNull),
      reason: 'the PC no longer has it',
    );
    expect(
      readEvent('not json'),
      isA<PcSays>().having(
        (e) => e.text,
        'text',
        'Unexpected message from the PC',
      ),
    );
  });
}
