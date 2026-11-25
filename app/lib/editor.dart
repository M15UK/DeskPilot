import 'dart:typed_data';

import 'package:deskpilot/choices.dart';
import 'package:deskpilot/deck.dart';
import 'package:deskpilot/look.dart';
import 'package:deskpilot/now_playing.dart';
import 'package:deskpilot/pictures.dart';
import 'package:deskpilot/tiles.dart';
import 'package:flutter/material.dart';

// Same limit as Deck.MaxTextLength on the PC.
const _maxTextLength = 40;

String? _required(String? text, String message) =>
    (text == null || text.trim().isEmpty) ? message : null;

/// What the button editor decided.
sealed class ButtonEdit {
  const ButtonEdit();
}

final class SaveButton extends ButtonEdit {
  const SaveButton(this.button);

  final DeckButton button;
}

final class DeleteButton extends ButtonEdit {
  const DeleteButton(this.id);

  final String id;
}

/// Open the folder [id] to change the buttons inside it.
final class OpenFolder extends ButtonEdit {
  const OpenFolder(this.id);

  final String id;
}

final class MoveButton extends ButtonEdit {
  const MoveButton(this.id, this.by);

  final String id;
  final int by;
}

/// Adds a new button, or changes, moves or deletes [button].
class ButtonEditor extends StatefulWidget {
  const ButtonEditor({
    super.key,
    this.button,
    this.canBeFolder = true,
    this.pictures = const {},
    this.pickPicture,
    this.onPicture,
  });

  final DeckButton? button;

  /// False inside a folder: folders don't hold folders.
  final bool canBeFolder;

  /// Pictures the phone already has, by id.
  final Map<String, Uint8List> pictures;

  /// Picks a photo; the phone's gallery when null.
  final PickPicture? pickPicture;

  /// Sends a picked photo to the PC and returns its id. Null hides pictures,
  /// for example while the PC isn't connected.
  final String Function(Uint8List)? onPicture;

  @override
  State<ButtonEditor> createState() => _ButtonEditorState();
}

class _ButtonEditorState extends State<ButtonEditor> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.button?.label);
  late final _combos = TextEditingController(
    text: switch (widget.button?.action) {
      KeysAction(:final combos) => combos.join(', '),
      _ => '',
    },
  );
  late final _target = TextEditingController(
    text: switch (widget.button?.action) {
      OpenAction(:final target) => target,
      _ => '',
    },
  );
  late String _kind = switch (widget.button?.action) {
    KeysAction() => 'keys',
    OpenAction() => 'open',
    StatAction() => 'stat',
    FolderAction() => 'folder',
    MusicAction() || ClockAction() || PhotosAction() => 'widget',
    _ => 'media',
  };
  late String _widget = switch (widget.button?.action) {
    ClockAction() => 'clock',
    PhotosAction() => 'photos',
    _ => 'music',
  };
  late List<String> _photos = switch (widget.button?.action) {
    PhotosAction(:final pictures) => pictures,
    _ => const [],
  };
  Map<String, Uint8List> _photoBytes = const {};
  String? _photoProblem;
  late String _stat = switch (widget.button?.action) {
    StatAction(:final stat) => stat,
    _ => 'cpuLoad',
  };
  late String _style = switch (widget.button?.action) {
    StatAction(:final style) => style,
    _ => 'number',
  };
  late String _media = switch (widget.button?.action) {
    MediaAction(:final media) => media,
    _ => 'playPause',
  };
  // Null means automatic: picked from what the button does.
  late String? _icon = widget.button?.icon;
  late String? _color = widget.button?.color;
  // The size in cells; a shape chip sets it, and a size made by hand on the
  // deck shows as custom.
  late (int, int) _cells = widget.button?.span ?? (1, 1);

  /// The shape chip for [_cells], or a missing key when it's a custom size.
  String? get _shape => _cells == (1, 1)
      ? null
      : shapeSpans.entries
                .where((entry) => entry.value == _cells)
                .map((entry) => entry.key)
                .firstOrNull ??
            'custom';
  late String? _look = widget.button?.style;
  late String? _show = widget.button?.show;
  late String? _image = widget.button?.image;
  Uint8List? _picked;

  Uint8List? get _picture =>
      _image == null ? null : _picked ?? widget.pictures[_image];

  @override
  void dispose() {
    _label.dispose();
    _combos.dispose();
    _target.dispose();
    super.dispose();
  }

  ButtonAction _action() => switch (_kind) {
    'keys' => KeysAction(
      List.unmodifiable(
        _combos.text
            .split(',')
            .map((combo) => combo.trim())
            .where((combo) => combo.isNotEmpty),
      ),
    ),
    'open' => OpenAction(_target.text.trim()),
    'stat' => StatAction(_stat, _style),
    'folder' => FolderAction(switch (widget.button?.action) {
      FolderAction(:final buttons) => buttons,
      _ => const [],
    }),
    'widget' => switch (_widget) {
      'clock' => const ClockAction(),
      'photos' => PhotosAction(List.unmodifiable(_photos)),
      _ => const MusicAction(),
    },
    _ => MediaAction(_media),
  };

  /// The photos of a photo widget that the phone has, in order.
  List<Uint8List> get _photoPictures => [
    for (final id in _photos) ?(_photoBytes[id] ?? widget.pictures[id]),
  ];

  Future<void> _addPhoto() async {
    final upload = widget.onPicture;
    if (upload == null) return;
    final bytes = await (widget.pickPicture ?? pickFromGallery)(
      wallpaper: true,
    );
    if (bytes == null || !mounted) return;
    if (bytes.length > maxPictureBytes) {
      setState(() => _photoProblem = 'That photo is too big. Pick another.');
      return;
    }
    final id = upload(bytes);
    setState(() {
      _photoProblem = null;
      _photos = [..._photos, id];
      _photoBytes = {..._photoBytes, id: bytes};
    });
  }

  /// The photos in a photo widget, each with a way to take it out, and a
  /// button to add more.
  Widget _photosField() {
    final problem = _photoProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, id) in _photos.indexed)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.square(
                      dimension: 64,
                      child: switch (_photoBytes[id] ?? widget.pictures[id]) {
                        final Uint8List bytes => Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        null => const Icon(Icons.photo_rounded),
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filledTonal(
                      tooltip: 'Take out photo ${index + 1}',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => setState(
                        () => _photos = [..._photos]..removeAt(index),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (widget.onPicture != null && _photos.length < 30)
          OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('Add photo'),
          ),
        if (problem != null)
          Text(problem, style: TextStyle(color: deckColors['red'])),
      ],
    );
  }

  /// How many buttons the folder being edited holds, or null when it isn't
  /// a folder.
  int? get _folderButtons => switch (widget.button?.action) {
    FolderAction(:final buttons) => buttons.length,
    _ => null,
  };

  DeckButton _button(String id) {
    final action = _action();
    final label = _label.text.trim();
    // Widgets draw themselves; stat tiles always show their reading one way.
    final widgetTile = _kind == 'widget';
    final plain = widgetTile || action is StatAction;
    return DeckButton(
      id: id,
      label: label.isEmpty ? autoLabel(action) : label,
      action: action,
      icon: widgetTile ? null : _icon,
      color: widgetTile ? null : _color,
      // The place stays; the size is in cells (1 by 1 needs no saying).
      x: widget.button?.x,
      y: widget.button?.y,
      w: _cells == (1, 1) ? null : _cells.$1,
      h: _cells == (1, 1) ? null : _cells.$2,
      style: plain ? null : _look,
      show: plain ? null : _show,
      image: plain ? null : _image,
    );
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final button = _button(widget.button?.id ?? newButtonId());
    Navigator.of(context).pop(SaveButton(button));
  }

  /// The button as it will look on the deck, updated as you edit.
  Widget _preview() {
    final button = _button('preview');
    return Center(
      child: SizedBox.square(
        dimension: 120,
        child: switch (button.action) {
          MusicAction() => const NowPlayingCard(media: null, onKey: null),
          ClockAction() => const ClockTile(pcName: null, stats: {}),
          PhotosAction() => PhotosTile(pictures: _photoPictures),
          final StatAction stat => StatTile(
            label: button.label,
            action: stat,
            value: null,
            maximum: statMaximum(stat.stat),
            history: const [],
            color: buttonColor(button),
          ),
          _ => KeyTile(
            icon: buttonIcon(button),
            label: button.label,
            color: buttonColor(button),
            style: button.style,
            show: button.show,
            picture: _picture,
            onTap: () {},
          ),
        },
      ),
    );
  }

  Widget _iconPicker() => ChoiceRow(
    title: 'Icon',
    choices: [
      ChoiceSquare(
        name: 'Automatic',
        selected: _icon == null,
        onTap: () => setState(() => _icon = null),
        child: const Icon(Icons.auto_awesome_rounded),
      ),
      for (final MapEntry(:key, :value) in deckIcons.entries)
        ChoiceSquare(
          name: key.replaceAll('_', ' '),
          selected: _icon == key,
          onTap: () => setState(() => _icon = key),
          child: Icon(value),
        ),
    ],
  );

  Widget _colorPicker() => ChoiceRow(
    title: 'Color',
    choices: [
      ChoiceSquare(
        name: 'Automatic',
        selected: _color == null,
        onTap: () => setState(() => _color = null),
        child: const Icon(Icons.auto_awesome_rounded),
      ),
      for (final MapEntry(:key, :value) in deckColors.entries)
        ChoiceSquare(
          name: key,
          selected: _color == key,
          onTap: () => setState(() => _color = key),
          child: CircleAvatar(radius: 11, backgroundColor: value),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final button = widget.button;
    return AlertDialog(
      title: Text(button == null ? 'New button' : 'Edit button'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              _preview(),
              TextFormField(
                controller: _label,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Label',
                  hintText: autoLabel(_action()),
                  helperText: 'Leave empty to use the name shown',
                ),
                maxLength: _maxTextLength,
              ),
              // A folder with buttons in it stays a folder, so they can't be
              // lost by picking another kind by mistake.
              if (_folderButtons case final count? when count > 0)
                Text(
                  'This folder holds $count buttons. Open it to change them, '
                  'or delete it to remove them all.',
                )
              else
                OptionChips(
                  title: 'Type',
                  choices: {
                    'media': 'Media',
                    'keys': 'Keys',
                    'open': 'Open',
                    'stat': 'Stat',
                    if (widget.canBeFolder) 'folder': 'Folder',
                    'widget': 'Widget',
                  },
                  selected: _kind,
                  onSelect: (kind) => setState(() => _kind = kind ?? _kind),
                ),
              switch (_kind) {
                'widget' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    OptionChips(
                      title: 'Widget',
                      choices: const {
                        'music': 'Music',
                        'clock': 'Clock',
                        'photos': 'Photos',
                      },
                      selected: _widget,
                      onSelect: (picked) => setState(() {
                        _widget = picked ?? _widget;
                        // Music reads best wide; pick another shape any time.
                        if (_widget == 'music' && _cells == (1, 1)) {
                          _cells = (3, 1);
                        }
                      }),
                    ),
                    if (_widget == 'photos')
                      _photosField()
                    else
                      const Text(
                        'It shows on its own. Drag it where you like and pick '
                        'its shape below.',
                      ),
                  ],
                ),
                'folder' => const Text(
                  'Tap the folder on your deck to open it. To add buttons, '
                  'open it from here in edit mode.',
                ),
                'keys' => TextFormField(
                  controller: _combos,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Key combos',
                    helperText:
                        'Like Ctrl+Shift+M. Separate several with commas.',
                  ),
                  validator: (text) =>
                      _required(text, 'Type at least one key combo'),
                ),
                'open' => TextFormField(
                  controller: _target,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'App, file, folder or link',
                    helperText: r'Like C:\Games\game.exe or https://…',
                  ),
                  validator: (text) =>
                      _required(text, 'Type what the button opens'),
                ),
                'stat' => Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _stat,
                      decoration: const InputDecoration(labelText: 'Reading'),
                      items: [
                        for (final MapEntry(:key, :value) in statNames.entries)
                          DropdownMenuItem(value: key, child: Text(value)),
                      ],
                      onChanged: (stat) =>
                          setState(() => _stat = stat ?? _stat),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _style,
                      decoration: const InputDecoration(
                        labelText: 'Show it as',
                      ),
                      items: [
                        for (final MapEntry(:key, :value) in statStyles.entries)
                          DropdownMenuItem(value: key, child: Text(value)),
                      ],
                      onChanged: (style) =>
                          setState(() => _style = style ?? _style),
                    ),
                  ],
                ),
                _ => DropdownButtonFormField<String>(
                  initialValue: _media,
                  decoration: const InputDecoration(labelText: 'Media key'),
                  items: [
                    for (final MapEntry(:key, :value) in mediaKeys.entries)
                      DropdownMenuItem(value: key, child: Text(value)),
                  ],
                  onChanged: (media) =>
                      setState(() => _media = media ?? _media),
                ),
              },
              if (_kind != 'stat' && _kind != 'widget') _iconPicker(),
              if (_kind != 'widget') _colorPicker(),
              if (widget.onPicture case final upload?
                  when _kind != 'stat' && _kind != 'widget')
                PictureField(
                  noun: 'picture',
                  wallpaper: false,
                  picture: _picture,
                  chosen: _image != null,
                  pick: widget.pickPicture ?? pickFromGallery,
                  upload: upload,
                  onChanged: (id, bytes) => setState(() {
                    _image = id;
                    _picked = bytes;
                  }),
                ),
              OptionChips(
                title: _shape == 'custom'
                    ? 'Shape (now a custom ${_cells.$1} by ${_cells.$2})'
                    : 'Shape',
                choices: buttonSizes,
                selected: _shape,
                onSelect: (shape) =>
                    setState(() => _cells = shapeSpans[shape] ?? (1, 1)),
              ),
              if (_kind != 'stat' && _kind != 'widget') ...[
                OptionChips(
                  title: 'Style',
                  choices: buttonStyles,
                  selected: _look,
                  onSelect: (look) => setState(() => _look = look),
                ),
                OptionChips(
                  title: 'Show',
                  choices: buttonShows,
                  selected: _show,
                  onSelect: (show) => setState(() => _show = show),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (button != null && button.action is FolderAction)
          TextButton(
            onPressed: () => Navigator.of(context).pop(OpenFolder(button.id)),
            child: const Text('Open folder'),
          ),
        if (button != null) ...[
          IconButton(
            tooltip: 'Move left',
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                Navigator.of(context).pop(MoveButton(button.id, -1)),
          ),
          IconButton(
            tooltip: 'Move right',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () =>
                Navigator.of(context).pop(MoveButton(button.id, 1)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(DeleteButton(button.id)),
            child: const Text('Delete'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// What the page editor decided.
sealed class PageEdit {
  const PageEdit();
}

/// The page's name and look, to save.
final class SavePage extends PageEdit {
  const SavePage({
    required this.name,
    this.size,
    this.icon,
    this.background,
    this.wallpaper,
  });

  final String name;
  final String? size;
  final String? icon;
  final String? background;
  final String? wallpaper;
}

final class DeletePage extends PageEdit {
  const DeletePage();
}

/// Names a new page, or changes or deletes [page]: its name, button size,
/// icon and background.
class PageEditor extends StatefulWidget {
  const PageEditor({
    super.key,
    required this.title,
    this.page,
    this.canDelete = false,
    this.pictures = const {},
    this.pickPicture,
    this.onPicture,
    this.onShare,
  });

  final String title;
  final DeckPage? page;
  final bool canDelete;

  /// Shares this page as a file; null for a new page.
  final VoidCallback? onShare;
  final Map<String, Uint8List> pictures;
  final PickPicture? pickPicture;
  final String Function(Uint8List)? onPicture;

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.page?.name);
  late String? _size = widget.page?.size;
  late String? _icon = widget.page?.icon;
  late String? _background = widget.page?.background;
  late String? _wallpaper = widget.page?.wallpaper;
  Uint8List? _picked;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      SavePage(
        name: _name.text.trim(),
        size: _size,
        icon: _icon,
        background: _background,
        wallpaper: _wallpaper,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.page == null,
              maxLength: _maxTextLength,
              decoration: const InputDecoration(labelText: 'Page name'),
              validator: (text) => _required(text, 'Give the page a name'),
              onFieldSubmitted: (_) => _save(),
            ),
            OptionChips(
              title: 'Button size',
              choices: pageSizes,
              selected: _size,
              onSelect: (size) => setState(() => _size = size),
            ),
            ChoiceRow(
              title: 'Icon',
              choices: [
                ChoiceSquare(
                  name: 'Automatic',
                  selected: _icon == null,
                  onTap: () => setState(() => _icon = null),
                  child: const Icon(Icons.auto_awesome_rounded),
                ),
                for (final MapEntry(:key, :value) in deckIcons.entries)
                  ChoiceSquare(
                    name: key.replaceAll('_', ' '),
                    selected: _icon == key,
                    onTap: () => setState(() => _icon = key),
                    child: Icon(value),
                  ),
              ],
            ),
            ChoiceRow(
              title: 'Background',
              choices: [
                ChoiceSquare(
                  name: 'None',
                  selected: _background == null,
                  onTap: () => setState(() => _background = null),
                  child: const Icon(Icons.block_rounded),
                ),
                for (final MapEntry(:key, :value) in deckColors.entries)
                  ChoiceSquare(
                    name: key,
                    selected: _background == key,
                    onTap: () => setState(() => _background = key),
                    child: CircleAvatar(radius: 11, backgroundColor: value),
                  ),
              ],
            ),
            if (widget.onPicture case final upload?)
              PictureField(
                noun: 'wallpaper',
                wallpaper: true,
                picture: _wallpaper == null
                    ? null
                    : _picked ?? widget.pictures[_wallpaper],
                chosen: _wallpaper != null,
                pick: widget.pickPicture ?? pickFromGallery,
                upload: upload,
                onChanged: (id, bytes) => setState(() {
                  _wallpaper = id;
                  _picked = bytes;
                }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.onShare case final share?)
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            share();
          },
          child: const Text('Share this page'),
        ),
      if (widget.canDelete)
        TextButton(
          onPressed: () => Navigator.of(context).pop(const DeletePage()),
          child: const Text('Delete page'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
