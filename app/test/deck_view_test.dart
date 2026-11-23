import 'package:deskpilot/deck.dart';
import 'package:deskpilot/deck_view.dart';
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

  Widget host({bool editing = false, bool connected = true}) => MaterialApp(
    home: Scaffold(
      body: DeckView(
        deck: deck,
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

  testWidgets('a button needs a label', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Add button'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Give the button a label'), findsOneWidget);
    expect(changed, isNull);
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
}
