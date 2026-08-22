import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An emergency contact. They do not need the app or to be family members.
class _Contact {
  _Contact({required this.name, required this.phone, required this.relation});

  final String name;
  final String phone;
  final String relation;
}

/// The Safety screen. Manages emergency contacts (who receive SOS alerts) and
/// links to SOS setup.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  final List<_Contact> _contacts = <_Contact>[
    _Contact(name: 'Mom', phone: '(415) 555-0132', relation: 'Family'),
    _Contact(name: 'Dad', phone: '(415) 555-0177', relation: 'Family'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Emergency contacts receive your SOS alerts with your location. '
              'They do not need the app or to be in your family.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          for (final _Contact c in _contacts)
            _ContactTile(
              contact: c,
              onRemove: () => setState(() => _contacts.remove(c)),
            ),
          _AddContactTile(onTap: _addContact),
        ],
      ),
    );
  }

  void _addContact() {
    final TextEditingController name = TextEditingController();
    final TextEditingController phone = TextEditingController();
    showDialog<void>(
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
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final String n = name.text.trim();
              final String p = phone.text.trim();
              if (n.isNotEmpty && p.isNotEmpty) {
                setState(() {
                  _contacts.add(
                    _Contact(name: n, phone: p, relation: 'Contact'),
                  );
                });
              }
              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onRemove});

  final _Contact contact;
  final VoidCallback onRemove;

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
      subtitle: Text('${contact.phone} · ${contact.relation}'),
      trailing: IconButton(
        tooltip: 'Remove',
        icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
        onPressed: onRemove,
      ),
    );
  }
}

class _AddContactTile extends StatelessWidget {
  const _AddContactTile({required this.onTap});

  final VoidCallback onTap;

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
