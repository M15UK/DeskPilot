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
  'cpuTemp': 'CPU temperature',
  'fps': 'FPS of the game in front',
  'speed': 'Sim: speed (km/h)',
  'rpm': 'Sim: RPM',
  'gear': 'Sim: gear',
  'fuel': 'Sim: fuel',
  'lap': 'Sim: lap',
  'position': 'Sim: position',
  'lapTime': 'Sim: lap time',
  'lastLap': 'Sim: last lap',
  'bestLap': 'Sim: best lap',
  'tyreFlTemp': 'Sim: front left tyre',
  'tyreFrTemp': 'Sim: front right tyre',
  'tyreRlTemp': 'Sim: rear left tyre',
  'tyreRrTemp': 'Sim: rear right tyre',
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
    {'kind': 'folder', 'buttons': final List<Object?> buttons} =>
      switch (_readAll(buttons, DeckButton.fromJson)) {
        final List<DeckButton> read
            when read.every((button) => button.action is! FolderAction) =>
          FolderAction(read),
        _ => null,
      },
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
/// A button that opens more buttons on the phone, with a way back. Folders
/// don't hold folders.
final class FolderAction extends ButtonAction {
  const FolderAction(this.buttons);

  final List<DeckButton> buttons;

  @override
  Map<String, Object> toJson() => {
    'kind': 'folder',
    'buttons': [for (final button in buttons) button.toJson()],
  };
}

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

/// A button on a page. [icon] names one of the app's icons and [color] one of
/// its colors; left null, the app picks both from what the button does.
/// [size] is one of [buttonSizes], [style] one of [buttonStyles] and [show]
/// one of [buttonShows]; null means the first choice in each.
class DeckButton {
  const DeckButton({
    required this.id,
    required this.label,
    required this.action,
    this.icon,
    this.color,
    this.size,
    this.style,
    this.show,
  });

  final String id;
  final String label;
  final ButtonAction action;
  final String? icon;
  final String? color;
  final String? size;
  final String? style;
  final String? show;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'action': action.toJson(),
    'icon': ?icon,
    'color': ?color,
    'size': ?size,
    'style': ?style,
    'show': ?show,
  };

  DeckButton _withAction(ButtonAction action) => DeckButton(
    id: id,
    label: label,
    action: action,
    icon: icon,
    color: color,
    size: size,
    style: style,
    show: show,
  );

  static DeckButton? fromJson(Object? json) {
    if (json
        case final Map<String, Object?> map &&
            {
              'id': final String id,
              'label': final String label,
              'action': final Object? action,
            }) {
      if (ButtonAction.fromJson(action) case final ButtonAction read) {
        return DeckButton(
          id: id,
          label: label,
          action: read,
          icon: _text(map['icon']),
          color: _text(map['color']),
          size: _text(map['size']),
          style: _text(map['style']),
          show: _text(map['show']),
        );
      }
    }
    return null;
  }
}

/// A page of buttons. [size] is one of [pageSizes] (null: medium), [icon]
/// its icon in the page rail, and [background] one of the button colors.
class DeckPage {
  const DeckPage({
    required this.name,
    required this.buttons,
    this.size,
    this.icon,
    this.background,
  });

  final String name;
  final List<DeckButton> buttons;
  final String? size;
  final String? icon;
  final String? background;

  Map<String, Object> toJson() => {
    'name': name,
    'buttons': [for (final button in buttons) button.toJson()],
    'size': ?size,
    'icon': ?icon,
    'background': ?background,
  };

  static DeckPage? fromJson(Object? json) {
    if (json
        case final Map<String, Object?> map &&
            {
              'name': final String name,
              'buttons': final List<Object?> buttons,
            }) {
      if (_readAll(buttons, DeckButton.fromJson)
          case final List<DeckButton> read) {
        return DeckPage(
          name: name,
          buttons: read,
          size: _text(map['size']),
          icon: _text(map['icon']),
          background: _text(map['background']),
        );
      }
    }
    return null;
  }

  DeckPage _withButtons(List<DeckButton> buttons) => DeckPage(
    name: name,
    buttons: List.unmodifiable(buttons),
    size: size,
    icon: icon,
    background: background,
  );
}

/// Button shapes: one place, two wide, two tall, or two by two.
const buttonSizes = {
  null: 'Normal',
  'wide': 'Wide',
  'tall': 'Tall',
  'big': 'Big',
};

/// Button styles: a soft tint, a solid color, or only an outline.
const buttonStyles = {null: 'Tinted', 'solid': 'Solid', 'outline': 'Outline'};

/// What a button shows: its icon and name, only the icon, or only the name.
const buttonShows = {
  null: 'Icon and name',
  'icon': 'Icon only',
  'name': 'Name only',
};

/// How big a page's buttons are.
const pageSizes = {
  'small': 'Small',
  null: 'Medium',
  'large': 'Large',
  'huge': 'Huge',
};

String? _text(Object? value) => value is String ? value : null;

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

  /// The button with [id], on a page or inside a folder.
  DeckButton? find(String id) {
    for (final page in pages) {
      for (final button in page.buttons) {
        if (button.id == id) return button;
        if (button.action case FolderAction(:final buttons)) {
          for (final inside in buttons) {
            if (inside.id == id) return inside;
          }
        }
      }
    }
    return null;
  }

  /// Puts [button] in place of the button with the same id, on a page or in a
  /// folder, or at the end of page [page] when it is new.
  Deck withButton(int page, DeckButton button) {
    if (find(button.id) == null) {
      return _editPage(page, (p) => p._withButtons([...p.buttons, button]));
    }
    return _editLists(
      (list) => [for (final b in list) b.id == button.id ? button : b],
    );
  }

  /// Adds a new [button] at the end of the folder with the id [folder].
  Deck withButtonInFolder(String folder, DeckButton button) => _editLists(
    (list) => [
      for (final b in list)
        if (b.action case FolderAction(:final buttons) when b.id == folder)
          b._withAction(FolderAction(List.unmodifiable([...buttons, button])))
        else
          b,
    ],
  );

  /// Deletes a button, on a page or in a folder.
  Deck withoutButton(String id) => _editLists(
    (list) => [
      for (final b in list)
        if (b.id != id) b,
    ],
  );

  /// Moves a button [by] places within its page or folder, stopping at either
  /// end.
  Deck movedButton(String id, int by) => _editLists((list) {
    final from = list.indexWhere((b) => b.id == id);
    if (from < 0) return list;
    final to = (from + by).clamp(0, list.length - 1);
    return [...list]
      ..removeAt(from)
      ..insert(to, list[from]);
  });

  Deck withPage(String name) => Deck(
    List.unmodifiable([...pages, DeckPage(name: name, buttons: const [])]),
  );

  /// Changes a page's name and look, keeping its buttons.
  Deck changedPage(
    int page, {
    required String name,
    String? size,
    String? icon,
    String? background,
  }) => _editPage(
    page,
    (p) => DeckPage(
      name: name,
      buttons: p.buttons,
      size: size,
      icon: icon,
      background: background,
    ),
  );

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

  /// Applies [edit] to every page's buttons and every folder's buttons.
  Deck _editLists(List<DeckButton> Function(List<DeckButton>) edit) =>
      _editPages(
        (p) => p._withButtons([
          for (final b in edit(p.buttons))
            if (b.action case FolderAction(:final buttons))
              b._withAction(FolderAction(List.unmodifiable(edit(buttons))))
            else
              b,
        ]),
      );
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

/// The name a button gets when its label is left empty: what it does, like
/// "Next", "Gear" or "acs.exe". At most 40 characters, like any label.
String autoLabel(ButtonAction action) {
  final name = switch (action) {
    MediaAction(:final media) => mediaKeys[media] ?? media,
    KeysAction(:final combos) => combos.join(', '),
    OpenAction(:final target) => _openName(target),
    FolderAction() => 'Folder',
    StatAction(:final stat) => _capitalized(
      (statNames[stat] ?? stat).replaceFirst('Sim: ', ''),
    ),
  };
  return name.length <= 40 ? name : name.substring(0, 40);
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// A website's host, or the last part of a file or folder path.
String _openName(String target) {
  final uri = Uri.tryParse(target);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return uri.host;
  final parts = target.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? target : parts.last;
}
