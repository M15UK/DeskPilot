import 'dart:convert';
import 'dart:typed_data';

import 'package:deskpilot/deck.dart';
import 'package:deskpilot/pictures.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

const _version = 1;

/// A deck or one page saved to a file with the pictures it uses, to keep as
/// a backup or to send to a friend.
class Backup {
  const Backup({this.deck, this.page, this.pictures = const {}});

  /// A whole deck, which replaces the one on the PC.
  final Deck? deck;

  /// One page, which is added to the deck on the PC.
  final DeckPage? page;
  final Map<String, Uint8List> pictures;
}

/// The file for a [deck] or a [page], with the [pictures] it uses.
String writeBackup({
  Deck? deck,
  DeckPage? page,
  required Map<String, Uint8List> pictures,
}) {
  final used = (deck ?? Deck([?page])).pictureIds;
  return const JsonEncoder.withIndent('  ').convert({
    'deskpilot': 'backup',
    'version': _version,
    if (deck != null) 'deck': deck.toJson(),
    if (page != null) 'page': page.toJson(),
    'pictures': {
      for (final id in used)
        if (pictures[id] case final bytes?) id: base64Encode(bytes),
    },
  });
}

/// Reads a backup file, or null when it isn't one this app can use. A
/// picture that doesn't match its id or is too big is left out.
Backup? readBackup(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json
      case final Map<String, Object?> map &&
          {'deskpilot': 'backup', 'version': final int version}
      when version <= _version) {
    final deck = map['deck'] == null ? null : Deck.fromJson(map['deck']);
    final page = map['page'] == null ? null : DeckPage.fromJson(map['page']);
    if ((deck == null) == (page == null)) return null;
    return Backup(deck: deck, page: page, pictures: _pictures(map['pictures']));
  }
  return null;
}

Map<String, Uint8List> _pictures(Object? json) {
  if (json is! Map<String, Object?>) return const {};
  final pictures = <String, Uint8List>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (value is! String) continue;
    try {
      final bytes = base64Decode(value);
      if (bytes.length <= maxPictureBytes && pictureId(bytes) == key) {
        pictures[key] = bytes;
      }
    } on FormatException {
      continue; // a damaged picture: the button shows its icon instead
    }
  }
  return Map.unmodifiable(pictures);
}

/// Opens the phone's share sheet with the backup as a file, to save it or
/// send it to someone.
Future<void> shareBackup(String text, String fileName) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(utf8.encode(text), mimeType: 'application/json')],
      fileNameOverrides: [fileName],
    ),
  );
}

/// Lets you pick a backup file. Returns its text, or null when nothing was
/// picked.
Future<String?> pickBackup() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (file == null) return null;
  return utf8.decode(await file.readAsBytes(), allowMalformed: true);
}
