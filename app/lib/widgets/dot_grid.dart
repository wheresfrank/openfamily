import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subwiz-style 6px dot field. Paper stays undyed; lime stays on actions.
///
/// The dots live in their own repaint boundary behind [child], so scrolling or
/// animating [child] never repaints the grid: it is rasterized once and reused.
class DotGridBackground extends StatelessWidget {
  const DotGridBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BrandTheme brand = BrandTheme.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: DotGridPainter(color: brand.dot),
              isComplex: true,
              willChange: false,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class DotGridPainter extends CustomPainter {
  const DotGridPainter({required this.color, this.spacing = 6});

  final Color color;
  final double spacing;

  /// Diameter of one dot (a 0.55 radius circle).
  static const double _dotDiameter = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = _dotDiameter
      ..strokeCap = StrokeCap.round;
    // One draw call for the whole grid instead of one per dot.
    canvas.drawRawPoints(PointMode.points, dotPositions(size, spacing), paint);
  }

  /// Flat x,y coordinates of every dot centre that fits in [size].
  static Float32List dotPositions(Size size, double spacing) {
    final int columns = size.width <= spacing / 2
        ? 0
        : ((size.width - spacing / 2) / spacing).ceil();
    final int rows = size.height <= spacing / 2
        ? 0
        : ((size.height - spacing / 2) / spacing).ceil();
    final Float32List points = Float32List(columns * rows * 2);
    int i = 0;
    for (int row = 0; row < rows; row++) {
      final double y = spacing / 2 + row * spacing;
      for (int column = 0; column < columns; column++) {
        points[i++] = spacing / 2 + column * spacing;
        points[i++] = y;
      }
    }
    return points;
  }

  @override
  bool shouldRepaint(DotGridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.spacing != spacing;
  }
}
