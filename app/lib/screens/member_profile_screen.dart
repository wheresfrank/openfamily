import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';
import '../widgets/member_avatar_bubble.dart';
import '../widgets/movement_icon.dart';
import 'day_detail_screen.dart';

/// A full-screen member profile: battery, location, and driving data, with a
/// purple location-pin "Day Detail" entry point at the bottom that opens the
/// location-history timeline.
///
/// Tapping a member bubble on the map opens this screen (not a modal bottom
/// sheet). Tapping a name in the member list still recenters the map.
class MemberProfileScreen extends StatelessWidget {
  const MemberProfileScreen({super.key, required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // Header: avatar + name + status.
          Row(
            children: [
              StatusAvatar(member: member, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.status.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: member.status.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _DetailRow(
            icon: Icon(_batteryIcon(), size: 22, color: _batteryColor()),
            label: 'Battery',
            value: member.batteryPercent > 0
                ? '${member.batteryPercent}%'
                : 'Offline',
          ),
          _DetailRow(
            icon: const Icon(Icons.schedule, size: 22, color: AppColors.purple),
            label: 'ETA',
            value: member.eta ?? '—',
          ),
          _DetailRow(
            icon: MovementIcon(
              movement: member.movement,
              size: 22,
              color: member.movement == MovementType.none
                  ? AppColors.textMuted
                  : null,
            ),
            label: 'Status',
            value: _drivingStatus(),
          ),
          _DetailRow(
            icon: const Icon(
              Icons.place_outlined,
              size: 22,
              color: AppColors.purple,
            ),
            label: 'Address',
            value: member.address,
          ),
          const SizedBox(height: 16),
          // Day Detail (location history) entry point.
          _DayDetailButton(member: member),
        ],
      ),
    );
  }

  IconData _batteryIcon() {
    if (member.batteryPercent <= 0) return Icons.battery_unknown;
    if (member.batteryPercent <= 20) return Icons.battery_1_bar;
    if (member.batteryPercent <= 50) return Icons.battery_3_bar;
    if (member.batteryPercent <= 80) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  Color _batteryColor() {
    if (member.batteryPercent <= 0) return AppColors.statusGrey;
    if (member.batteryPercent <= 20) return AppColors.statusRed;
    if (member.batteryPercent <= 50) return AppColors.statusOrange;
    return AppColors.statusGreen;
  }

  String _drivingStatus() {
    if (member.movement == MovementType.car && member.speedMph != null) {
      final String speed = '${member.speedMph} mph';
      return member.isSpeeding ? 'Speeding · $speed' : 'Driving · $speed';
    }
    if (member.movement == MovementType.none) return 'Not moving';
    return member.movement.label;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final Widget icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 22, child: Center(child: icon)),
          const SizedBox(width: 14),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The purple location-pin "Day Detail" entry point at the bottom of the
/// profile, opening the location-history timeline.
class _DayDetailButton extends StatelessWidget {
  const _DayDetailButton({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DayDetailScreen(member: member),
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.location_on, color: AppColors.purple, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Day Detail',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.purple,
                  ),
                ),
              ),
              Text(
                'Location history',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
