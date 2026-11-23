import 'dart:convert';
import 'dart:io';

import 'package:deskpilot/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('asks to scan the QR code when no PC is paired', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const DeskPilotApp());
    await tester.pump();

    expect(find.text('Scan the QR code'), findsOneWidget);
    expect(find.byTooltip('Edit the deck'), findsNothing);
  });

  testWidgets('a PC it cannot reach can be forgotten', (tester) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _Offline();
    addTearDown(() => HttpOverrides.global = previous);
    FlutterSecureStorage.setMockInitialValues({
      'pc': jsonEncode({
        'pc': {
          'name': 'GAMING-PC',
          'hosts': ['192.0.2.1'],
          'port': 8740,
          'fingerprint': 'a' * 64,
        },
        'key': 'saved-key',
      }),
    });

    await tester.pumpWidget(const DeskPilotApp());
    await tester.pump();

    expect(find.textContaining("Couldn't reach GAMING-PC"), findsOneWidget);
    expect(find.text('Connect again'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget this PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();

    expect(find.text('Scan the QR code'), findsOneWidget);
  });
}

/// No network, like a phone in airplane mode.
class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('No network in widget tests');
}
