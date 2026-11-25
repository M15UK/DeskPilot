import 'dart:convert';
import 'dart:typed_data';

import 'package:deskpilot/deck.dart';
import 'package:flutter_test/flutter_test.dart';

// A deck exactly as the PC agent sends it.
const pcDeck =
    '{"pages":[{"name":"Main","buttons":['
    '{"id":"previous","label":"Previous","action":{"kind":"media","media":"previous"}},'
    '{"id":"play-pause","label":"Play / Pause","action":{"kind":"media","media":"playPause"}},'
    '{"id":"pit","label":"Pit","action":{"kind":"keys","combos":["Ctrl+P","Enter"]},"icon":"flag","color":"amber","show":"icon","image":"0123456789abcdef"},'
    '{"id":"ac","label":"Assetto Corsa","action":{"kind":"open","target":"steam://rungameid/244210"}},'
    '{"id":"cpu","label":"CPU","action":{"kind":"stat","stat":"cpuLoad","style":"gauge"},"size":"wide","style":"outline"}'
    '],"size":"large","icon":"home","background":"blue","wallpaper":"fedcba9876543210"}]}';

Deck sample() => Deck.fromJson(jsonDecode(pcDeck))!;

List<String> ids(Deck deck, [int page = 0]) => [
  for (final button in deck.pages[page].buttons) button.id,
];

void main() {
  test('reads the deck the PC sends and writes it back the same', () {
    final deck = sample();

    expect(deck.pages.single.name, 'Main');
    expect(deck.pages.single.buttons[2].action, isA<KeysAction>());
    expect((deck.pages.single.buttons[2].action as KeysAction).combos, [
      'Ctrl+P',
      'Enter',
    ]);
    expect(jsonEncode(deck.toJson()), pcDeck);
  });

  test('refuses decks it cannot show', () {
    final broken = {
      'no pages': '{}',
      'an unknown action': '{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"shell","command":"x"}}]}]}',
      'combos that are not text': '{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"keys","combos":[1]}}]}]}',
      'an unknown stat': '{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"stat","stat":"cpuSpeed","style":"gauge"}}]}]}',
      'a button without a label': '{"pages":[{"name":"Main","buttons":[{"id":"a","action":{"kind":"media","media":"next"}}]}]}',
    };
    broken.forEach((what, json) {
      expect(Deck.fromJson(jsonDecode(json)), isNull, reason: what);
    });
  });

  test('adds a new button to the end of a page', () {
    const button = DeckButton(
      id: 'new',
      label: 'New',
      action: MediaAction('mute'),
    );

    expect(ids(sample().withButton(0, button)), [
      'previous',
      'play-pause',
      'pit',
      'ac',
      'cpu',
      'new',
    ]);
  });

  test('replaces a button with the same id in place', () {
    const renamed = DeckButton(
      id: 'pit',
      label: 'Box box',
      action: KeysAction(['P']),
    );

    final deck = sample().withButton(0, renamed);

    expect(ids(deck), ['previous', 'play-pause', 'pit', 'ac', 'cpu']);
    expect(deck.pages[0].buttons[2].label, 'Box box');
  });

  test('moves and deletes buttons', () {
    expect(ids(sample().movedButton('pit', -1)), [
      'previous',
      'pit',
      'play-pause',
      'ac',
      'cpu',
    ]);
    expect(ids(sample().movedButton('cpu', 1)), [
      'previous',
      'play-pause',
      'pit',
      'ac',
      'cpu',
    ]);
    expect(ids(sample().withoutButton('pit')), [
      'previous',
      'play-pause',
      'ac',
      'cpu',
    ]);
  });

  test('adds, renames and deletes pages', () {
    final deck = sample().withPage('Racing').changedPage(1, name: 'Sim racing');

    expect([for (final page in deck.pages) page.name], ['Main', 'Sim racing']);
    expect(deck.withoutPage(0).pages.single.name, 'Sim racing');
  });

  test('a page keeps its button size through button edits', () {
    final deck = sample()
        .changedPage(0, name: 'Home', size: 'small')
        .withoutButton('pit')
        .movedButton('cpu', -1);

    expect(deck.pages[0].name, 'Home');
    expect(deck.pages[0].size, 'small');
    expect(deck.pages[0].buttons[2].size, 'wide');
  });

  test('reads a folder the PC sends and writes it back the same', () {
    const json =
        '{"pages":[{"name":"Main","buttons":[{"id":"f","label":"Streaming",'
        '"action":{"kind":"folder","buttons":[{"id":"obs","label":"OBS",'
        '"action":{"kind":"open","target":"obs64.exe"}}]}}]}]}';

    final deck = Deck.fromJson(jsonDecode(json))!;

    expect(jsonEncode(deck.toJson()), json);
    expect(
      (deck.pages[0].buttons[0].action as FolderAction).buttons.single.id,
      'obs',
    );
  });

  test('refuses a folder inside a folder', () {
    const json =
        '{"pages":[{"name":"Main","buttons":[{"id":"f","label":"F",'
        '"action":{"kind":"folder","buttons":[{"id":"g","label":"G",'
        '"action":{"kind":"folder","buttons":[]}}]}}]}]}';

    expect(Deck.fromJson(jsonDecode(json)), isNull);
  });

  test('adds, moves and deletes buttons inside a folder', () {
    const a = DeckButton(id: 'a', label: 'A', action: MediaAction('next'));
    const b = DeckButton(id: 'b', label: 'B', action: MediaAction('mute'));
    final deck = sample()
        .withButton(
          0,
          const DeckButton(id: 'f', label: 'F', action: FolderAction([])),
        )
        .withButtonInFolder('f', a)
        .withButtonInFolder('f', b)
        .movedButton('b', -1);
    List<String> inside(Deck deck) => [
      for (final button
          in (deck.pages[0].buttons.last.action as FolderAction).buttons)
        button.id,
    ];

    expect(inside(deck), ['b', 'a']);
    expect(inside(deck.withoutButton('a')), ['b']);
    expect(
      inside(
        deck.withButton(
          0,
          const DeckButton(
            id: 'a',
            label: 'Renamed',
            action: MediaAction('next'),
          ),
        ),
      ),
      ['b', 'a'],
      reason: 'an edited button stays inside its folder',
    );
  });

  test('a picture id is the start of its SHA-256, like on the PC', () {
    // The same bytes and id as ImageStoreTests on the PC.
    expect(
      pictureId(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])),
      matches(RegExp(r'^[0-9a-f]{16}$')),
    );
    expect(pictureId(Uint8List.fromList([1, 2, 3])), '039058c6f2c0cb49');
  });

  test('new button ids are unique', () {
    expect({for (var i = 0; i < 100; i++) newButtonId()}, hasLength(100));
  });
}
