import 'dart:convert';
import 'dart:io';

import 'package:deskpilot/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ButtonStyleButton playPauseButton(WidgetTester tester) => tester.widget(
    find.ancestor(
      of: find.text('Play / Pause'),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );

  testWidgets('asks to scan the QR code when no PC is paired', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const DeskPilotApp());
    await tester.pump();

    expect(find.text('Scan the QR code'), findsOneWidget);
    expect(find.text('Play / Pause'), findsNothing);
  });

  testWidgets('a paired PC shows Play/Pause and can be forgotten', (
    tester,
  ) async {
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

    expect(find.text('Play / Pause'), findsOneWidget);
    expect(playPauseButton(tester).onPressed, isNull);
    expect(find.textContaining("Couldn't reach GAMING-PC"), findsOneWidget);

    await tester.tap(find.byTooltip('Forget this PC'));
    await tester.pump();

    expect(find.text('Scan the QR code'), findsOneWidget);
  });
}

/// No network, like a phone in airplane mode.
class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('No network in widget tests');
}
