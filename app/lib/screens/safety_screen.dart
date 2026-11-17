import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/emergency_contact.dart';
import '../services/api_client.dart';
import '../services/contact_picker.dart';
import '../services/emergency_contact_service.dart';
import '../services/server_features.dart';
import '../theme/app_theme.dart';

/// The Safety screen. Manages emergency contacts (who receive SOS alerts).
///
/// Contacts are picked from the phone's address book and stored on the
/// server so they survive leaving this screen.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({
    super.key,
    this.contactService,
    this.contactPicker,
    this.smsConfigured,
  });

  final EmergencyContactService? contactService;
  final ContactPicker? contactPicker;

  /// When null, uses [ServerFeatures.smsConfigured].
  final bool? smsConfigured;

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  late final EmergencyContactService _service;
  late final ContactPicker _picker;

  List<EmergencyContact>? _contacts;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service = widget.contactService ?? EmergencyContactService();
    _picker = widget.contactPicker ?? NativeContactPicker();
    if (_smsConfigured) {
      _load();
    }
  }

  bool get _smsConfigured =>
      widget.smsConfigured ?? ServerFeatures.instance.smsConfigured;

  Future<void> _load() async {
    setState(() {
      _contacts = null;
      _error = null;
    });
    try {
      final List<EmergencyContact> contacts = await _service.list();
      if (!mounted) return;
      setState(() => _contacts = contacts);
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e,
          fallback: context.l10n.loadContactsFailed));
    }
  }

  String _errorMessage(Object e, {required String fallback}) {
    if (e is ApiException) return e.message;
    return fallback;
  }

  Future<void> _addFromPhone() async {
    if (_saving) return;
    try {
      final PickedPhoneContact? picked = await _picker.pickPhoneContact();
      if (picked == null || !mounted) return;

      final String? phone = await _phoneForPickedContact(picked);
      if (phone == null || !mounted) return;

      await _saveContact(name: picked.name, phone: phone);
    } on ContactHasNoPhoneException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.contactNoPhone),
        ),
      );
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _errorMessage(e, fallback: context.l10n.openContactsFailed),
          ),
        ),
      );
    }
  }

  /// Picks which number to save when the address-book entry has several.
  Future<String?> _phoneForPickedContact(PickedPhoneContact picked) async {
    final String? selected = picked.selectedPhone;
    if (selected != null && selected.isNotEmpty) return selected;
    if (picked.phones.length == 1) return picked.phones.first;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  context.l10n.whichNumberFor(picked.name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final String phone in picked.phones)
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(phone),
                  onTap: () => Navigator.of(context).pop(phone),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addManually() async {
    if (_saving) return;
    final _DraftContact? draft = await showDialog<_DraftContact>(
      context: context,
      builder: (BuildContext context) => const _ManualContactDialog(),
    );
    if (draft == null || !mounted) return;
    await _saveContact(name: draft.name, phone: draft.phone);
  }

  Future<void> _saveContact({
    required String name,
    required String phone,
  }) async {
    setState(() => _saving = true);
    try {
      final EmergencyContact created = await _service.add(
        name: name,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _contacts = <EmergencyContact>[...?_contacts, created];
      });
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _errorMessage(
              e,
              fallback: context.l10n.saveContactFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      } else {
        _saving = false;
      }
    }
  }

  Future<void> _removeContact(EmergencyContact contact) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.removeContactQuestion),
        content: Text(
          context.l10n.stopSosAlertsTo(contact.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.actionRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.delete(contact.id);
      if (!mounted) return;
      setState(() {
        _contacts = _contacts!
            .where((EmergencyContact c) => c.id != contact.id)
            .toList();
      });
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _errorMessage(
              e,
              fallback: context.l10n.removeContactFailed,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.safetyTitle)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_smsConfigured) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            context.l10n.smsNotConfigured,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: BrandTheme.of(context).muted),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(context.l10n.actionRetry)),
            ],
          ),
        ),
      );
    }
    final List<EmergencyContact>? contacts = _contacts;
    if (contacts == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            context.l10n.emergencyContactsExplainer,
            style: TextStyle(fontSize: 13, color: BrandTheme.of(context).muted),
          ),
        ),
        if (contacts.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              context.l10n.noEmergencyContacts,
              style: TextStyle(fontSize: 13, color: BrandTheme.of(context).muted),
            ),
          ),
        for (final EmergencyContact c in contacts)
          _ContactTile(
            contact: c,
            onRemove: () => _removeContact(c),
          ),
        _AddContactTile(
          enabled: !_saving && contacts.length < 10,
          onTap: _addFromPhone,
        ),
        ListTile(
          leading:
              Icon(Icons.keyboard_outlined, color: BrandTheme.of(context).muted),
          title: Text(
            context.l10n.typeNameAndNumber,
            style: TextStyle(color: BrandTheme.of(context).muted),
          ),
          enabled: !_saving && contacts.length < 10,
          onTap: _addManually,
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onRemove});

  final EmergencyContact contact;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final String subtitle = contact.relation.isEmpty
        ? contact.phone
        : '${contact.phone} · ${contact.relation}';
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.purple.withValues(alpha: 0.12),
        ),
        child: Icon(Icons.person, color: BrandTheme.of(context).accentInk, size: 22),
      ),
      title: Text(
        contact.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: context.l10n.actionRemove,
        icon: Icon(Icons.delete_outline, color: BrandTheme.of(context).muted),
        onPressed: onRemove,
      ),
    );
  }
}

class _AddContactTile extends StatelessWidget {
  const _AddContactTile({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.contacts_outlined,
        color: enabled ? BrandTheme.of(context).accentInk : BrandTheme.of(context).muted,
      ),
      title: Text(
        context.l10n.chooseFromContacts,
        style: TextStyle(
          color: enabled ? BrandTheme.of(context).accentInk : BrandTheme.of(context).muted,
          fontWeight: FontWeight.w600,
        ),
      ),
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _DraftContact {
  const _DraftContact({required this.name, required this.phone});

  final String name;
  final String phone;
}

class _ManualContactDialog extends StatefulWidget {
  const _ManualContactDialog();

  @override
  State<_ManualContactDialog> createState() => _ManualContactDialogState();
}

class _ManualContactDialogState extends State<_ManualContactDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  String? _nameError;
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    final String phone = _phone.text.trim();
    setState(() {
      _nameError = name.isEmpty ? context.l10n.enterAName : null;
      _phoneError = EmergencyContact.looksLikePhone(phone)
          ? null
          : context.l10n.enterValidPhone;
    });
    if (name.isEmpty || !EmergencyContact.looksLikePhone(phone)) return;
    Navigator.of(context).pop(_DraftContact(name: name, phone: phone));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.addEmergencyContact),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.l10n.nameLabel,
              border: const OutlineInputBorder(),
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: context.l10n.phoneLabel,
              border: const OutlineInputBorder(),
              errorText: _phoneError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.actionAdd),
        ),
      ],
    );
  }
}
