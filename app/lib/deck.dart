import 'dart:math';

/// The media keys the PC can press, and how the app shows them.
const mediaKeys = {
  'playPause': 'Play / Pause',
  'previous': 'Previous',
  'next': 'Next',
  'volumeDown': 'Volume down',
  'volumeUp': 'Volume up',
  'mute': 'Mute',
};

/// The PC readings a stat tile can show, and how the app names them.
const statNames = {
  'cpuLoad': 'CPU load',
  'gpuLoad': 'GPU load',
  'gpuTemp': 'GPU temperature',
  'ramLoad': 'RAM used',
};

/// How a stat tile shows its reading.
const statStyles = {'number': 'Number', 'gauge': 'Gauge', 'chart': 'Chart'};

/// What a deck button does. The kinds are described in docs/PROTOCOL.md.
sealed class ButtonAction {
  const ButtonAction();

  Map<String, Object> toJson();

  static ButtonAction? fromJson(Object? json) => switch (json) {
    {'kind': 'media', 'media': final String media}
        when mediaKeys.containsKey(media) =>
      MediaAction(media),
    {'kind': 'keys', 'combos': final List<Object?> combos}
        when combos.isNotEmpty && combos.every((combo) => combo is String) =>
      KeysAction(List.unmodifiable(combos.cast<String>())),
    {'kind': 'open', 'target': final String target}
        when target.trim().isNotEmpty =>
      OpenAction(target),
    {'kind': 'stat', 'stat': final String stat, 'style': final String style}
        when statNames.containsKey(stat) && statStyles.containsKey(style) =>
      StatAction(stat, style),
    _ => null,
  };
}

/// A media key, one of [mediaKeys].
final class MediaAction extends ButtonAction {
  const MediaAction(this.media);

  final String media;

  @override
  Map<String, Object> toJson() => {'kind': 'media', 'media': media};
}

/// Key combos pressed one after another, like ['Ctrl+C', 'Alt+Tab'].
final class KeysAction extends ButtonAction {
  const KeysAction(this.combos);

  final List<String> combos;

  @override
  Map<String, Object> toJson() => {'kind': 'keys', 'combos': combos};
}

/// Opens an app, file, folder or link on the PC.
final class OpenAction extends ButtonAction {
  const OpenAction(this.target);

  final String target;

  @override
  Map<String, Object> toJson() => {'kind': 'open', 'target': target};
}

/// A tile that shows a PC reading, one of [statNames], in one of
/// [statStyles]. Tapping it does nothing.
final class StatAction extends ButtonAction {
  const StatAction(this.stat, this.style);

  final String stat;
  final String style;

  @override
  Map<String, Object> toJson() => {
    'kind': 'stat',
    'stat': stat,
    'style': style,
  };
}

class DeckButton {
  const DeckButton({
    required this.id,
    required this.label,
    required this.action,
  });

  final String id;
  final String label;
  final ButtonAction action;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'action': action.toJson(),
  };

  static DeckButton? fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'label': final String label,
      'action': final Object? action,
    }) {
      if (ButtonAction.fromJson(action) case final ButtonAction read) {
        return DeckButton(id: id, label: label, action: read);
      }
    }
    return null;
  }
}

class DeckPage {
  const DeckPage({required this.name, required this.buttons});

  final String name;
  final List<DeckButton> buttons;

  Map<String, Object> toJson() => {
    'name': name,
    'buttons': [for (final button in buttons) button.toJson()],
  };

  static DeckPage? fromJson(Object? json) {
    if (json case {
      'name': final String name,
      'buttons': final List<Object?> buttons,
    }) {
      if (_readAll(buttons, DeckButton.fromJson)
          case final List<DeckButton> read) {
        return DeckPage(name: name, buttons: read);
      }
    }
    return null;
  }

  DeckPage _withButtons(List<DeckButton> buttons) =>
      DeckPage(name: name, buttons: List.unmodifiable(buttons));
}

/// The pages of buttons the PC keeps. Each edit returns a new deck, which the
/// app sends to the PC to check and save.
class Deck {
  const Deck(this.pages);

  final List<DeckPage> pages;

  Map<String, Object> toJson() => {
    'pages': [for (final page in pages) page.toJson()],
  };

  static Deck? fromJson(Object? json) {
    if (json case {'pages': final List<Object?> pages} when pages.isNotEmpty) {
      if (_readAll(pages, DeckPage.fromJson) case final List<DeckPage> read) {
        return Deck(read);
      }
    }
    return null;
  }

  /// Puts [button] in place of the button with the same id, or at the end of
  /// page [page] when it is new.
  Deck withButton(int page, DeckButton button) {
    final exists = pages.any((p) => p.buttons.any((b) => b.id == button.id));
    if (exists) {
      return _editPages(
        (p) => p._withButtons([
          for (final b in p.buttons) b.id == button.id ? button : b,
        ]),
      );
    }
    return _editPage(page, (p) => p._withButtons([...p.buttons, button]));
  }

  Deck withoutButton(String id) => _editPages(
    (p) => p._withButtons([
      for (final b in p.buttons)
        if (b.id != id) b,
    ]),
  );

  /// Moves a button [by] places within its page, stopping at either end.
  Deck movedButton(String id, int by) => _editPages((p) {
    final from = p.buttons.indexWhere((b) => b.id == id);
    if (from < 0) return p;
    final to = (from + by).clamp(0, p.buttons.length - 1);
    final others = [...p.buttons]..removeAt(from);
    return p._withButtons([...others]..insert(to, p.buttons[from]));
  });

  Deck withPage(String name) => Deck(
    List.unmodifiable([...pages, DeckPage(name: name, buttons: const [])]),
  );

  Deck renamedPage(int page, String name) =>
      _editPage(page, (p) => DeckPage(name: name, buttons: p.buttons));

  Deck withoutPage(int page) => Deck(
    List.unmodifiable([
      for (final (index, p) in pages.indexed)
        if (index != page) p,
    ]),
  );

  Deck _editPage(int page, DeckPage Function(DeckPage) edit) => Deck(
    List.unmodifiable([
      for (final (index, p) in pages.indexed) index == page ? edit(p) : p,
    ]),
  );

  Deck _editPages(DeckPage Function(DeckPage) edit) =>
      Deck(List.unmodifiable([for (final p in pages) edit(p)]));
}

/// Reads every item, or returns null when any of them can't be read.
List<T>? _readAll<T>(List<Object?> items, T? Function(Object?) read) {
  final result = <T>[];
  for (final item in items) {
    final value = read(item);
    if (value == null) return null;
    result.add(value);
  }
  return List.unmodifiable(result);
}

final _random = Random.secure();

/// A random id for a new button.
String newButtonId() => [
  for (var i = 0; i < 8; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
