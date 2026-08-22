import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

class _Contact {
  const _Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
  });

  final String id;
  final String name;
  final String phone;
  final String relation;
}

/// The Safety screen. Manages emergency contacts who receive SOS SMS even
/// without the app.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  List<_Contact> _contacts = <_Contact>[];
  bool _loading = true;
  String? _error;
  bool _canManage = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final UserProfileRole role = await _loadRole();
      final dynamic raw = await ApiClient.get('/me/contacts');
      final List<_Contact> contacts = <_Contact>[];
      if (raw is List) {
        for (final dynamic row in raw) {
          if (row is! Map) continue;
          final Map<String, dynamic> map = Map<String, dynamic>.from(row);
          contacts.add(
            _Contact(
              id: map['id'] as String? ?? '',
              name: map['name'] as String? ?? 'Contact',
              phone: map['phone'] as String? ?? '',
              relation: map['relation'] as String? ?? '',
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _canManage = role != UserProfileRole.child;
        _loading = false;
      });
    } on SessionExpiredException {
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load emergency contacts.';
      });
    }
  }

  Future<UserProfileRole> _loadRole() async {
    try {
      final profile = await ApiClient.getProfile();
      switch (profile.role) {
        case 'child':
          return UserProfileRole.child;
        default:
          return UserProfileRole.manager;
      }
    } catch (_) {
      return UserProfileRole.manager;
    }
  }

  Future<void> _addContact() async {
    if (!_canManage || _busy) return;
    final TextEditingController name = TextEditingController();
    final TextEditingController phone = TextEditingController();
    final TextEditingController relation = TextEditingController();
    final bool? added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add emergency contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: '+15551234567',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relation,
              decoration: const InputDecoration(
                labelText: 'Relation (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added != true || !mounted) {
      name.dispose();
      phone.dispose();
      relation.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.post(
        '/me/contacts',
        body: <String, dynamic>{
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'relation': relation.text.trim(),
        },
      );
      await _load();
    } on SessionExpiredException {
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t add that contact.')),
      );
    } finally {
      name.dispose();
      phone.dispose();
      relation.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeContact(_Contact contact) async {
    if (!_canManage || _busy) return;
    setState(() => _busy = true);
    try {
      await ApiClient.delete('/me/contacts/${contact.id}');
      await _load();
    } on SessionExpiredException {
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t remove that contact.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Text(
                        'Emergency contacts get an SMS for SOS even if they '
                        'do not have the app. They need a reachable number in '
                        'E.164 format, and the server operator must configure '
                        'Twilio. Family members still get in-app alerts.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ),
                    if (_contacts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Text(
                          'No emergency contacts yet. Add someone who should '
                          'be texted when you send SOS.',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    for (final _Contact c in _contacts)
                      _ContactTile(
                        contact: c,
                        onRemove: _canManage ? () => _removeContact(c) : null,
                      ),
                    if (_canManage)
                      _AddContactTile(onTap: _busy ? null : _addContact)
                    else
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          'A parent or family admin manages emergency contacts.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

enum UserProfileRole { manager, child }

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, this.onRemove});

  final _Contact contact;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.purple.withValues(alpha: 0.12),
        ),
        child: const Icon(Icons.person, color: AppColors.purple, size: 22),
      ),
      title: Text(
        contact.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        contact.relation.isEmpty
            ? contact.phone
            : '${contact.phone} · ${contact.relation}',
      ),
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
              onPressed: onRemove,
            ),
    );
  }
}

class _AddContactTile extends StatelessWidget {
  const _AddContactTile({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.add_circle_outline, color: AppColors.purple),
      title: const Text(
        'Add emergency contact',
        style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
