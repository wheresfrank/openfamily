import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/theme/app_theme.dart';
import 'package:openfamily/widgets/dot_grid.dart';

void main() {
  test('dot positions match the original loop bounds', () {
    const double spacing = 6;
    const Size size = Size(20, 14);
    final List<double> expected = <double>[];
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        expected
          ..add(x)
          ..add(y);
      }
    }
    expect(DotGridPainter.dotPositions(size, spacing), expected);
  });

  test('an empty area has no dots', () {
    expect(DotGridPainter.dotPositions(Size.zero, 6), isEmpty);
    expect(DotGridPainter.dotPositions(const Size(2, 100), 6), isEmpty);
  });

  testWidgets('the grid sits in its own repaint boundary behind the child',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: DotGridBackground(child: Text('content')),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    final Finder grid = find.descendant(
      of: find.byType(DotGridBackground),
      matching: find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter is DotGridPainter,
      ),
    );
    expect(grid, findsOneWidget);
    expect(
      find.ancestor(of: grid, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });
}
