import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';
import 'member_avatar_bubble.dart';
import 'movement_icon.dart';

/// The Family member-list bottom panel on the map.
///
/// Self-contained and fully deterministic: the expanded/collapsed state is a
/// plain [State] flag toggled by tapping the header (or the chevron), so the
/// panel always works regardless of drag Gesture recognition in compact mode.
/// A slim handle remains as a purely visual affordance that the panel can be
/// raised; it is not required for interaction.
///
/// Collapsed it renders a short card: a drag handle, a tappable header (circle
/// name + member count + chevron + a round "+" add button), and a single row
/// of member avatar chips — so the family stays glanceable on the map. Tapping
/// the header expands it to the full list: header, a scrollable list of member
/// rows (battery % / ETA / speed chips + address), and an "Add a person" row
/// pinned at the bottom. The panel is anchored to the bottom and grows upward,
/// never covering the fixed control bar below it.
class MemberListSheet extends StatefulWidget {
  const MemberListSheet({
    super.key,
    required this.circleName,
    required this.members,
    this.onMemberTap,
    this.onAddPerson,
    this.onShowActions,
  });

  final String circleName;
  final List<Member> members;
  final ValueChanged<Member>? onMemberTap;

  /// Opens the "Add a person / Send Code" invite flow.
  final VoidCallback? onAddPerson;

  /// Opens the add-actions menu (Check In / Help Alert / Invite).
  final VoidCallback? onShowActions;

  @override
  State<MemberListSheet> createState() => _MemberListSheetState();
}

class _MemberListSheetState extends State<MemberListSheet> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final List<Member> members = widget.members;
    return _sheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DragHandle(),
          _buildHeader(context),
          if (_expanded)
            _buildFullList(members)
          else
            _buildCompactStrip(members),
        ],
      ),
    );
  }

  /// The shared gradient card with rounded top corners that wraps the panel so
  /// it blends with the map.
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

  /// Header row: circle name, member count, and on the trailing side a chevron
  /// that expands/collapses the panel plus a round "+" add button. The whole
  /// row is tappable so expanding never depends on a swipe gesture.
  Widget _buildHeader(BuildContext context) {
    final void Function()? showActions = widget.onShowActions;

    return InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
        child: Row(
          children: [
            Text(
              widget.circleName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            _CountChip(count: widget.members.length),
            const Spacer(),
            Icon(
              _expanded ? Icons.expand_more : Icons.expand_less,
              size: 22,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            _AddButton(onTap: showActions),
          ],
        ),
      ),
    );
  }

  /// Collapsed view: a single row of member avatars so the family stays
  /// glanceable without swallowing the map. The header above it remains
  /// tappable to expand the full list.
  Widget _buildCompactStrip(List<Member> members) {
    final List<Widget> chips = <Widget>[];
    final int shown = members.length < 8 ? members.length : 8;
    for (int i = 0; i < shown; i++) {
      final Member m = members[i];
      chips.add(
        _AvatarChip(member: m, onTap: () => widget.onMemberTap?.call(m)),
      );
    }
    final int rest = members.length - shown;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
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
    );
  }

  /// Expanded view: a scrollable list of full member rows (battery %, ETA,
  /// speed chips and address) plus an "Add a person" footer. The list is
  /// shrink-wrapped so the panel sizes itself to the content, but the panel's
  /// own max height (set by the enclosing [ConstrainedBox]) caps it and lets
  /// a long list scroll within that bound.
  Widget _buildFullList(List<Member> members) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListView.separated(
          shrinkWrap: true,
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
              onTap: () => widget.onMemberTap?.call(member),
            );
          },
        ),
        _AddPersonRow(onTap: widget.onAddPerson),
      ],
    );
  }
}

/// A small round "+" button in the panel header that opens the add-actions
/// menu (Check In / Help Alert / Invite).
class _AddButton extends StatelessWidget {
  const _AddButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add — Check In / Help Alert / Invite',
      child: Material(
        color: AppColors.purple.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.add, size: 20, color: AppColors.purple),
          ),
        ),
      ),
    );
  }
}

/// The drag handle pill at the top of the panel. Purely a visual affordance
/// (the panel is expanded/collapsed by tapping the header).
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
          color:
              member.isSpeeding ? const Color(0xFFE65100) : AppColors.purple,
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

/// "Add a person" row pinned at the bottom of the expanded member list.
class _AddPersonRow extends StatelessWidget {
  const _AddPersonRow({this.onTap});

  final VoidCallback? onTap;

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
              child: const Icon(
                Icons.person_add_alt_1,
                size: 20,
                color: AppColors.purple,
              ),
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