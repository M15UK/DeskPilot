import 'package:deskpilot/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ButtonStyleButton playPauseButton(WidgetTester tester) => tester.widget(
    find.ancestor(
      of: find.text('Play / Pause'),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );

  testWidgets('starts disconnected with Play/Pause turned off', (tester) async {
    await tester.pumpWidget(const DeskPilotApp());

    expect(find.text('Not connected'), findsOneWidget);
    expect(playPauseButton(tester).onPressed, isNull);
  });

  testWidgets('asks for the PC address before connecting', (tester) async {
    await tester.pumpWidget(const DeskPilotApp());

    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(find.text("Type your PC's address first"), findsOneWidget);
    expect(playPauseButton(tester).onPressed, isNull);
  });
}
