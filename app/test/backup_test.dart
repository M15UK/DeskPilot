import 'dart:convert';
import 'dart:typed_data';

import 'package:deskpilot/backup.dart';
import 'package:deskpilot/deck.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 9]);
  final id = pictureId(png);
  final deck = Deck([
    DeckPage(
      name: 'Racing',
      buttons: [
        DeckButton(
          id: 'pit',
          label: 'Pit',
          action: const KeysAction(['P']),
          image: id,
        ),
        const DeckButton(
          id: 'f',
          label: 'Cameras',
          action: FolderAction([
            DeckButton(id: 'cam', label: 'F1', action: KeysAction(['F1'])),
          ]),
        ),
      ],
    ),
  ]);

  test('a deck backup keeps its buttons and only the pictures it uses', () {
    final text = writeBackup(
      deck: deck,
      pictures: {id: png, '0000000000000000': png},
    );

    final backup = readBackup(text)!;

    expect(jsonEncode(backup.deck!.toJson()), jsonEncode(deck.toJson()));
    expect(backup.page, isNull);
    expect(backup.pictures.keys, [id]);
    expect(backup.pictures[id], png);
  });

  test('a shared page comes in as a new page with fresh button ids', () {
    final backup = readBackup(
      writeBackup(page: deck.pages.single, pictures: {id: png}),
    )!;

    final merged = deck.withImportedPage(backup.page!);

    expect(merged.pages, hasLength(2));
    final added = merged.pages[1].buttons;
    expect(added.first.id, isNot('pit'));
    expect(added.first.image, id);
    final inside = (added.last.action as FolderAction).buttons.single;
    expect(inside.id, isNot('cam'));
    expect(inside.label, 'F1');
  });

  test('refuses files that are not DeskPilot backups', () {
    expect(readBackup('not json'), isNull);
    expect(readBackup('{"hello":"world"}'), isNull);
    expect(readBackup('{"deskpilot":"backup","version":1}'), isNull);
  });

  test('leaves out a picture that does not match its id', () {
    final json = jsonDecode(
      writeBackup(deck: deck, pictures: {id: png}),
    ) as Map<String, Object?>;
    (json['pictures']! as Map<String, Object?>)[id] = base64Encode([1, 2, 3]);

    expect(readBackup(jsonEncode(json))!.pictures, isEmpty);
  });
}
