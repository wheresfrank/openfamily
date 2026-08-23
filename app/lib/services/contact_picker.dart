import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';

/// A contact the user picked from the phone's address book.
class PickedPhoneContact {
  const PickedPhoneContact({
    required this.name,
    required this.phones,
    this.selectedPhone,
  });

  final String name;
  final List<String> phones;

  /// The number the OS picker already chose, when the user tapped one.
  final String? selectedPhone;
}

/// Thrown when the chosen address-book entry has no phone number.
class ContactHasNoPhoneException implements Exception {
  const ContactHasNoPhoneException();
}

/// Opens the operating system's contact picker.
///
/// This uses the native picker UI rather than reading the whole address book,
/// so the app does not need `READ_CONTACTS` or `NSContactsUsageDescription`.
abstract class ContactPicker {
  /// Returns the picked contact, or null if the user cancelled.
  ///
  /// Throws [ContactHasNoPhoneException] when the chosen person has no number.
  Future<PickedPhoneContact?> pickPhoneContact();
}

/// [ContactPicker] backed by [FlutterNativeContactPicker].
class NativeContactPicker implements ContactPicker {
  NativeContactPicker({FlutterNativeContactPicker? plugin})
      : _plugin = plugin ?? FlutterNativeContactPicker();

  final FlutterNativeContactPicker _plugin;

  @override
  Future<PickedPhoneContact?> pickPhoneContact() async {
    final Contact? contact = await _plugin.selectPhoneNumber();
    if (contact == null) return null;

    final List<String> phones = <String>[];
    void addPhone(String? number) {
      final String trimmed = (number ?? '').trim();
      if (trimmed.isNotEmpty && !phones.contains(trimmed)) {
        phones.add(trimmed);
      }
    }

    for (final String number in contact.phoneNumbers ?? const <String>[]) {
      addPhone(number);
    }
    addPhone(contact.selectedPhoneNumber);

    if (phones.isEmpty) {
      throw const ContactHasNoPhoneException();
    }

    final String name = (contact.fullName ?? '').trim();
    final String? selected = contact.selectedPhoneNumber?.trim();
    return PickedPhoneContact(
      name: name.isEmpty ? phones.first : name,
      phones: phones,
      selectedPhone:
          (selected != null && selected.isNotEmpty) ? selected : null,
    );
  }
}
