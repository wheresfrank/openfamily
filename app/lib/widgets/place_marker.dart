import 'package:flutter/material.dart';

import '../models/place.dart';
import '../theme/app_theme.dart';

/// A saved place on the map: a lime icon badge with its name in a readable
/// label under it. Tapping it reports through [onTap]. The place's arrive/leave
/// radius is drawn separately by the map as a circle.
class PlaceMarker extends StatelessWidget {
  const PlaceMarker({super.key, required this.place, this.onTap});

  /// Width of the marker, wide enough for a short name under the badge.
  static const double width = 104;

  /// Height of the badge plus one line of label.
  static const double height = 62;

  final Place place;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BrandTheme brand = BrandTheme.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: onTap != null,
        label: place.name,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x44000000), blurRadius: 4),
                ],
              ),
              // Ink on lime: white would be only 1.8:1.
              child: Icon(place.icon, color: AppColors.onAccent, size: 18),
            ),
            const SizedBox(height: 3),
            Container(
              constraints: const BoxConstraints(maxWidth: width),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: brand.sheet.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: brand.accentInk.withValues(alpha: 0.7),
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 3),
                ],
              ),
              child: Text(
                place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
