import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/family_management_service.dart';
import '../theme/app_theme.dart';
import 'create_circle_screen.dart';
import 'invite_screen.dart';
import 'join_circle_screen.dart';

/// Family administration for the currently signed-in user.
///
/// Family admins can rename the family, issue invites, change member roles, and
/// remove members. Users without a family can create one or join with an invite
/// code from this screen.
class FamilyManagementScreen extends StatefulWidget {
  const FamilyManagementScreen({super.key});

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen> {
  bool _loading = true;
  bool _savingName = false;
  bool _hasFamily = false;
  String _familyName = '';
  String _role = 'member';
  String _userId = '';
  String? _error;
  List<ManagedFamilyMember> _members = <ManagedFamilyMember>[];
  late final TextEditingController _name = TextEditingController();

  bool get _isAdmin => _role == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final Map<String, dynamic> family = await FamilyManagementService.fetchFamily();
      final List<ManagedFamilyMember> members = await FamilyManagementService.fetchMembers();
      if (!mounted) return;
      setState(() {
        _hasFamily = true;
        _familyName = family['name'] as String? ?? 'Family';
        _name.text = _familyName;
        _role = family['role'] as String? ?? 'member';
        _userId = family['user_id'] as String? ?? '';
        _members = members;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _hasFamily = e.status != 404;
        _loading = false;
        _error = e.status == 404 ? null : e.message;
        _members = <ManagedFamilyMember>[];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load family settings. Check your connection and try again.';
      });
    }
  }

  Future<void> _rename() async {
    final String name = _name.text.trim();
    if (name.isEmpty || _savingName) return;
    setState(() => _savingName = true);
    try {
      await FamilyManagementService.renameFamily(name);
      if (!mounted) return;
      setState(() => _familyName = name);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family renamed')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeRole(ManagedFamilyMember member, String role) async {
    try {
      await FamilyManagementService.updateRole(member.id, role);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(ManagedFamilyMember member) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove member?'),
            content: Text('${member.name} will keep their account but leave this family.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await FamilyManagementService.removeMember(member.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openInvite() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InviteScreen(circleName: _familyName))).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Family management')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _hasFamily
              ? _buildFamily()
              : _buildNoFamily(),
    );
  }

  Widget _buildNoFamily() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.groups_outlined, size: 64, color: AppColors.purple),
          const SizedBox(height: 16),
          const Text('You are not in a family yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Create a family or join one with an invite code.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CreateCircleScreen(onCreated: () { _load(); }))), child: const Text('Create family')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JoinCircleScreen(onDone: () { _load(); }, closeOnDone: true))), child: const Text('Join with invite code')),
        ],
      ),
    );
  }

  Widget _buildFamily() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: _name, enabled: _isAdmin, decoration: const InputDecoration(labelText: 'Family name', border: OutlineInputBorder())),
                if (_isAdmin) ...[
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _savingName ? null : _rename, child: _savingName ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save family name')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _openInvite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Invite a person')),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text('Members', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._members.map(_memberTile),
        ],
      ),
    );
  }

  Widget _memberTile(ManagedFamilyMember member) {
    final bool isSelf = member.id == _userId;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase())),
        title: Text(isSelf ? '${member.name} (You)' : member.name),
        subtitle: Text(member.email),
        trailing: _isAdmin
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                DropdownButton<String>(value: member.role, onChanged: isSelf ? null : (value) { if (value != null) _changeRole(member, value); }, items: const [DropdownMenuItem(value: 'admin', child: Text('Admin')), DropdownMenuItem(value: 'member', child: Text('Member')), DropdownMenuItem(value: 'child', child: Text('Child'))]),
                IconButton(tooltip: 'Remove member', onPressed: isSelf ? null : () => _remove(member), icon: const Icon(Icons.person_remove_outlined)),
              ])
            : Text(member.role),
      ),
    );
  }
}
