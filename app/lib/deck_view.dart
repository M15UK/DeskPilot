import 'dart:math';

import 'package:deskpilot/deck.dart';
import 'package:flutter/material.dart';

// Same limits as Deck.MaxButtonsPerPage and Deck.MaxTextLength on the PC.
const _maxButtonsPerPage = 32;
const _maxTextLength = 40;

/// One page of the deck as a grid of buttons, with chips to switch pages.
/// In edit mode a tap edits the button, and extra tiles and chips add more.
class DeckView extends StatelessWidget {
  const DeckView({
    super.key,
    required this.deck,
    required this.page,
    required this.editing,
    required this.onPress,
    required this.onChange,
    required this.onPageChanged,
    this.stats = const {},
    this.history = const {},
  });

  final Deck deck;
  final int page;
  final bool editing;

  /// Null while the PC isn't connected, which turns the buttons off.
  final ValueChanged<String>? onPress;
  final ValueChanged<Deck> onChange;
  final ValueChanged<int> onPageChanged;

  /// The PC's latest readings, by [statNames] key.
  final Map<String, double> stats;

  /// The last minute of each reading, oldest first, for chart tiles.
  final Map<String, List<double>> history;

  @override
  Widget build(BuildContext context) {
    final buttons = deck.pages[page].buttons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deck.pages.length > 1 || editing) _pageChips(context),
        Expanded(
          child: GridView.extent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              for (final button in buttons) _tile(context, button),
              if (editing && buttons.length < _maxButtonsPerPage)
                OutlinedButton.icon(
                  onPressed: () => _editButton(context, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add button'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, DeckButton button) {
    if (button.action case final StatAction stat) {
      return _StatTile(
        label: button.label,
        action: stat,
        value: stats[stat.stat],
        history: history[stat.stat] ?? const [],
        onTap: editing ? () => _editButton(context, button) : null,
      );
    }
    final press = onPress;
    return FilledButton.tonal(
      onPressed: editing
          ? () => _editButton(context, button)
          : press == null
          ? null
          : () => press(button.id),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconFor(button.action), size: 32),
          const SizedBox(height: 8),
          Text(
            button.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _pageChips(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: 8,
      children: [
        for (final (index, deckPage) in deck.pages.indexed)
          ChoiceChip(
            label: Text(deckPage.name),
            selected: index == page,
            onSelected: (_) => onPageChanged(index),
          ),
        if (editing) ...[
          ActionChip(
            avatar: const Icon(Icons.edit),
            label: const Text('Page settings'),
            onPressed: () => _editPage(context),
          ),
          ActionChip(
            avatar: const Icon(Icons.add),
            label: const Text('Add page'),
            onPressed: () => _addPage(context),
          ),
        ],
      ],
    ),
  );

  Future<void> _editButton(BuildContext context, DeckButton? button) async {
    final edit = await showDialog<ButtonEdit>(
      context: context,
      builder: (_) => ButtonEditor(button: button),
    );
    if (edit == null) return;
    onChange(switch (edit) {
      SaveButton(:final button) => deck.withButton(page, button),
      DeleteButton(:final id) => deck.withoutButton(id),
      MoveButton(:final id, :final by) => deck.movedButton(id, by),
    });
  }

  Future<void> _addPage(BuildContext context) async {
    final edit = await showDialog<PageEdit>(
      context: context,
      builder: (_) => const PageEditor(title: 'Add page'),
    );
    if (edit case RenamePage(:final name)) {
      onChange(deck.withPage(name));
      onPageChanged(deck.pages.length);
    }
  }

  Future<void> _editPage(BuildContext context) async {
    final edit = await showDialog<PageEdit>(
      context: context,
      builder: (_) => PageEditor(
        title: 'Page settings',
        name: deck.pages[page].name,
        canDelete: deck.pages.length > 1,
      ),
    );
    switch (edit) {
      case RenamePage(:final name):
        onChange(deck.renamedPage(page, name));
      case DeletePage():
        onChange(deck.withoutPage(page));
        onPageChanged(max(0, page - 1));
      case null:
        break;
    }
  }
}

IconData _iconFor(ButtonAction action) => switch (action) {
  MediaAction(media: 'playPause') => Icons.play_arrow_rounded,
  MediaAction(media: 'next') => Icons.skip_next_rounded,
  MediaAction(media: 'previous') => Icons.skip_previous_rounded,
  MediaAction(media: 'volumeUp') => Icons.volume_up_rounded,
  MediaAction(media: 'volumeDown') => Icons.volume_down_rounded,
  MediaAction(media: 'mute') => Icons.volume_off_rounded,
  MediaAction() => Icons.music_note_rounded,
  KeysAction() => Icons.keyboard_rounded,
  OpenAction() => Icons.open_in_new_rounded,
  StatAction() => Icons.speed_rounded,
};

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

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final button = DeckButton(
      id: widget.button?.id ?? newButtonId(),
      label: _label.text.trim(),
      action: _action(),
    );
    Navigator.of(context).pop(SaveButton(button));
  }

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
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label'),
                maxLength: _maxTextLength,
                validator: (text) => _required(text, 'Give the button a label'),
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

/// How many readings a chart tile shows: one a second for a minute.
const statHistoryLength = 60;

/// How a reading looks on a tile: 41°C, 24%, or a dash when the PC can't
/// tell.
String formatStat(String stat, double? value) => switch (value) {
  null => '—',
  final value when stat.endsWith('Temp') => '${value.round()}°C',
  final value => '${value.round()}%',
};

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.action,
    required this.value,
    required this.history,
    required this.onTap,
  });

  final String label;
  final StatAction action;
  final double? value;
  final List<double> history;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = Text(
      formatStat(action.stat, value),
      style: theme.textTheme.headlineSmall,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: switch (action.style) {
                  'gauge' => Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: CircularProgressIndicator(
                          // Percent and °C both fill the ring at 100.
                          value: ((value ?? 0) / 100).clamp(0.0, 1.0),
                          strokeWidth: 8,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      reading,
                    ],
                  ),
                  'chart' => Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ChartPainter(
                            history,
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Align(alignment: Alignment.topLeft, child: reading),
                    ],
                  ),
                  _ => Center(child: reading),
                },
              ),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line of the last minute of a reading, 0 at the bottom and 100 at the
/// top, growing in from the right.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.points, this.color);

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final step = size.width / (statHistoryLength - 1);
    final line = Path();
    for (final (index, point) in points.indexed) {
      final x = size.width - (points.length - 1 - index) * step;
      final y = size.height * (1 - (point / 100).clamp(0.0, 1.0));
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.color != color;
}
