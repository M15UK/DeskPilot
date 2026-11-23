import 'dart:math';

import 'package:flutter/widgets.dart';

/// Where a tile sits in the grid, in cells.
typedef TilePlace = ({int column, int row, int width, int height});

/// Places tiles of (width, height) cells in a grid [columns] wide, in order,
/// each in the first free spot that fits, reading left to right and top to
/// bottom. A tile wider than the grid is narrowed to fit.
List<TilePlace> placeTiles(List<(int, int)> spans, int columns) {
  final taken = <(int, int)>{};
  bool free(int column, int row, int width, int height) {
    for (var x = column; x < column + width; x++) {
      for (var y = row; y < row + height; y++) {
        if (taken.contains((x, y))) return false;
      }
    }
    return true;
  }

  TilePlace place(int wide, int tall) {
    final width = min(wide, columns);
    for (var row = 0; ; row++) {
      for (var column = 0; column + width <= columns; column++) {
        if (free(column, row, width, tall)) {
          for (var x = column; x < column + width; x++) {
            for (var y = row; y < row + tall; y++) {
              taken.add((x, y));
            }
          }
          return (column: column, row: row, width: width, height: tall);
        }
      }
    }
  }

  return [for (final (wide, tall) in spans) place(wide, tall)];
}

/// A scrolling grid of square cells up to [cell] pixels wide, where each
/// child takes its span from [spans] (width, height in cells).
class TileGrid extends StatelessWidget {
  const TileGrid({
    super.key,
    required this.cell,
    required this.gap,
    required this.spans,
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final double cell;
  final double gap;
  final List<(int, int)> spans;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final width = size.maxWidth - padding.horizontal;
      // Like GridView.extent: cells are at most [cell] wide.
      final columns = max(1, ((width + gap) / (cell + gap)).ceil());
      final unit = (width - gap * (columns - 1)) / columns;
      final places = placeTiles(spans, columns);
      final rows = places.fold(0, (most, p) => max(most, p.row + p.height));
      double length(int cells) => cells * unit + (cells - 1) * gap;
      return SingleChildScrollView(
        padding: padding,
        child: SizedBox(
          height: rows == 0 ? 0 : length(rows),
          child: Stack(
            children: [
              for (final (index, place) in places.indexed)
                Positioned(
                  left: place.column * (unit + gap),
                  top: place.row * (unit + gap),
                  width: length(place.width),
                  height: length(place.height),
                  child: children[index],
                ),
            ],
          ),
        ),
      );
    },
  );
}
