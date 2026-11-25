import 'package:deskpilot/settings.dart';
import 'package:deskpilot/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppSettings saved;
  var backedUp = false;

  Widget host() => MaterialApp(
    home: SettingsPage(
      settings: const AppSettings(),
      onChanged: (settings) => saved = settings,
      pcName: 'GAMING-PC',
      onForget: () {},
      onBackup: () => backedUp = true,
      onLoadBackup: () {},
    ),
  );

  testWidgets('backs up the deck', (tester) async {
    await tester.pumpWidget(host());

    await tester.scrollUntilVisible(find.text('Back up the deck'), 200);
    await tester.tap(find.text('Back up the deck'));

    expect(backedUp, isTrue);
    expect(find.text('Load a backup'), findsOneWidget);
  });

  testWidgets('picks a theme', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Neon'));
    await tester.pump();

    expect(saved.theme, 'neon');
  });

  testWidgets('turns on full screen and big PC cards', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Full screen'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Big PC cards'), 200);
    await tester.tap(find.text('Big PC cards'));
    await tester.pump();

    expect((saved.fullScreen, saved.bigPcCards), (true, true));
  });

  testWidgets('square corners and tight spacing', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Square'));
    await tester.pump();
    await tester.tap(find.text('Tight'));
    await tester.pump();

    expect((saved.corners, saved.spacing), ('square', 'tight'));
  });
}
