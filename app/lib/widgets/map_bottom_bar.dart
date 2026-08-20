import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The fixed bottom control bar, pinned to the very bottom of the map screen.
///
/// It is *always* visible — the Family member panel sits directly above this
/// bar and stops *above* it, so the controls are never covered. Layout, left
/// to right:
///
/// * a large, prominent **SOS** button (emergency red but flat at rest,
///   escalating to intense red only during an active SOS countdown),
/// * **Places** and **Keys** as small circular icon buttons,
/// * **Safety** as a labeled *tab* (icon + text, not a bare circle),
/// * a **Settings** gear pinned to the bottom-right corner as a distinct
///   corner element.
///
/// The widget is transparent — it renders only the controls — so the map stays
/// full-bleed behind it. The `+` add action lives inside the Family panel's
/// header, above this bar.
class MapBottomBar extends StatelessWidget {
  const MapBottomBar({
    super.key,
    this.onSos,
    this.onPlaces,
    this.onKeys,
    this.onSafety,
    this.onSettings,
    this.sosIntense = false,
  });

  final VoidCallback? onSos;
  final VoidCallback? onPlaces;
  final VoidCallback? onKeys;
  final VoidCallback? onSafety;
  final VoidCallback? onSettings;

  /// When true, the SOS button escalates to intense red (an active countdown).
  /// The map screen keeps this false; the countdown escalation lives on the
  /// SOS screen. Exposed so a future design that keeps the map visible during
  /// a countdown can wire it to shared state.
  final bool sosIntense;

  /// Height of the SOS button.
  static const double sosHeight = 72;

  /// Total height of the bar (SOS button + 8px vertical padding on each side).
  /// Exposed so the map screen can reserve space and anchor the Family panel
  /// above it.
  static const double height = sosHeight + 16;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large, dominant SOS button — clearly bigger than the other controls.
          _SosButton(onTap: onSos, intense: sosIntense),
          const SizedBox(width: 12),
          // Places.
          _FloatingIconButton(
            icon: Icons.place_outlined,
            label: 'Places',
            onTap: onPlaces,
          ),
          const SizedBox(width: 8),
          // Keys / Tile.
          _FloatingIconButton(
            icon: Icons.key_outlined,
            label: 'Keys',
            onTap: onKeys,
          ),
          const SizedBox(width: 8),
          // Safety — a white circular icon button, matching Places / Keys.
          _FloatingIconButton(
            icon: Icons.shield_outlined,
            label: 'Safety',
            onTap: onSafety,
          ),
          const Spacer(),
          // Settings — a white circular icon button, matching Places / Keys,
          // pinned to the bottom-right corner.
          _FloatingIconButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

/// A large, prominent SOS button floating over the map. It is a tall rounded
/// rectangle (not a small circle) so it reads as the dominant control.
///
/// At rest it is emergency red but flat (no glow/elevation), so it is
/// prominent yet not alarming. It escalates to a deeper intense red with a red
/// glow only when [intense] is true — i.e. during an actual SOS countdown.
class _SosButton extends StatelessWidget {
  const _SosButton({this.onTap, this.intense = false});

  final VoidCallback? onTap;
  final bool intense;

  @override
  Widget build(BuildContext context) {
    final Color fill = intense ? AppColors.sosIntenseRed : AppColors.sosRed;
    return Semantics(
      button: true,
      label: 'SOS — send emergency alert',
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(24),
        // At rest: emergency red, flat (no glow/elevation) so it is prominent
        // yet not alarming. Intense: escalate to a deeper red with a red glow.
        elevation: intense ? 8 : 0,
        shadowColor: intense ? AppColors.sosIntenseRed : Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            height: MapBottomBar.sosHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the "SOS" word is drawn. The `sos` glyph icon already
                // renders the letters "SOS", so drawing both would read the
                // word twice — keep just the text.
                Text(
                  'SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small circular icon button floating over the map (Places, Keys, Safety,
/// Settings). A white disc with a purple glyph and a soft shadow, which is how
/// every secondary map control reads consistently.
class _FloatingIconButton extends StatelessWidget {
  const _FloatingIconButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: AppColors.purple, size: 22),
          ),
        ),
      ),
    );
  }
}
