import 'package:deskpilot/deck.dart';
import 'package:deskpilot/deck_view.dart';
import 'package:deskpilot/tiles.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const deck = Deck([
  DeckPage(
    name: 'Main',
    buttons: [
      DeckButton(
        id: 'play-pause',
        label: 'Play / Pause',
        action: MediaAction('playPause'),
      ),
    ],
  ),
  DeckPage(name: 'Racing', buttons: []),
]);

void main() {
  Deck? changed;
  String? pressed;
  int? shownPage;

  setUp(() {
    changed = null;
    pressed = null;
    shownPage = null;
  });

  Widget host({
    bool editing = false,
    bool connected = true,
    Deck shown = deck,
  }) => MaterialApp(
    home: Scaffold(
      body: DeckView(
        deck: shown,
        page: 0,
        editing: editing,
        onPress: connected ? (id) => pressed = id : null,
        onChange: (deck) => changed = deck,
        onPageChanged: (page) => shownPage = page,
      ),
    ),
  );

  testWidgets('tapping a button presses it on the PC', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Play / Pause'));

    expect(pressed, 'play-pause');
    expect(find.text('Add button'), findsNothing);
  });

  testWidgets('buttons are off while the PC is not connected', (tester) async {
    await tester.pumpWidget(host(connected: false));

    await tester.tap(find.text('Play / Pause'));

    expect(pressed, isNull);
  });

  testWidgets('the page chips switch pages', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Racing'));

    expect(shownPage, 1);
  });

  testWidgets('adds a key combo button in edit mode', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Add button'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label'),
      'Mute Discord',
    );
    await tester.tap(find.text('Keys'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Key combos'),
      'Ctrl+Shift+M, Alt+Tab',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final added = changed!.pages[0].buttons.last;
    expect(added.label, 'Mute Discord');
    expect((added.action as KeysAction).combos, ['Ctrl+Shift+M', 'Alt+Tab']);
    expect(changed!.pages[0].buttons, hasLength(2));
  });

  testWidgets('an empty label names the button after what it does', (
    tester,
  ) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Add button'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(changed!.pages[0].buttons.last.label, 'CPU load');
  });

  test('buttons name themselves after what they do', () {
    expect(autoLabel(const MediaAction('next')), 'Next');
    expect(autoLabel(const StatAction('gear', 'number')), 'Gear');
    expect(autoLabel(const StatAction('speed', 'gauge')), 'Speed (km/h)');
    expect(autoLabel(const KeysAction(['Ctrl+Shift+M'])), 'Ctrl+Shift+M');
    expect(autoLabel(const OpenAction(r'C:\Games\AC\acs.exe')), 'acs.exe');
    expect(
      autoLabel(const OpenAction('https://www.example.com/x')),
      'www.example.com',
    );
  });

  testWidgets('deletes a button in edit mode', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Play / Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(pressed, isNull);
    expect(changed!.pages[0].buttons, isEmpty);
  });

  testWidgets('picks an icon and a color for a button', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Play / Pause'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('flag'));
    await tester.tap(find.byTooltip('flag'));
    await tester.ensureVisible(find.byTooltip('amber'));
    await tester.tap(find.byTooltip('amber'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = changed!.pages[0].buttons.single;
    expect(saved.icon, 'flag');
    expect(saved.color, 'amber');
  });

  testWidgets('dragging a button onto another moves it there', (tester) async {
    const two = Deck([
      DeckPage(
        name: 'Main',
        buttons: [
          DeckButton(id: 'a', label: 'First', action: MediaAction('previous')),
          DeckButton(id: 'b', label: 'Second', action: MediaAction('next')),
        ],
      ),
    ]);
    await tester.pumpWidget(host(editing: true, shown: two));

    final drag = await tester.startGesture(
      tester.getCenter(find.text('Second')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await drag.moveTo(tester.getCenter(find.text('First')));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect([for (final b in changed!.pages[0].buttons) b.id], ['b', 'a']);
  });

  testWidgets('adds a page in edit mode', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Discord');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      [for (final page in changed!.pages) page.name],
      ['Main', 'Racing', 'Discord'],
    );
    expect(shownPage, 2);
  });

  group('stat tiles', () {
    const pcDeck = Deck([
      DeckPage(
        name: 'PC',
        buttons: [
          DeckButton(
            id: 'gpu-temp',
            label: 'GPU temperature',
            action: StatAction('gpuTemp', 'number'),
          ),
          DeckButton(
            id: 'cpu',
            label: 'CPU',
            action: StatAction('cpuLoad', 'gauge'),
          ),
          DeckButton(
            id: 'ram',
            label: 'RAM',
            action: StatAction('ramLoad', 'chart'),
          ),
        ],
      ),
    ]);

    Widget stats() => MaterialApp(
      home: Scaffold(
        body: DeckView(
          deck: pcDeck,
          page: 0,
          editing: false,
          onPress: (id) => pressed = id,
          onChange: (deck) => changed = deck,
          onPageChanged: (page) => shownPage = page,
          stats: const {'gpuTemp': 41.4, 'cpuLoad': 23.6},
          history: const {
            'cpuLoad': [10, 23.6],
          },
        ),
      ),
    );

    testWidgets('show the PC readings', (tester) async {
      await tester.pumpWidget(stats());

      expect(find.text('41°C'), findsOneWidget);
      expect(find.text('24%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'no RAM reading yet');
    });

    testWidgets('do not press anything', (tester) async {
      await tester.pumpWidget(stats());

      await tester.tap(find.text('41°C'));

      expect(pressed, isNull);
    });

    testWidgets('can be added in edit mode', (tester) async {
      await tester.pumpWidget(host(editing: true));

      await tester.tap(find.text('Add button'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Label'),
        'CPU',
      );
      await tester.tap(find.text('Stat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final added = changed!.pages[0].buttons.last.action;
      expect(added, isA<StatAction>());
      expect((added as StatAction).stat, 'cpuLoad');
      expect(added.style, 'number');
    });
  });

  test('readings read naturally on a tile', () {
    expect(formatStat('cpuTemp', 61.26), '61°C');
    expect(formatStat('gpuLoad', 23.6), '24%');
    expect(formatStat('fps', 143.6), '144');
    expect(formatStat('fps', null), '—');
    expect(statMaximum('fps'), 240);
    expect(statMaximum('cpuLoad'), 100);
  });

  test('sim racing readings read like a race dash', () {
    expect(formatStat('gear', -1), 'R');
    expect(formatStat('gear', 0), 'N');
    expect(formatStat('gear', 3), '3');
    expect(formatStat('bestLap', 102.345), '1:42.345');
    expect(formatStat('lapTime', 5.2), '0:05.200');
    expect(formatStat('position', 2), 'P2');
    expect(formatStat('fuel', 41.5), '41.5 L');
    expect(formatStat('speed', 182.4), '182');
    expect(formatStat('tyreFlTemp', 85), '85°C');
    expect(statMaximum('rpm', {'rpmMax': 8500}), 8500);
    expect(statMaximum('rpm'), 9000);
    expect(statMaximum('fuel', {'fuelMax': 65}), 65);
  });
}
