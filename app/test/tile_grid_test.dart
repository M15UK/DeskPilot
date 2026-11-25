import 'package:deskpilot/tile_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests think in whole cells; the grid counts eighths of a cell.
TileSpec free(int w, int h) => (w: w * 8, h: h * 8, x: null, y: null);

TileSpec at(int x, int y, [int w = 1, int h = 1]) =>
    (w: w * 8, h: h * 8, x: x * 8, y: y * 8);

List<(int, int)> cells(List<TilePlace> places) => [
  for (final p in places) (p.column ~/ 8, p.row ~/ 8),
];

void main() {
  test('tiles fill each row left to right, and a big one takes two by two', () {
    final places = placeTiles([
      free(1, 1),
      free(2, 2),
      free(1, 1),
      free(1, 1),
      free(1, 1),
    ], 4);

    expect(cells(places), [(0, 0), (1, 0), (3, 0), (0, 1), (3, 1)]);
  });

  test('a tile wider than the grid is made to fit', () {
    final places = placeTiles([free(2, 1)], 1);

    expect((places.single.width, places.single.height), (8, 8));
  });

  test('a tile placed by hand stays put, and the rest fill around it', () {
    final places = placeTiles([at(3, 0), free(1, 1), free(2, 1)], 4);

    expect(cells(places), [(3, 0), (0, 0), (1, 0)]);
  });

  test(
    'a place that runs off the grid or overlaps is filled like the rest',
    () {
      final places = placeTiles([at(3, 0, 2), at(0, 0), at(0, 0)], 4);

      expect(cells(places), [(1, 0), (0, 0), (3, 0)]);
    },
  );

  testWidgets('a wide tile is two tiles wide', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: TileGrid(
              cell: 100,
              gap: 0,
              tiles: [free(1, 1), free(2, 1)],
              children: const [Text('one'), Text('wide')],
            ),
          ),
        ),
      ),
    );

    final wide = find.ancestor(
      of: find.text('wide'),
      matching: find.byType(Positioned),
    );
    expect(tester.getSize(wide.first).width, 200);
  });

  group('in edit mode', () {
    List<TilePlace>? placed;

    Widget grid(List<TileSpec> tiles) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: TileGrid(
            cell: 100,
            gap: 0,
            editing: true,
            movable: {for (var i = 0; i < tiles.length; i++) i},
            tiles: tiles,
            onPlaced: (places) => placed = places,
            children: [for (var i = 0; i < tiles.length; i++) Text('tile $i')],
          ),
        ),
      ),
    );

    setUp(() => placed = null);

    testWidgets('a long press drags a tile to any empty cell', (tester) async {
      await tester.pumpWidget(grid([free(1, 1), free(1, 1)]));

      final drag = await tester.startGesture(
        tester.getCenter(find.text('tile 0')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await drag.moveBy(const Offset(200, 100));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect(cells(placed!), [(2, 1), (1, 0)]);
    });

    testWidgets('a tile is not dropped onto another', (tester) async {
      await tester.pumpWidget(grid([free(1, 1), free(1, 1)]));

      final drag = await tester.startGesture(
        tester.getCenter(find.text('tile 0')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await drag.moveBy(const Offset(100, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect(placed, isNull);
    });

    testWidgets('the corner handle makes a tile bigger', (tester) async {
      await tester.pumpWidget(grid([free(1, 1)]));

      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.open_in_full_rounded)),
      );
      await drag.moveBy(const Offset(110, 210));
      await tester.pump();
      await drag.up();
      await tester.pump();

      // 12.5 pixels an eighth: 110 is about 9 more, 210 about 17 more.
      expect((placed!.single.width, placed!.single.height), (17, 25));
      expect(find.text('2.13 × 3.13'), findsNothing, reason: 'label gone');
    });

    testWidgets('shows the size while resizing', (tester) async {
      await tester.pumpWidget(grid([free(1, 1)]));

      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.open_in_full_rounded)),
      );
      await drag.moveBy(const Offset(50, 0));
      await tester.pump();

      expect(find.text('1.5 × 1'), findsOneWidget);
      await drag.up();
    });

    testWidgets('a tile moves in small steps, not only whole cells', (
      tester,
    ) async {
      await tester.pumpWidget(grid([free(1, 1)]));

      final drag = await tester.startGesture(
        tester.getCenter(find.text('tile 0')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await drag.moveBy(const Offset(30, 40));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect((placed!.single.column, placed!.single.row), (2, 3));
    });
  });
}
