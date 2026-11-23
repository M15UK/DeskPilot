import 'dart:async';
import 'dart:math';

import 'package:deskpilot/deck.dart';
import 'package:deskpilot/editor.dart';
import 'package:deskpilot/look.dart';
import 'package:deskpilot/tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Same limit as Deck.MaxButtonsPerPage on the PC.
const _maxButtonsPerPage = 32;

/// Wider than this, pages sit in a rail on the left (tablets); narrower, they
/// are chips under the grid (phones).
const _railFromWidth = 600.0;

/// One page of the deck as a grid of buttons, with a rail or chips to switch
/// pages. In edit mode a tap edits a button, a long press drags it to a new
/// place, and extra tiles add buttons and pages.
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= _railFromWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _PageRail(
              names: [for (final p in deck.pages) p.name],
              selected: page,
              onSelect: onPageChanged,
              extras: editing ? _pageActions(context) : const [],
            ),
            Expanded(child: _grid(context)),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _grid(context)),
          if (deck.pages.length > 1 || editing) _pageChips(context),
        ],
      );
    },
  );

  Widget _grid(BuildContext context) {
    final buttons = deck.pages[page].buttons;
    return GridView.extent(
      maxCrossAxisExtent: 170,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (final (index, button) in buttons.indexed)
          _placed(context, button, index),
        if (editing && buttons.length < _maxButtonsPerPage)
          OutlinedButton.icon(
            onPressed: () => _editButton(context, null),
            style: OutlinedButton.styleFrom(
              foregroundColor: DeckLook.muted,
              side: const BorderSide(color: DeckLook.cardBorder, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DeckLook.radius),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add button'),
          ),
      ],
    );
  }

  /// A tile, which in edit mode can be dragged onto another tile's place.
  Widget _placed(BuildContext context, DeckButton button, int index) {
    final tile = _tile(context, button);
    if (!editing) return tile;
    return DragTarget<String>(
      onWillAcceptWithDetails: (drag) => drag.data != button.id,
      onAcceptWithDetails: (drag) {
        final from = deck.pages[page].buttons.indexWhere(
          (b) => b.id == drag.data,
        );
        if (from >= 0) onChange(deck.movedButton(drag.data, index - from));
      },
      builder: (context, hovering, _) => LayoutBuilder(
        builder: (context, size) => LongPressDraggable<String>(
          data: button.id,
          feedback: SizedBox.fromSize(size: size.biggest, child: tile),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: Stack(
            children: [
              Positioned.fill(child: tile),
              if (hovering.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(DeckLook.radius),
                        border: Border.all(
                          color: deckColors['blue']!,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              const Positioned(
                top: 6,
                left: 6,
                child: IgnorePointer(
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 16,
                    color: DeckLook.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, DeckButton button) {
    final edit = editing ? () => _editButton(context, button) : null;
    if (button.action case final StatAction stat) {
      return StatTile(
        label: button.label,
        action: stat,
        value: stats[stat.stat],
        maximum: statMaximum(stat.stat, stats),
        history: history[stat.stat] ?? const [],
        color: buttonColor(button),
        onTap: edit,
      );
    }
    final press = onPress;
    return KeyTile(
      icon: buttonIcon(button),
      label: button.label,
      color: buttonColor(button),
      onTap:
          edit ??
          (press == null
              ? null
              : () {
                  unawaited(HapticFeedback.lightImpact());
                  press(button.id);
                }),
    );
  }

  List<_RailItem> _pageActions(BuildContext context) => [
    _RailItem(
      icon: Icons.edit_rounded,
      label: 'Page settings',
      onTap: () => _editPage(context),
    ),
    _RailItem(
      icon: Icons.add_rounded,
      label: 'Add page',
      onTap: () => _addPage(context),
    ),
  ];

  Widget _pageChips(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 8,
        children: [
          for (final (index, deckPage) in deck.pages.indexed)
            ChoiceChip(
              avatar: Icon(pageIcon(deckPage.name)),
              label: Text(deckPage.name),
              selected: index == page,
              onSelected: (_) => onPageChanged(index),
            ),
          if (editing) ...[
            ActionChip(
              avatar: const Icon(Icons.edit_rounded),
              label: const Text('Page settings'),
              onPressed: () => _editPage(context),
            ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded),
              label: const Text('Add page'),
              onPressed: () => _addPage(context),
            ),
          ],
        ],
      ),
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

/// The pages down the left side of a tablet, like a sidebar.
class _PageRail extends StatelessWidget {
  const _PageRail({
    required this.names,
    required this.selected,
    required this.onSelect,
    required this.extras,
  });

  final List<String> names;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<_RailItem> extras;

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    decoration: BoxDecoration(
      color: DeckLook.rail,
      borderRadius: BorderRadius.circular(DeckLook.radius),
      border: Border.all(color: DeckLook.cardBorder),
    ),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final (index, name) in names.indexed)
          _RailItem(
            icon: pageIcon(name),
            label: name,
            selected: index == selected,
            onTap: () => onSelect(index),
          ),
        ...extras,
      ],
    ),
  );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          spacing: 4,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1E2433) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? DeckLook.text : DeckLook.muted,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selected ? DeckLook.text : DeckLook.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
