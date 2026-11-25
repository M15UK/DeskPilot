import 'dart:math';
import 'dart:typed_data';

import 'package:deskpilot/deck.dart';
import 'package:deskpilot/editor.dart';
import 'package:deskpilot/look.dart';
import 'package:deskpilot/now_playing.dart';
import 'package:deskpilot/pictures.dart';
import 'package:deskpilot/tile_grid.dart';
import 'package:deskpilot/tiles.dart';
import 'package:flutter/material.dart';

// Same limit as Deck.MaxButtonsPerPage on the PC.
const _maxButtonsPerPage = 32;

/// A button at the end of the page rail.
typedef RailTool = ({IconData icon, String label, VoidCallback onTap});

/// About how wide a button is for each page size.
const _cellSizes = {'small': 120.0, null: 170.0, 'large': 230.0, 'huge': 300.0};

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
    this.media,
    this.onMediaKey,
    this.pcName,
    this.tools = const [],
    this.folder,
    this.onFolderChanged,
    this.pictures = const {},
    this.pickPicture,
    this.onPicture,
    this.onSharePage,
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

  /// What the PC is playing, for music tiles.
  final NowPlaying? media;

  /// Presses a media key for a music tile's buttons; null turns them off.
  final ValueChanged<String>? onMediaKey;

  /// The PC's name for clock tiles; null while it isn't connected.
  final String? pcName;

  /// Extra buttons at the end of the page rail, like settings while full
  /// screen hides the top bar.
  final List<RailTool> tools;

  /// The id of the open folder on this page, or null for the page itself.
  final String? folder;
  final ValueChanged<String?>? onFolderChanged;

  /// Pictures the phone has, by id, for buttons and wallpapers.
  final Map<String, Uint8List> pictures;

  /// Picks a photo in the editors; the phone's gallery when null.
  final PickPicture? pickPicture;

  /// Sends a picked photo to the PC and returns its id; null hides pictures.
  final String Function(Uint8List)? onPicture;

  /// Shares page [int] as a backup file.
  final ValueChanged<int>? onSharePage;

  /// The open folder's button, when [folder] is still a folder on this page.
  DeckButton? get _openFolder {
    for (final button in deck.pages[page].buttons) {
      if (button.id == folder && button.action is FolderAction) return button;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= _railFromWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _PageRail(
              pages: deck.pages,
              selected: page,
              onSelect: onPageChanged,
              extras: [
                if (editing) ..._pageActions(context),
                for (final tool in tools)
                  _RailItem(
                    icon: tool.icon,
                    label: tool.label,
                    onTap: tool.onTap,
                  ),
              ],
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
    final shown = deck.pages[page];
    final open = _openFolder;
    final buttons = switch (open?.action) {
      FolderAction(:final buttons) => buttons,
      _ => shown.buttons,
    };
    final adding = editing && buttons.length < _maxButtonsPerPage;
    final grid = TileGrid(
      cell: _cellSizes[shown.size] ?? _cellSizes[null]!,
      gap: DeckLook.of(context).gap,
      padding: EdgeInsets.fromLTRB(
        shown.background == null ? 0 : 10,
        shown.background == null ? 0 : 10,
        shown.background == null ? 0 : 10,
        12,
      ),
      editing: editing,
      tiles: [
        if (open != null) (w: 1, h: 1, x: null, y: null),
        for (final button in buttons)
          (w: button.span.$1, h: button.span.$2, x: button.x, y: button.y),
        if (adding) (w: 1, h: 1, x: null, y: null),
      ],
      // The Back and Add button tiles stay where the grid puts them.
      movable: {
        for (var i = 0; i < buttons.length; i++) i + (open == null ? 0 : 1),
      },
      // Moving or resizing one tile pins every tile where it is, so nothing
      // else jumps around.
      onPlaced: (places) => onChange(
        deck.withPlaces({
          for (final (index, button) in buttons.indexed)
            if (places[index + (open == null ? 0 : 1)] case final place)
              button.id: (
                x: place.column,
                y: place.row,
                w: place.width,
                h: place.height,
              ),
        }),
      ),
      children: [
        if (open != null)
          KeyTile(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            color: deckColors['gray']!,
            onTap: () => onFolderChanged?.call(null),
          ),
        for (final button in buttons) _placed(context, button),
        if (adding)
          OutlinedButton.icon(
            onPressed: () => _editButton(context, null),
            style: OutlinedButton.styleFrom(
              foregroundColor: DeckLook.of(context).muted,
              side: BorderSide(
                color: DeckLook.of(context).cardBorder,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  DeckLook.of(context).radius,
                ),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add button'),
          ),
      ],
    );
    if (pictures[shown.wallpaper] case final wallpaper?) {
      // Darkened, so the buttons stay easy to read on any photo.
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DeckLook.of(context).radius),
          image: DecorationImage(
            image: MemoryImage(wallpaper),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.45),
              BlendMode.darken,
            ),
          ),
        ),
        child: grid,
      );
    }
    final background = deckColors[shown.background];
    if (background == null) return grid;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeckLook.of(context).radius),
        border: Border.all(color: background.withValues(alpha: 0.25)),
      ),
      child: grid,
    );
  }

  /// A tile, with a hint in edit mode that a long press moves it.
  Widget _placed(BuildContext context, DeckButton button) {
    final tile = _tile(context, button);
    if (!editing) return tile;
    return Stack(
      fit: StackFit.expand,
      children: [
        tile,
        // Top right: stat tiles have their label top left.
        Positioned(
          top: 6,
          right: 6,
          child: IgnorePointer(
            child: Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: DeckLook.of(context).muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, DeckButton button) {
    final edit = editing ? () => _editButton(context, button) : null;
    final shows = switch (button.action) {
      MusicAction() => NowPlayingCard(
        media: media,
        onKey: editing ? null : onMediaKey,
      ),
      ClockAction() => ClockTile(pcName: pcName, stats: stats),
      PhotosAction(pictures: final ids) => PhotosTile(
        pictures: [for (final id in ids) ?pictures[id]],
      ),
      _ => null,
    };
    if (shows != null) {
      if (edit == null) return shows;
      // In edit mode a tap anywhere on a widget edits it.
      return Stack(
        fit: StackFit.expand,
        children: [
          shows,
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: edit),
          ),
        ],
      );
    }
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
    final opens = button.action is FolderAction;
    return KeyTile(
      icon: buttonIcon(button),
      label: button.label,
      color: buttonColor(button),
      style: button.style,
      show: button.show,
      picture: pictures[button.image],
      onTap:
          edit ??
          (opens
              ? () => onFolderChanged?.call(button.id)
              : press == null
              ? null
              : () => press(button.id)),
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
              avatar: Icon(deckIcons[deckPage.icon] ?? pageIcon(deckPage.name)),
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
    final open = _openFolder;
    final edit = await showDialog<ButtonEdit>(
      context: context,
      builder: (_) => ButtonEditor(
        button: button,
        canBeFolder: open == null,
        pictures: pictures,
        pickPicture: pickPicture,
        onPicture: onPicture,
      ),
    );
    switch (edit) {
      case SaveButton(button: final saved) when button == null && open != null:
        onChange(deck.withButtonInFolder(open.id, saved));
      case SaveButton(button: final saved):
        onChange(deck.withButton(page, saved));
      case DeleteButton(:final id):
        onChange(deck.withoutButton(id));
      case MoveButton(:final id, :final by):
        onChange(deck.movedButton(id, by));
      case OpenFolder(:final id):
        onFolderChanged?.call(id);
      case null:
        break;
    }
  }

  Future<void> _addPage(BuildContext context) async {
    final edit = await showDialog<PageEdit>(
      context: context,
      builder: (_) => PageEditor(
        title: 'Add page',
        pictures: pictures,
        pickPicture: pickPicture,
        onPicture: onPicture,
      ),
    );
    if (edit case SavePage(
      :final name,
      :final size,
      :final icon,
      :final background,
      :final wallpaper,
    )) {
      final added = deck.withPage(name);
      onChange(
        added.changedPage(
          added.pages.length - 1,
          name: name,
          size: size,
          icon: icon,
          background: background,
          wallpaper: wallpaper,
        ),
      );
      onPageChanged(deck.pages.length);
    }
  }

  Future<void> _editPage(BuildContext context) async {
    final edit = await showDialog<PageEdit>(
      context: context,
      builder: (_) => PageEditor(
        title: 'Page settings',
        page: deck.pages[page],
        canDelete: deck.pages.length > 1,
        onShare: switch (onSharePage) {
          final share? => () => share(page),
          null => null,
        },
        pictures: pictures,
        pickPicture: pickPicture,
        onPicture: onPicture,
      ),
    );
    switch (edit) {
      case SavePage(
        :final name,
        :final size,
        :final icon,
        :final background,
        :final wallpaper,
      ):
        onChange(
          deck.changedPage(
            page,
            name: name,
            size: size,
            icon: icon,
            background: background,
            wallpaper: wallpaper,
          ),
        );
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
    required this.pages,
    required this.selected,
    required this.onSelect,
    required this.extras,
  });

  final List<DeckPage> pages;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<_RailItem> extras;

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    decoration: BoxDecoration(
      color: DeckLook.of(context).rail,
      borderRadius: BorderRadius.circular(DeckLook.of(context).radius),
      border: Border.all(color: DeckLook.of(context).cardBorder),
    ),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final (index, page) in pages.indexed)
          _RailItem(
            icon: deckIcons[page.icon] ?? pageIcon(page.name),
            label: page.name,
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
                borderRadius: BorderRadius.circular(
                  DeckLook.of(context).radius * 0.6,
                ),
              ),
              child: Icon(
                icon,
                color: selected
                    ? DeckLook.of(context).text
                    : DeckLook.of(context).muted,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? DeckLook.of(context).text
                    : DeckLook.of(context).muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
