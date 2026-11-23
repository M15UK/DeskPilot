import 'package:deskpilot/tile_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tiles fill each row left to right, and a big one takes two by two', () {
    final places = placeTiles([(1, 1), (2, 2), (1, 1), (1, 1), (1, 1)], 4);

    expect(
      [for (final p in places) (p.column, p.row)],
      [(0, 0), (1, 0), (3, 0), (0, 1), (3, 1)],
    );
  });

  test('a tile wider than the grid is made to fit', () {
    final places = placeTiles([(2, 1)], 1);

    expect((places.single.width, places.single.height), (1, 1));
  });

  testWidgets('a wide tile is two tiles wide', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: TileGrid(
              cell: 100,
              gap: 0,
              spans: [(1, 1), (2, 1)],
              children: [Text('one'), Text('wide')],
            ),
          ),
        ),
      ),
    );

    final wide = find.ancestor(
      of: find.text('wide'),
      matching: find.byType(Positioned),
    );
    expect(tester.getSize(wide).width, 200);
  });
}
