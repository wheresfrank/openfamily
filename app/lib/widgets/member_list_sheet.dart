import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';
import 'member_avatar_bubble.dart';
import 'movement_icon.dart';

/// The member list that lives inside the draggable bottom sheet on the map.
///
/// When the sheet is collapsed it renders a slim [compact] strip — a single
/// row of member avatars — so the family is glanceable without swallowing the
/// map. Dragging the sheet up expands it to the full list: a drag handle, the
/// circle header, a scrollable list of member rows, and an "Add a person" row
/// pinned at the bottom. The list is driven by the [scrollController] supplied
/// by the enclosing [DraggableScrollableSheet] so dragging also drags the sheet.
class MemberListSheet extends StatelessWidget {
  const MemberListSheet({
    super.key,
    required this.scrollController,
    required this.circleName,
    required this.members,
    required this.onMemberTap,
    required this.onAddPerson,
    // When true (sheet collapsed), renders a slim avatar strip instead of the
    // full rows, so the family takes far less room when you are not using it.
    this.compact = false,
  });

  final ScrollController scrollController;
  final String circleName;
  final List<Member> members;
  final ValueChanged<Member> onMemberTap;
  final VoidCallback onAddPerson;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _sheetSurface(
      child: compact ? _buildCompact() : _buildFull(),
    );
  }

  /// The shared gradient card with rounded top corners that wraps either the
  /// compact strip or the full member list, so both blend with the map.
  Container _sheetSurface({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppGradients.softPurple,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Collapsed view: a drag handle, a compact header, and a single row of
  /// member avatars. Much shorter than the full list, so the map gets the
  /// room back, while members stay visible and tappable at a glance.
  Widget _buildCompact() {
    final List<Widget> chips = <Widget>[];
    final int shown = members.length < 8 ? members.length : 8;
    for (int i = 0; i < shown; i++) {
      final Member m = members[i];
      chips.add(
        _AvatarChip(member: m, onTap: () => onMemberTap(m)),
      );
    }
    final int rest = members.length - shown;

    return Column(
      children: [
        _DragHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(
            children: [
              Text(
                circleName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              _CountChip(count: members.length),
              const Spacer(),
              const Text(
                'Swipe up for the full list',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...chips,
              if (rest > 0)
                Text(
                  '+$rest',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Expanded view: the original full member list (header, scrollable rows,
  /// and the "Add a person" footer).
  Widget _buildFull() {
    return Column(
      children: [
        // Drag handle.
        _DragHandle(),
        // Header.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Row(
            children: [
              Text(
                circleName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              _CountChip(count: members.length),
            ],
          ),
        ),
        // Member rows — the full row (battery %, ETA, address) is always
        // visible here so members stay glanceable with full context.
        Expanded(
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              indent: 76,
              color: Color(0x11000000),
            ),
            itemBuilder: (context, index) {
              final Member member = members[index];
              return _MemberRow(
                member: member,
                onTap: () => onMemberTap(member),
              );
            },
          ),
        ),
        // Add a person.
        _AddPersonRow(onTap: onAddPerson),
      ],
    );
  }
}

/// The drag handle pill at the top of the sheet.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// The purple pill showing the number of members in the circle.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.purple,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A single member's avatar shown in the compact collapsed strip.
class _AvatarChip extends StatelessWidget {
  const _AvatarChip({required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: member.name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: StatusAvatar(member: member, size: 38),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusAvatar(member: member, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Distinct glanceable fields: battery %, ETA, speed — each
                  // its own chip, never collapsed into one ellipsized line.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: _statusChips(),
                  ),
                  const SizedBox(height: 4),
                  // Address on its own line.
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          member.position == null
                              ? 'No location yet'
                              : member.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (member.movement != MovementType.none) ...[
              const SizedBox(width: 8),
              MovementIcon(movement: member.movement, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the distinct status chips: battery %, ETA, and driving speed.
  List<Widget> _statusChips() {
    final List<Widget> chips = <Widget>[];

    if (member.batteryPercent > 0) {
      chips.add(
        _StatusChip(
          icon: _batteryIcon(),
          color: _batteryColor(),
          label: '${member.batteryPercent}%',
        ),
      );
    } else if (member.status == MemberStatus.stopped) {
      chips.add(
        const _StatusChip(
          icon: Icons.battery_unknown,
          color: AppColors.statusGrey,
          label: 'Offline',
        ),
      );
    }

    if (member.eta != null) {
      chips.add(
        _StatusChip(
          icon: Icons.schedule,
          color: AppColors.purple,
          label: 'ETA ${member.eta}',
        ),
      );
    }

    if (member.movement == MovementType.car && member.speedMph != null) {
      chips.add(
        _StatusChip(
          icon: Icons.directions_car,
          color: member.isSpeeding
              ? const Color(0xFFE65100)
              : AppColors.purple,
          label: '${member.speedMph} mph',
        ),
      );
    }

    return chips;
  }

  IconData _batteryIcon() {
    if (member.batteryPercent <= 20) return Icons.battery_1_bar;
    if (member.batteryPercent <= 50) return Icons.battery_3_bar;
    if (member.batteryPercent <= 80) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  Color _batteryColor() {
    if (member.batteryPercent <= 20) return AppColors.statusRed;
    if (member.batteryPercent <= 50) return AppColors.statusOrange;
    return AppColors.statusGreen;
  }
}

/// A small pill chip showing one glanceable status field (battery %, ETA,
/// speed) with a leading icon, so each field stays visually distinct.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    this.color = AppColors.purple,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add a person" row pinned at the bottom of the member list.
class _AddPersonRow extends StatelessWidget {
  const _AddPersonRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.purple.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.person_add_alt_1, size: 20, color: AppColors.purple),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add a person',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.purple,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Send Code to invite',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}