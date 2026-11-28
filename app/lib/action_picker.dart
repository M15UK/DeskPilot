import 'package:deskpilot/deck.dart';
import 'package:deskpilot/look.dart';
import 'package:deskpilot/tiles.dart';
import 'package:flutter/material.dart';

/// An action picked to add: ready to add straight away, or needing settings
/// first (keys to press, what to open, photos), and an opening size in cells.
typedef PickedAction = ({
  ButtonAction action,
  bool needsSettings,
  (int, int)? cells,
});

typedef _Item = ({
  String category,
  String name,
  ButtonAction action,
  bool needsSettings,
  (int, int)? cells,
});

List<_Item> _items({required bool canBeFolder}) => [
  for (final MapEntry(:key, :value) in mediaKeys.entries)
    (
      category: 'Media',
      name: value,
      action: MediaAction(key),
      needsSettings: false,
      cells: null,
    ),
  (
    category: 'Keys and apps',
    name: 'Key shortcut',
    action: const KeysAction([]),
    needsSettings: true,
    cells: null,
  ),
  (
    category: 'Keys and apps',
    name: 'Open an app or website',
    action: const OpenAction(''),
    needsSettings: true,
    cells: null,
  ),
  if (canBeFolder)
    (
      category: 'Keys and apps',
      name: 'Folder',
      action: const FolderAction([]),
      needsSettings: false,
      cells: null,
    ),
  (
    category: 'Widgets',
    name: 'Music',
    action: const MusicAction(),
    needsSettings: false,
    cells: (3, 1),
  ),
  (
    category: 'Widgets',
    name: 'Clock',
    action: const ClockAction(),
    needsSettings: false,
    cells: null,
  ),
  (
    category: 'Widgets',
    name: 'Photos',
    action: const PhotosAction([]),
    needsSettings: true,
    cells: (2, 2),
  ),
  (
    category: 'Widgets',
    name: 'Tyres',
    action: const TyresAction(),
    needsSettings: false,
    cells: (2, 2),
  ),
  for (final MapEntry(:key, :value) in statNames.entries)
    (
      category: value.startsWith('Sim: ') ? 'Sim racing' : 'PC stats',
      name: autoLabel(StatAction(key, 'number')),
      action: StatAction(
        key,
        key.endsWith('Load') || key == 'rpm' ? 'gauge' : 'number',
      ),
      needsSettings: false,
      cells: null,
    ),
];

/// The list of everything a button can do, by category with a search, like
/// the actions list of the popular deck apps. Returns the [PickedAction].
class ActionPicker extends StatefulWidget {
  const ActionPicker({super.key, this.canBeFolder = true});

  /// False inside a folder: folders don't hold folders.
  final bool canBeFolder;

  @override
  State<ActionPicker> createState() => _ActionPickerState();
}

class _ActionPickerState extends State<ActionPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = DeckLook.of(context);
    final words = _search.text.trim().toLowerCase();
    final shown = [
      for (final item in _items(canBeFolder: widget.canBeFolder))
        if (words.isEmpty ||
            item.name.toLowerCase().contains(words) ||
            item.category.toLowerCase().contains(words))
          item,
    ];
    final categories = {for (final item in shown) item.category};
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add a button',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search actions',
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing matches "$words".',
                        style: TextStyle(color: look.muted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        for (final category in categories) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Text(
                              category,
                              style: TextStyle(
                                color: look.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final item in shown)
                                if (item.category == category)
                                  _Card(item: item),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final sample = DeckButton(id: '', label: item.name, action: item.action);
    return SizedBox(
      width: 116,
      height: 96,
      child: KeyTile(
        icon: buttonIcon(sample),
        label: item.name,
        color: buttonColor(sample),
        onTap: () => Navigator.of(context).pop<PickedAction>((
          action: item.action,
          needsSettings: item.needsSettings,
          cells: item.cells,
        )),
      ),
    );
  }
}
