import 'package:deskpilot/deck.dart';
import 'package:deskpilot/look.dart';
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

final class MoveButton extends ButtonEdit {
  const MoveButton(this.id, this.by);

  final String id;
  final int by;
}

/// Adds a new button, or changes, moves or deletes [button].
class ButtonEditor extends StatefulWidget {
  const ButtonEditor({super.key, this.button});

  final DeckButton? button;

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
    _ => 'media',
  };
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
    _ => MediaAction(_media),
  };

  DeckButton _button(String id) {
    final action = _action();
    final label = _label.text.trim();
    return DeckButton(
      id: id,
      label: label.isEmpty ? autoLabel(action) : label,
      action: action,
      icon: _icon,
      color: _color,
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
            onTap: () {},
          ),
        },
      ),
    );
  }

  Widget _iconPicker() => _Choices(
    title: 'Icon',
    choices: [
      _Choice(
        name: 'Automatic',
        selected: _icon == null,
        onTap: () => setState(() => _icon = null),
        child: const Icon(Icons.auto_awesome_rounded),
      ),
      for (final MapEntry(:key, :value) in deckIcons.entries)
        _Choice(
          name: key.replaceAll('_', ' '),
          selected: _icon == key,
          onTap: () => setState(() => _icon = key),
          child: Icon(value),
        ),
    ],
  );

  Widget _colorPicker() => _Choices(
    title: 'Color',
    choices: [
      _Choice(
        name: 'Automatic',
        selected: _color == null,
        onTap: () => setState(() => _color = null),
        child: const Icon(Icons.auto_awesome_rounded),
      ),
      for (final MapEntry(:key, :value) in deckColors.entries)
        _Choice(
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'media', label: Text('Media')),
                  ButtonSegment(value: 'keys', label: Text('Keys')),
                  ButtonSegment(value: 'open', label: Text('Open')),
                  ButtonSegment(value: 'stat', label: Text('Stat')),
                ],
                selected: {_kind},
                onSelectionChanged: (kinds) =>
                    setState(() => _kind = kinds.single),
              ),
              switch (_kind) {
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
              if (_kind != 'stat') _iconPicker(),
              _colorPicker(),
            ],
          ),
        ),
      ),
      actions: [
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

final class RenamePage extends PageEdit {
  const RenamePage(this.name);

  final String name;
}

final class DeletePage extends PageEdit {
  const DeletePage();
}

/// Names a new page, or renames or deletes the current one.
class PageEditor extends StatefulWidget {
  const PageEditor({
    super.key,
    required this.title,
    this.name = '',
    this.canDelete = false,
  });

  final String title;
  final String name;
  final bool canDelete;

  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(RenamePage(_name.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        maxLength: _maxTextLength,
        decoration: const InputDecoration(labelText: 'Page name'),
        validator: (text) => _required(text, 'Give the page a name'),
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
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

/// A titled row of small square choices, like icons or colors.
class _Choices extends StatelessWidget {
  const _Choices({required this.title, required this.choices});

  final String title;
  final List<_Choice> choices;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(title, style: const TextStyle(color: DeckLook.muted, fontSize: 12)),
      Wrap(spacing: 6, runSpacing: 6, children: choices),
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.name,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeckLook.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? DeckLook.text : DeckLook.cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}
