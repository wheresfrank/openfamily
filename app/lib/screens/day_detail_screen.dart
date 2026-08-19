import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';
import '../widgets/member_avatar_bubble.dart';
import '../widgets/movement_icon.dart';

/// "Day Detail" — the location-history timeline for a member.
///
/// Renders the member's day as a vertical timeline of past locations with
/// times (and a movement icon where relevant), ending at their current
/// location. When the member has no backend history yet, a plausible
/// synthetic day is generated so the timeline is always demonstrable.
class DayDetailScreen extends StatelessWidget {
  const DayDetailScreen({super.key, required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final List<LocationHistoryEntry> entries = _buildTimeline(member);

    return Scaffold(
      appBar: AppBar(title: const Text('Day Detail')),
      body: Column(
        children: [
          _Header(member: member),
          const Divider(height: 1, color: Color(0x11000000)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              itemCount: entries.length,
              itemBuilder: (context, index) => _TimelineEntry(
                entry: entries[index],
                isLast: index == entries.length - 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the member's real history when present, otherwise synthesizes a
  /// plausible day ending at the member's current location.
  List<LocationHistoryEntry> _buildTimeline(Member member) {
    if (member.history.isNotEmpty) return member.history;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    return <LocationHistoryEntry>[
      LocationHistoryEntry(
        time: today.add(const Duration(hours: 7, minutes: 30)),
        address: 'Home · 123 Maple St',
        movement: MovementType.home,
      ),
      LocationHistoryEntry(
        time: today.add(const Duration(hours: 8, minutes: 15)),
        address: 'Driving · Market St',
        movement: MovementType.car,
      ),
      LocationHistoryEntry(
        time: today.add(const Duration(hours: 8, minutes: 45)),
        address: 'Work · 1 Embarcadero',
        movement: MovementType.work,
      ),
      LocationHistoryEntry(
        time: today.add(const Duration(hours: 12, minutes: 10)),
        address: 'Lunch · Ferry Building',
        movement: MovementType.none,
      ),
      LocationHistoryEntry(
        time: today.add(const Duration(hours: 13, minutes: 0)),
        address: 'Work · 1 Embarcadero',
        movement: MovementType.work,
      ),
      LocationHistoryEntry(
        time: today.add(const Duration(hours: 17, minutes: 30)),
        address: 'Driving · Market St',
        movement: MovementType.car,
      ),
      LocationHistoryEntry(
        time: now,
        address: member.address,
        movement: member.movement,
      ),
    ];
  }
}

/// Header showing the member's avatar, name, and the day's date.
class _Header extends StatelessWidget {
  const _Header({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          StatusAvatar(member: member, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(DateTime.now()),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single row of the timeline: time, a dot with a connecting line, and the
/// location (with a movement icon where relevant).
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry, required this.isLast});

  final LocationHistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = entry.movement == MovementType.none
        ? AppColors.textMuted
        : AppColors.purple;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time.
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatTime(entry.time),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Dot + connecting line.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0x22000000),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Location + movement.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.address,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (entry.movement != MovementType.none) ...[
                    const SizedBox(width: 8),
                    MovementIcon(movement: entry.movement, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final int hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String minute = t.minute.toString().padLeft(2, '0');
  final String ampm = t.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $ampm';
}

String _formatDate(DateTime d) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
