import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Places and sizes count in eighths of a cell, so a tile can have nearly
/// any size (like `eighths` in the deck).
const _parts = 8;

/// The smallest tile is half a cell; the biggest twelve cells across.
const _minSize = _parts ~/ 2;
const _maxSize = 12 * _parts;

/// Where a tile sits and how big it is, in eighths of a cell.
typedef TilePlace = ({int column, int row, int width, int height});

/// A tile to lay out, in eighths of a cell: its size, and its top left corner
/// when it was placed by hand.
typedef TileSpec = ({int w, int h, int? x, int? y});

/// A size in eighths as cells: 1, 1.5, 2.13.
String cellCount(int parts) {
  final cells = parts / _parts;
  return cells == cells.roundToDouble()
      ? '${cells.round()}'
      : cells.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

bool _overlaps(TilePlace a, TilePlace b) =>
    a.column < b.column + b.width &&
    b.column < a.column + a.width &&
    a.row < b.row + b.height &&
    b.row < a.row + a.height;

/// Places tiles in a grid [columns] cells wide. Tiles placed by hand go where
/// they were put, when that fits and is free; every other tile then takes the
/// first free whole cell that fits it, reading left to right and top to
/// bottom. A tile wider than the grid is narrowed to fit.
List<TilePlace> placeTiles(List<TileSpec> tiles, int columns) {
  final across = columns * _parts;
  final taken = <TilePlace>[];
  bool free(TilePlace place) => !taken.any((other) => _overlaps(place, other));

  final places = List<TilePlace?>.filled(tiles.length, null);
  for (final (index, tile) in tiles.indexed) {
    if (tile case (:final w, :final h, x: final x?, y: final y?)
        when x + w <= across) {
      final place = (column: x, row: y, width: w, height: h);
      if (free(place)) taken.add(places[index] = place);
    }
  }
  for (final (index, tile) in tiles.indexed) {
    if (places[index] != null) continue;
    final width = min(tile.w, across);
    search:
    for (var row = 0; ; row += _parts) {
      for (var column = 0; column + width <= across; column += _parts) {
        final place = (column: column, row: row, width: width, height: tile.h);
        if (free(place)) {
          taken.add(places[index] = place);
          break search;
        }
      }
    }
  }
  return [for (final place in places) place!];
}

/// A scrolling grid of square cells up to [cell] pixels wide. In edit mode
/// a long press drags a [movable] tile to any free cell, and the handle in its
/// corner resizes it; [onPlaced] then gets where every tile is.
class TileGrid extends StatefulWidget {
  const TileGrid({
    super.key,
    required this.cell,
    required this.gap,
    required this.tiles,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.editing = false,
    this.movable = const {},
    this.onPlaced,
  });

  final double cell;
  final double gap;
  final List<TileSpec> tiles;
  final List<Widget> children;
  final EdgeInsets padding;
  final bool editing;

  /// The indexes of the tiles that can be moved and resized.
  final Set<int> movable;
  final ValueChanged<List<TilePlace>>? onPlaced;

  @override
  State<TileGrid> createState() => _TileGridState();
}

class _TileGridState extends State<TileGrid> {
  int? _active;
  bool _resizing = false;
  Offset _drag = Offset.zero;
  TilePlace? _preview;
  bool _blocked = false;

  void _start(int index, TilePlace place, {required bool resizing}) =>
      setState(() {
        _active = index;
        _resizing = resizing;
        _drag = Offset.zero;
        _preview = place;
        _blocked = false;
      });

  /// Follows the finger in eighths of a cell ([step] pixels each): where the
  /// tile would land or how big it would be, and whether that's free.
  void _follow(Offset drag, List<TilePlace> places, int columns, double step) {
    final index = _active;
    if (index == null) return;
    final place = places[index];
    final across = columns * _parts;
    final moved = (x: (drag.dx / step).round(), y: (drag.dy / step).round());
    final TilePlace next = _resizing
        ? (
            column: place.column,
            row: place.row,
            width: (place.width + moved.x).clamp(
              _minSize,
              max(_minSize, min(_maxSize, across - place.column)),
            ),
            height: (place.height + moved.y).clamp(_minSize, _maxSize),
          )
        : (
            column: (place.column + moved.x).clamp(
              0,
              max(0, across - place.width),
            ),
            row: max(0, place.row + moved.y),
            width: place.width,
            height: place.height,
          );
    setState(() {
      _drag = drag;
      _preview = next;
      _blocked = [
        for (final (i, other) in places.indexed)
          if (i != index) other,
      ].any((other) => _overlaps(next, other));
    });
  }

  void _finish(List<TilePlace> places) {
    final (index, preview) = (_active, _preview);
    if (index != null && preview != null && !_blocked) {
      if (preview != places[index]) {
        widget.onPlaced?.call(
          List.unmodifiable([...places]..[index] = preview),
        );
      }
    }
    setState(() {
      _active = null;
      _preview = null;
      _drag = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final gap = widget.gap;
      final width = size.maxWidth - widget.padding.horizontal;
      // Like GridView.extent: cells are at most [cell] wide.
      final columns = max(1, ((width + gap) / (widget.cell + gap)).ceil());
      final unit = (width - gap * (columns - 1)) / columns;
      // A cell plus its gap, and an eighth of that: one step of a tile.
      final step = (unit + gap) / _parts;
      final places = placeTiles(widget.tiles, columns);
      double length(int parts) => parts * step - gap;

      final preview = _preview;
      var rows = places.fold(0, (most, p) => max(most, p.row + p.height));
      if (preview != null) rows = max(rows, preview.row + preview.height);
      // Room below the tiles to drag them into.
      if (widget.editing) rows += 2 * _parts;

      Widget placed(int index) {
        final place = places[index];
        final active = index == _active;
        final shown = active && _resizing ? preview ?? place : place;
        final follow = active && !_resizing ? _drag : Offset.zero;
        final tile = widget.children[index];
        return Positioned(
          // Keyed, so a tile keeps its gesture when it's drawn on top.
          key: ValueKey(index),
          left: shown.column * step + follow.dx,
          top: shown.row * step + follow.dy,
          width: length(shown.width),
          height: length(shown.height),
          child: widget.editing && widget.movable.contains(index)
              ? _Editable(
                  onMoveStart: () => _start(index, place, resizing: false),
                  onMove: (drag) => _follow(drag, places, columns, step),
                  onResizeStart: () => _start(index, place, resizing: true),
                  onResize: (delta) =>
                      _follow(_drag + delta, places, columns, step),
                  onEnd: () => _finish(places),
                  child: Opacity(opacity: active ? 0.85 : 1, child: tile),
                )
              : tile,
        );
      }

      final order = [
        for (var i = 0; i < places.length; i++)
          if (i != _active) i,
        ?_active,
      ];
      return SingleChildScrollView(
        padding: widget.padding,
        child: SizedBox(
          height: rows == 0 ? 0 : length(rows),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (preview != null && _active != null)
                Positioned(
                  left: preview.column * step,
                  top: preview.row * step,
                  width: length(preview.width),
                  height: length(preview.height),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _blocked
                              ? const Color(0xFFFF5A5F)
                              : const Color(0xFF4ADE80),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              for (final index in order) placed(index),
              if (preview != null && _resizing && _active != null)
                Positioned(
                  left: preview.column * step,
                  top: preview.row * step,
                  width: length(preview.width),
                  height: length(preview.height),
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${cellCount(preview.width)} × '
                          '${cellCount(preview.height)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A tile in edit mode: a long press drags it, and the handle in its corner
/// resizes it.
class _Editable extends StatelessWidget {
  const _Editable({
    required this.onMoveStart,
    required this.onMove,
    required this.onResizeStart,
    required this.onResize,
    required this.onEnd,
    required this.child,
  });

  final VoidCallback onMoveStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onResizeStart;
  final ValueChanged<Offset> onResize;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      GestureDetector(
        onLongPressStart: (_) => onMoveStart(),
        onLongPressMoveUpdate: (details) => onMove(details.offsetFromOrigin),
        onLongPressEnd: (_) => onEnd(),
        child: child,
      ),
      Positioned(
        right: 2,
        bottom: 2,
        child: RawGestureDetector(
          gestures: {
            _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
              _EagerPan.new,
              (pan) => pan
                ..onStart = ((_) => onResizeStart())
                ..onUpdate = ((details) => onResize(details.delta))
                ..onEnd = ((_) => onEnd()),
            ),
          },
          child: Semantics(
            label: 'Resize',
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0x99000000),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.open_in_full_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A drag that wins straight away, so resizing never scrolls the page.
class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
