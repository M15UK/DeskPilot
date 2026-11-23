import 'package:deskpilot/deck.dart';
import 'package:deskpilot/look.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a button keeps the icon and color picked for it', () {
    const button = DeckButton(
      id: 'pit',
      label: 'Pit',
      action: KeysAction(['Ctrl+P']),
      icon: 'flag',
      color: 'amber',
    );

    expect(buttonIcon(button), Icons.flag_rounded);
    expect(buttonColor(button), deckColors['amber']);
  });

  test(
    'a button without its own icon or color takes them from what it does',
    () {
      const next = DeckButton(
        id: 'n',
        label: 'Next',
        action: MediaAction('next'),
      );
      const cpu = DeckButton(
        id: 'c',
        label: 'CPU',
        action: StatAction('cpuLoad', 'gauge'),
      );

      expect(buttonIcon(next), Icons.skip_next_rounded);
      expect(buttonColor(next), deckColors['teal']);
      expect(buttonColor(cpu), deckColors['blue']);
    },
  );

  test(
    'an icon or color this app does not know falls back to the automatic one',
    () {
      const button = DeckButton(
        id: 'm',
        label: 'Mute',
        action: MediaAction('mute'),
        icon: 'rocket_from_the_future',
        color: 'rainbow',
      );

      expect(buttonIcon(button), Icons.volume_off_rounded);
      expect(buttonColor(button), deckColors['teal']);
    },
  );
}
