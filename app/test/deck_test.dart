import 'dart:convert';

import 'package:deskpilot/deck.dart';
import 'package:flutter_test/flutter_test.dart';

// A deck exactly as the PC agent sends it.
const pcDeck =
    '{"pages":[{"name":"Main","buttons":['
    '{"id":"previous","label":"Previous","action":{"kind":"media","media":"previous"}},'
    '{"id":"play-pause","label":"Play / Pause","action":{"kind":"media","media":"playPause"}},'
    '{"id":"pit","label":"Pit","action":{"kind":"keys","combos":["Ctrl+P","Enter"]}},'
    '{"id":"ac","label":"Assetto Corsa","action":{"kind":"open","target":"steam://rungameid/244210"}}'
    ']}]}';

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

    expect(ids(deck), ['previous', 'play-pause', 'pit', 'ac']);
    expect(deck.pages[0].buttons[2].label, 'Box box');
  });

  test('moves and deletes buttons', () {
    expect(ids(sample().movedButton('pit', -1)), [
      'previous',
      'pit',
      'play-pause',
      'ac',
    ]);
    expect(ids(sample().movedButton('ac', 1)), [
      'previous',
      'play-pause',
      'pit',
      'ac',
    ]);
    expect(ids(sample().withoutButton('pit')), [
      'previous',
      'play-pause',
      'ac',
    ]);
  });

  test('adds, renames and deletes pages', () {
    final deck = sample().withPage('Racing').renamedPage(1, 'Sim racing');

    expect([for (final page in deck.pages) page.name], ['Main', 'Sim racing']);
    expect(deck.withoutPage(0).pages.single.name, 'Sim racing');
  });

  test('new button ids are unique', () {
    expect({for (var i = 0; i < 100; i++) newButtonId()}, hasLength(100));
  });
}
