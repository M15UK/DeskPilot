import 'dart:convert';

import 'package:deskpilot/deck.dart';
import 'package:deskpilot/editor.dart';
import 'package:deskpilot/action_picker.dart';
import 'package:deskpilot/deck_view.dart';
import 'package:deskpilot/now_playing.dart';
import 'package:deskpilot/tile_grid.dart';
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

  group('widgets', () {
    const home = Deck([
      DeckPage(
        name: 'Main',
        buttons: [
          DeckButton(
            id: 'm',
            label: 'Music',
            action: MusicAction(),
            size: 'wider',
          ),
          DeckButton(id: 'c', label: 'Clock', action: ClockAction()),
        ],
      ),
    ]);
    final song = NowPlaying(
      title: 'Neon Highway',
      artist: 'The Midnight Drive',
      app: 'Spotify',
      playing: true,
      receivedAt: DateTime(2026),
    );

    testWidgets('show the song and the PC, and the music keys work', (
      tester,
    ) async {
      String? key;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeckView(
              deck: home,
              page: 0,
              editing: false,
              onPress: _ignore,
              onChange: _ignore,
              onPageChanged: _ignore,
              media: song,
              onMediaKey: (pressed) => key = pressed,
              pcName: 'GAMING-PC',
            ),
          ),
        ),
      );

      expect(find.text('Neon Highway'), findsOneWidget);
      expect(find.text('GAMING-PC'), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      expect(key, 'next');
    });

    testWidgets('a music widget is three places wide', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: DeckView(
                deck: home,
                page: 0,
                editing: false,
                onPress: null,
                onChange: _ignore,
                onPageChanged: _ignore,
              ),
            ),
          ),
        ),
      );

      final music = tester.getSize(find.byType(NowPlayingCard));
      final clock = tester.getSize(find.byType(ClockTile));
      expect(music.width, greaterThan(clock.width * 2.5));
    });

    testWidgets('can be added from the editor, with photos', (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeckView(
              deck: deck,
              page: 0,
              editing: true,
              onPress: null,
              onChange: (deck) => changed = deck,
              onPageChanged: _ignore,
              pickPicture: ({required wallpaper}) async => png,
              onPicture: pictureId,
            ),
          ),
        ),
      );

      await pickAction(tester, 'photos', 'Photos');
      await tester.ensureVisible(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final added = changed!.pages[0].buttons.last.action as PhotosAction;
      expect(added.pictures, [pictureId(png)]);
    });
  });

  testWidgets('the page chips switch pages', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('Racing'));

    expect(shownPage, 1);
  });

  testWidgets('adds a key combo button in edit mode', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await pickAction(tester, 'key', 'Key shortcut');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label'),
      'Mute Discord',
    );
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

  testWidgets('Add button sits in the rail, not in the grid', (tester) async {
    await tester.pumpWidget(host(editing: true));

    expect(find.text('Add button'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Add button'),
        matching: find.byType(TileGrid),
      ),
      findsNothing,
    );
  });

  testWidgets('a simple action is added in one tap, named for what it does', (
    tester,
  ) async {
    await tester.pumpWidget(host(editing: true));

    await pickAction(tester, 'cpu load', 'CPU load');

    final added = changed!.pages[0].buttons.last;
    expect(added.label, 'CPU load');
    expect((added.action as StatAction).stat, 'cpuLoad');
    expect(find.byType(ButtonEditor), findsNothing, reason: 'nothing to set');
  });

  testWidgets('the actions list is searchable', (tester) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Add button'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(ActionPicker),
        matching: find.byType(TextField),
      ),
      'tyre',
    );
    await tester.pump();

    final inPicker = find.descendant(
      of: find.byType(ActionPicker),
      matching: find.byType(KeyTile),
    );
    expect(inPicker, findsWidgets);
    expect(
      find.descendant(
        of: find.byType(ActionPicker),
        matching: find.text('Next'),
      ),
      findsNothing,
    );
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
    await openTab(tester, 'Look');
    await tester.ensureVisible(find.byTooltip('flag'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('flag'));
    await tester.ensureVisible(find.byTooltip('amber'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('amber'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = changed!.pages[0].buttons.single;
    expect(saved.icon, 'flag');
    expect(saved.color, 'amber');
  });

  testWidgets('dragging a button puts it in an empty spot and pins the rest', (
    tester,
  ) async {
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
    await drag.moveBy(const Offset(0, 180));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    final first = changed!.find('a')!.fine;
    final second = changed!.find('b')!.fine;
    expect((first.left, first.top), (0, 0), reason: 'pinned where it was');
    expect((second.left, second.top), (8, 8), reason: 'one cell down');
  });

  testWidgets('a button can be wide, solid and show only its icon', (
    tester,
  ) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Play / Pause'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Size');
    await tester.tap(find.text('Wide'));
    await openTab(tester, 'Look');
    for (final choice in ['Solid', 'Icon only']) {
      await tester.ensureVisible(find.text(choice));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pump();
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = changed!.pages[0].buttons.single;
    expect(
      (saved.fine.width, saved.fine.height, saved.style, saved.show),
      (16, 8, 'solid', 'icon'),
    );
  });

  testWidgets('a size made by hand shows as custom, and a shape resets it', (
    tester,
  ) async {
    const sized = Deck([
      DeckPage(
        name: 'Main',
        buttons: [
          DeckButton(
            id: 's',
            label: 'Stretched',
            action: MediaAction('next'),
            x: 1,
            y: 0,
            w: 4,
            h: 2,
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(host(editing: true, shown: sized));

    await tester.tap(find.text('Stretched'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Size');
    await tester.ensureVisible(find.text('Shape (now a custom 4 × 2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = changed!.pages[0].buttons.single;
    final fine = saved.fine;
    expect((fine.width, fine.height, fine.left, fine.top), (8, 8, 8, 0));
    expect(saved.x, isNull, reason: 'now saved in eighths');
  });

  testWidgets('the width slider sets any size, not just whole cells', (
    tester,
  ) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Play / Pause'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Size');
    final width = find.byType(Slider).first;
    await tester.ensureVisible(width);
    await tester.pumpAndSettle();
    await tester.drag(width, const Offset(60, 0));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = changed!.pages[0].buttons.single.fine;
    expect(saved.width, greaterThan(8));
    expect(saved.height, 8);
  });

  testWidgets('an icon only button still says its name to screen readers', (
    tester,
  ) async {
    const iconOnly = Deck([
      DeckPage(
        name: 'Main',
        buttons: [
          DeckButton(
            id: 'n',
            label: 'Next song',
            action: MediaAction('next'),
            show: 'icon',
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(host(shown: iconOnly));

    expect(find.text('Next song'), findsNothing);
    expect(find.bySemanticsLabel('Next song'), findsOneWidget);
  });

  testWidgets('page settings change the button size and background', (
    tester,
  ) async {
    await tester.pumpWidget(host(editing: true));

    await tester.tap(find.text('Page settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large'));
    await tester.ensureVisible(find.byTooltip('purple').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('purple').last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final main = changed!.pages[0];
    expect(
      (main.name, main.size, main.background),
      ('Main', 'large', 'purple'),
    );
    expect(main.buttons, hasLength(1));
  });

  group('folders', () {
    const withFolder = Deck([
      DeckPage(
        name: 'Main',
        buttons: [
          DeckButton(
            id: 'f',
            label: 'Streaming',
            action: FolderAction([
              DeckButton(
                id: 'rec',
                label: 'Record',
                action: KeysAction(['Ctrl+F9']),
              ),
            ]),
          ),
        ],
      ),
    ]);

    Widget folderHost({bool editing = false, String? open}) => MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => DeckView(
            deck: withFolder,
            page: 0,
            editing: editing,
            onPress: (id) => pressed = id,
            onChange: (deck) => changed = deck,
            onPageChanged: _ignore,
            folder: open,
            onFolderChanged: (id) => setState(() => open = id),
          ),
        ),
      ),
    );

    testWidgets('open on a tap, press what is inside, and close with Back', (
      tester,
    ) async {
      await tester.pumpWidget(folderHost());

      await tester.tap(find.text('Streaming'));
      await tester.pump();
      await tester.tap(find.text('Record'));
      expect(pressed, 'rec');
      await tester.tap(find.text('Back'));
      await tester.pump();

      expect(find.text('Streaming'), findsOneWidget);
      expect(find.text('Record'), findsNothing);
    });

    testWidgets('get new buttons added inside them in edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(folderHost(editing: true, open: 'f'));

      await tester.tap(find.text('Add button'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ActionPicker),
          matching: find.text('Folder'),
        ),
        findsNothing,
        reason: 'no folder in a folder',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ActionPicker),
          matching: find.text('Next'),
        ),
      );
      await tester.pumpAndSettle();

      final folder = changed!.pages[0].buttons.single.action as FolderAction;
      expect(folder.buttons, hasLength(2));
    });

    testWidgets('can be made from the editor', (tester) async {
      await tester.pumpWidget(host(editing: true));

      await pickAction(tester, 'folder', 'Folder');

      expect(changed!.pages[0].buttons.last.action, isA<FolderAction>());
    });
  });

  testWidgets('puts your own picture on a button', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );
    String? uploaded;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeckView(
            deck: deck,
            page: 0,
            editing: true,
            onPress: null,
            onChange: (deck) => changed = deck,
            onPageChanged: _ignore,
            pickPicture: ({required wallpaper}) async => png,
            onPicture: (bytes) => uploaded = pictureId(bytes),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Play / Pause'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Look');
    await tester.ensureVisible(find.text('Choose picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(uploaded, hasLength(16));
    expect(changed!.pages[0].buttons.single.image, uploaded);
  });

  testWidgets('page settings share the page', (tester) async {
    int? shared;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeckView(
            deck: deck,
            page: 0,
            editing: true,
            onPress: null,
            onChange: _ignore,
            onPageChanged: _ignore,
            onSharePage: (page) => shared = page,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Page settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share this page'));
    await tester.pumpAndSettle();

    expect(shared, 0);
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

      await pickAction(tester, 'gpu temp', 'GPU temperature');

      final added = changed!.pages[0].buttons.last.action;
      expect(added, isA<StatAction>());
      expect((added as StatAction).stat, 'gpuTemp');
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

  test('racing page readings read naturally', () {
    expect(formatStat('delta', -0.214), '−0.214');
    expect(formatStat('delta', 0.5), '+0.500');
    expect(formatStat('tyreFlPressure', 27.6), '27.6 psi');
    expect(formatStat('flag', 2), 'Yellow');
    expect(formatStat('flag', 0), 'None');
    expect(formatStat('pitLimiter', 1), 'On');
    expect(formatStat('lapsOfFuel', 11.6), '11.6 laps');
    expect(formatStat('fuelToFinish', 4.3), '+4.3 L');
    expect(formatStat('sector', 2), 'S2');
  });

  testWidgets('the tyres tile shows each tyre and its pressure', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 300,
            child: TyresTile(
              stats: {
                'tyreFlTemp': 84,
                'tyreFrTemp': 97,
                'tyreRlTemp': 68,
                'tyreRrTemp': 86,
                'tyreFlPressure': 27.6,
                'tyreRrPressure': 27.3,
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('84°'), findsOneWidget);
    expect(find.text('97°'), findsOneWidget);
    expect(find.text('27.6'), findsOneWidget);
    expect(find.text('27.3'), findsOneWidget);
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

void _ignore(Object? _) {}

/// Opens the actions list, searches it, and picks [name].
Future<void> pickAction(WidgetTester tester, String search, String name) async {
  await tester.tap(find.text('Add button'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(ActionPicker),
      matching: find.byType(TextField),
    ),
    search,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(ActionPicker), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

/// Switches the button editor to its [name] tab.
Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(Tab, name));
  await tester.pumpAndSettle();
}
