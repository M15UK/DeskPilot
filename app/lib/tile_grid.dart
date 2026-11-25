import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Where a tile sits in the grid, in cells.
typedef TilePlace = ({int column, int row, int width, int height});

/// A tile to lay out: its size in cells, and the cell of its top left corner
/// when it was placed by hand.
typedef TileSpec = ({int w, int h, int? x, int? y});

/// The most cells a tile can grow to, like DeckButton.MaxSpan on the PC.
const _maxSpan = 12;

/// Places tiles in a grid [columns] wide. Tiles placed by hand go where they
/// were put, when that fits and is free; every other tile then takes the first
/// free spot, reading left to right and top to bottom. A tile wider than the
/// grid is narrowed to fit.
List<TilePlace> placeTiles(List<TileSpec> tiles, int columns) {
  final taken = <(int, int)>{};
  bool free(int column, int row, int width, int height) {
    for (var x = column; x < column + width; x++) {
      for (var y = row; y < row + height; y++) {
        if (taken.contains((x, y))) return false;
      }
    }
    return true;
  }

  TilePlace take(int column, int row, int width, int height) {
    for (var x = column; x < column + width; x++) {
      for (var y = row; y < row + height; y++) {
        taken.add((x, y));
      }
    }
    return (column: column, row: row, width: width, height: height);
  }

  final places = List<TilePlace?>.filled(tiles.length, null);
  for (final (index, tile) in tiles.indexed) {
    if (tile case (:final w, :final h, x: final x?, y: final y?)
        when x + w <= columns && free(x, y, w, h)) {
      places[index] = take(x, y, w, h);
    }
  }
  for (final (index, tile) in tiles.indexed) {
    if (places[index] != null) continue;
    final width = min(tile.w, columns);
    search:
    for (var row = 0; ; row++) {
      for (var column = 0; column + width <= columns; column++) {
        if (free(column, row, width, tile.h)) {
          places[index] = take(column, row, width, tile.h);
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

  /// Follows the finger: where the tile would land, and whether it's free.
  void _follow(Offset drag, List<TilePlace> places, int columns, double step) {
    final index = _active;
    if (index == null) return;
    final place = places[index];
    final TilePlace next;
    if (_resizing) {
      final width = (place.width + drag.dx / step).round();
      final height = (place.height + drag.dy / step).round();
      next = (
        column: place.column,
        row: place.row,
        width: width.clamp(1, min(_maxSpan, columns - place.column)),
        height: height.clamp(1, _maxSpan),
      );
    } else {
      final column = ((place.column * step + drag.dx) / step).round();
      final row = ((place.row * step + drag.dy) / step).round();
      next = (
        column: column.clamp(0, columns - place.width),
        row: max(0, row),
        width: place.width,
        height: place.height,
      );
    }
    setState(() {
      _drag = drag;
      _preview = next;
      _blocked = _overlaps(next, places, index);
    });
  }

  static bool _overlaps(TilePlace place, List<TilePlace> places, int except) {
    for (final (index, other) in places.indexed) {
      if (index == except) continue;
      if (place.column < other.column + other.width &&
          other.column < place.column + place.width &&
          place.row < other.row + other.height &&
          other.row < place.row + place.height) {
        return true;
      }
    }
    return false;
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
      final step = unit + gap;
      final places = placeTiles(widget.tiles, columns);
      double length(int cells) => cells * unit + (cells - 1) * gap;

      final preview = _preview;
      var rows = places.fold(0, (most, p) => max(most, p.row + p.height));
      if (preview != null) rows = max(rows, preview.row + preview.height);
      // Room below the tiles to drag them into.
      if (widget.editing) rows += 2;

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
