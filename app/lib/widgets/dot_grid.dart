import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subwiz-style 6px dot field. Paper stays undyed; lime stays on actions.
class DotGridBackground extends StatelessWidget {
  const DotGridBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BrandTheme brand = BrandTheme.of(context);
    return CustomPaint(
      painter: DotGridPainter(color: brand.dot),
      child: child,
    );
  }
}

class DotGridPainter extends CustomPainter {
  const DotGridPainter({required this.color, this.spacing = 6});

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.55, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DotGridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.spacing != spacing;
  }
}
