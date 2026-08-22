import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';
import '../widgets/member_tile.dart';
import 'invite_screen.dart';
import 'member_profile_screen.dart';

/// The dedicated, full-screen home for a circle's family members.
///
/// This is the replacement for the old map drawer: a proper [Scaffold] with an
/// app bar (mirroring Places / Keys / Safety), reached from the map's bottom
/// action bar. It shows the live member roster — the same rich `MemberTile`
/// rows the drawer used — plus an Invite action and a tap-through to each
/// member's profile.
///
/// The list is driven by a [ValueListenable] so status chips (battery, ETA,
/// movement) stay live while the screen is open, fed by the map screen's
/// single WebSocket subscription rather than a second connection.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({
    super.key,
    required this.circleName,
    required this.members,
    this.onInvite,
  });

  /// The circle / family name, shown in the roster header.
  final String circleName;

  /// Live family members from the map screen's single family subscription.
  final ValueListenable<List<Member>> members;

  /// Optionally override the invite action (used by tests). Defaults to
  /// pushing the standard [InviteScreen].
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'People',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _invite(context),
            tooltip: 'Invite someone',
            icon: const Icon(
              Icons.person_add_alt_1,
              color: AppColors.purple,
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Member>>(
        valueListenable: members,
        builder: (context, roster, _) {
          if (roster.isEmpty) {
            return _EmptyPeople(
              circleName: circleName,
              onInvite: _invite(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: roster.length + 1,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              // Row 0 is the roster header; the rest are members.
              if (index == 0) {
                return _RosterHeader(
                    circleName: circleName, count: roster.length);
              }
              final Member member = roster[index - 1];
              return MemberTile(
                member: member,
                onTap: () => _openMember(context, member),
              );
            },
          );
        },
      ),
    );
  }

  /// The invite callback: the injected override wins, otherwise push the
  /// standard Invite flow.
  VoidCallback _invite(BuildContext context) {
    final VoidCallback? override = onInvite;
    if (override != null) return override;
    return () {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InviteScreen(circleName: circleName),
        ),
      );
    };
  }

  void _openMember(BuildContext context, Member member) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberProfileScreen(member: member),
      ),
    );
  }
}

/// The roster header: which circle is shown and how many members it has.
class _RosterHeader extends StatelessWidget {
  const _RosterHeader({required this.circleName, required this.count});

  final String circleName;
  final int count;

  @override
  Widget build(BuildContext context) {
    final String countLabel = '$count ${count == 1 ? 'member' : 'members'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  circleName,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  countLabel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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

/// Shown when the circle has no members yet — invites someone to see them on
/// the map.
class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople({required this.circleName, required this.onInvite});

  final String circleName;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_alt_outlined,
                  size: 34, color: AppColors.purple),
            ),
            const SizedBox(height: 16),
            Text(
              'No one is in $circleName yet',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Invite family to share their location and see them on your map.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Invite someone'),
            ),
          ],
        ),
      ),
    );
  }
}
