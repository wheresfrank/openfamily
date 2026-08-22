import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/member.dart';
import '../services/member_avatar_cache.dart';
import '../theme/app_theme.dart';
import 'movement_icon.dart';

/// A circular avatar bubble pinned to a member's location on the map.
///
/// The bubble is a circular photo avatar (or initials fallback) with a colored
/// status ring/outline around it, plus a small movement badge (car + speed,
/// bike, home, etc.) anchored to its bottom-right. A "location error" state
/// adds a red exclamation-mark badge. Tapping the bubble opens the member's
/// details.
class MemberAvatarBubble extends StatelessWidget {
  const MemberAvatarBubble({
    super.key,
    required this.member,
    this.onTap,
    this.radius = 22,
  });

  final Member member;
  final VoidCallback? onTap;

  /// Radius of the avatar circle in logical pixels.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String tooltip = _tooltip();

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: radius * 2 + 14,
            height: radius * 2 + 14,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                StatusAvatar(member: member, size: radius * 2 + 6),
                if (member.movement != MovementType.none)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: _MovementBadge(member: member),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Colorblind-safe, screen-reader-friendly description of this bubble.
  String _tooltip() {
    final StringBuffer sb = StringBuffer(member.name);
    sb.write(' — ${member.status.description}');
    if (member.movement != MovementType.none) {
      sb.write(' · ${member.movement.label}');
      if (member.movement == MovementType.car && member.speedMph != null) {
        sb.write(' ${member.speedMph} mph');
      }
    }
    return sb.toString();
  }
}

/// A circular photo avatar (or initials fallback) with a colored status
/// RING/OUTLINE around it — the bar's core "circular avatar bubble" +
/// "colored status circle/outline" visual.
///
/// The avatar is the member's photo (or initials on their accent color) at
/// full size; the status is a colored ring drawn *around* the photo, never a
/// fill behind it, so the ring stays visible even when a photo is present.
/// The red "location error" state additionally shows a red exclamation-mark
/// badge (not a filled disc) so the error is unmistakable.
class StatusAvatar extends StatefulWidget {
  const StatusAvatar({super.key, required this.member, this.size = 44});

  final Member member;
  final double size;

  @override
  State<StatusAvatar> createState() => _StatusAvatarState();
}

class _StatusAvatarState extends State<StatusAvatar> {
  Future<Uint8List?>? _avatarFuture;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant StatusAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_avatarMetadataChanged(oldWidget.member, widget.member)) {
      _loadAvatar();
    }
  }

  void _loadAvatar() {
    _avatarFuture = widget.member.hasAvatar
        ? MemberAvatarCache.instance.load(widget.member)
        : null;
  }

  bool _avatarMetadataChanged(Member before, Member after) {
    return before.id != after.id ||
        before.hasAvatar != after.hasAvatar ||
        before.avatarVersion != after.avatarVersion;
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = widget.member.status.color;
    final bool isError = widget.member.status == MemberStatus.error;
    final double ringWidth = _ringWidth(widget.size);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // The avatar itself: photo or initials, at full size.
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.member.avatarColor,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: _avatarOrInitials(),
            ),
          ),
          // Status ring drawn on top, around the avatar (never behind it).
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: statusColor, width: ringWidth),
            ),
          ),
          // Red exclamation-mark badge for the location-error state.
          if (isError)
            Positioned(
              top: -ringWidth,
              right: -ringWidth,
              child: _ErrorBadge(size: widget.size),
            ),
        ],
      ),
    );
  }

  /// Loads only authenticated image bytes. Until that request completes (or
  /// if it fails), preserve the familiar initials fallback.
  Widget _avatarOrInitials() {
    final Future<Uint8List?>? avatarFuture = _avatarFuture;
    if (avatarFuture == null) return _initials();

    return FutureBuilder<Uint8List?>(
      future: avatarFuture,
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
        final Uint8List? bytes = snapshot.data;
        if (bytes == null) return _initials();
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _initials(),
        );
      },
    );
  }

  Widget _initials() {
    return Center(
      child: Text(
        widget.member.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: widget.size * 0.4,
        ),
      ),
    );
  }

  /// Ring thickness scaled to the avatar size so it stays glanceable on the
  /// map (small) and in the profile (large).
  double _ringWidth(double s) {
    final double w = s * 0.08;
    if (w < 2.5) return 2.5;
    if (w > 4.5) return 4.5;
    return w;
  }
}

/// A small red exclamation-mark badge anchored to the top-right of an avatar,
/// used for the "location error" state. It is a red badge with a white
/// exclamation mark — not a filled disc replacing the avatar.
class _ErrorBadge extends StatelessWidget {
  const _ErrorBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final double raw = size * 0.42;
    final double badgeSize = raw < 16.0 ? 16.0 : (raw > 24.0 ? 24.0 : raw);
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.statusRed,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text(
          '!',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: badgeSize * 0.62,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A cluster bubble shown when many members are near each other.
///
/// Instead of a bare "N" count, it renders an identity preview: up to three
/// stacked/overlapping member avatars plus a small count badge, so the user
/// can glance at *who* is clustered, not just how many. Each avatar keeps its
/// colored status ring (and error badge), and each moving member keeps its
/// movement badge below the stack — so low-battery / offline / driving /
/// speeding states stay glanceable even when clustered.
class ClusterBubble extends StatelessWidget {
  const ClusterBubble({super.key, required this.members, this.onTap});

  final List<Member> members;
  final VoidCallback? onTap;

  static const double _avatarSize = 30;
  static const double _overlap = 14;

  @override
  Widget build(BuildContext context) {
    final int count = members.length;
    final List<Member> preview = members.take(3).toList();
    final double stackWidth = _avatarSize + _overlap * (preview.length - 1);
    final List<Member> moving =
        preview.where((m) => m.movement != MovementType.none).toList();
    final String label = _label();

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Overlapping avatars, each with its status ring + error badge.
              SizedBox(
                width: stackWidth + 22,
                height: _avatarSize + 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (int i = 0; i < preview.length; i++)
                      Positioned(
                        left: i * _overlap,
                        top: 0,
                        child: StatusAvatar(
                          member: preview[i],
                          size: _avatarSize,
                        ),
                      ),
                    Positioned(
                      left: stackWidth - 4,
                      bottom: 0,
                      child: _CountBadge(count: count),
                    ),
                  ],
                ),
              ),
              // Movement badges for each moving member, so driving / speeding
              // (and other movement) stays visible when clustered.
              if (moving.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < moving.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _MovementBadge(member: moving[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Colorblind-safe, screen-reader-friendly description of the cluster.
  String _label() {
    final StringBuffer sb = StringBuffer('${members.length} people here');
    for (final Member m in members.take(3)) {
      sb.write(' · ${m.name}: ${m.status.description}');
      if (m.movement != MovementType.none) {
        sb.write(' ${m.movement.label}');
        if (m.movement == MovementType.car && m.speedMph != null) {
          sb.write(' ${m.speedMph} mph');
        }
      }
    }
    return sb.toString();
  }
}

/// A small purple count badge anchored to a cluster bubble.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Small circular badge showing the movement icon and, for driving, the speed.
/// A speeding driver is shown as a "race car with flames".
class _MovementBadge extends StatelessWidget {
  const _MovementBadge({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final bool speeding = member.isSpeeding;
    final bool showSpeed =
        member.movement == MovementType.car && member.speedMph != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showSpeed ? 6 : 4,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: speeding ? const Color(0xFFFFF3E0) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: speeding ? const Color(0xFFFFB74D) : const Color(0x22000000),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (speeding)
            const RaceCarIcon(size: 16)
          else
            MovementIcon(movement: member.movement, size: 13),
          if (showSpeed) ...[
            const SizedBox(width: 3),
            Text(
              '${member.speedMph} mph',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: speeding ? const Color(0xFFE65100) : Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
