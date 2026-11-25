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

  testWidgets('says so when the tablet has no vibration motor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const AppSettings(),
          onChanged: (_) {},
          pcName: null,
          onForget: () {},
          canVibrate: false,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Vibrate'), 200);
    expect(find.textContaining('no vibration motor'), findsOneWidget);
  });

  testWidgets('picks a theme', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Neon'));
    await tester.pump();

    expect(saved.theme, 'neon');
  });

  testWidgets('turns on full screen', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Full screen'));
    await tester.pump();

    expect(saved.fullScreen, isTrue);
  });

  testWidgets('adds a ready Racing page', (tester) async {
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const AppSettings(),
          onChanged: (_) {},
          pcName: 'GAMING-PC',
          onForget: () {},
          onAddRacingPage: () => added = true,
        ),
      ),
    );

    final button = find.text('Add a Racing page');
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);

    expect(added, isTrue);
  });

  testWidgets('puts music and clock on the first page', (tester) async {
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const AppSettings(),
          onChanged: (_) {},
          pcName: 'GAMING-PC',
          onForget: () {},
          onAddHomeWidgets: () => added = true,
        ),
      ),
    );

    final button = find.text('Add music and clock to the first page');
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);

    expect(added, isTrue);
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
