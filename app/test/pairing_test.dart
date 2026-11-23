import 'dart:convert';

import 'package:deskpilot/pairing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final fingerprint = 'a' * 64;

String qrText({
  Object? version = 2,
  Object? hosts = const ['192.168.1.50', '10.0.0.7'],
  Object? port = 8740,
  Object? fingerprint,
  Object? code = 'code123',
}) => jsonEncode({
  'deskpilot': version,
  'name': 'GAMING-PC',
  'hosts': hosts,
  'port': port,
  'fingerprint': fingerprint ?? 'a' * 64,
  'code': ?code,
});

void main() {
  test('reads the QR code the PC shows', () {
    // Same text as PairingQrTests in the agent.
    final qr = readPairingQr(qrText());

    expect(qr, isNotNull);
    expect(qr!.code, 'code123');
    expect(qr.pc.name, 'GAMING-PC');
    expect(qr.pc.hosts, ['192.168.1.50', '10.0.0.7']);
    expect(qr.pc.port, 8740);
    expect(qr.pc.fingerprint, fingerprint);
  });

  test('refuses QR codes that are not from DeskPilot', () {
    final notOurs = {
      'a website': 'https://example.com',
      'an older version': qrText(version: 1),
      'a bad fingerprint': qrText(fingerprint: 'xyz'),
      'no addresses': qrText(hosts: <String>[]),
      'a name instead of an address': qrText(hosts: ['evil.example.com']),
      'a port out of range': qrText(port: 70000),
      'no code': qrText(code: null),
      'an empty code': qrText(code: ''),
    };
    notOurs.forEach((what, text) {
      expect(readPairingQr(text), isNull, reason: what);
    });
  });

  group('PcStore', () {
    const store = PcStore();
    final saved = (
      pc: PcInfo(
        name: 'GAMING-PC',
        hosts: const ['192.168.1.50'],
        port: 8740,
        fingerprint: fingerprint,
      ),
      key: 'secret-key',
    );

    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('remembers the paired PC', () async {
      await store.save(saved);

      final loaded = await store.load();

      expect(loaded?.key, 'secret-key');
      expect(loaded?.pc.toJson(), saved.pc.toJson());
    });

    test('forgets the PC', () async {
      await store.save(saved);

      await store.clear();

      expect(await store.load(), isNull);
    });

    test('ignores damaged saved data', () async {
      FlutterSecureStorage.setMockInitialValues({'pc': 'not json'});

      expect(await store.load(), isNull);
    });
  });
}
