import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A pill-shaped switcher at the top of the map that swaps the map's
/// population between circles (e.g. "Family" vs "Friends"). A trailing `+`
/// chip opens the "Join a Circle" flow.
class CircleSwitcher extends StatelessWidget {
  const CircleSwitcher({
    super.key,
    required this.circles,
    required this.selectedIndex,
    required this.onSelected,
    this.onJoinCircle,
  });

  final List<String> circles;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onJoinCircle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < circles.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _CircleChip(
                label: circles[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ],
            if (onJoinCircle != null) ...[
              const SizedBox(width: 4),
              _JoinChip(onTap: onJoinCircle!),
            ],
          ],
        ),
      ),
    );
  }
}

class _CircleChip extends StatelessWidget {
  const _CircleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// A labeled "Join a Circle" chip that opens the "Join a Circle" flow.
class _JoinChip extends StatelessWidget {
  const _JoinChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: AppColors.purple),
            SizedBox(width: 4),
            Text(
              'Join a Circle',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
