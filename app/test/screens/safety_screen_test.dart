import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/models/emergency_contact.dart';
import 'package:whereabouts/screens/safety_screen.dart';
import 'package:whereabouts/services/contact_picker.dart';
import 'package:whereabouts/services/emergency_contact_service.dart';

class _FakeContactService extends EmergencyContactService {
  _FakeContactService(this.store);

  final List<EmergencyContact> store;
  int _nextId = 1;

  @override
  Future<List<EmergencyContact>> list() async =>
      List<EmergencyContact>.from(store);

  @override
  Future<EmergencyContact> add({
    required String name,
    required String phone,
    String relation = '',
  }) async {
    final EmergencyContact created = EmergencyContact(
      id: 'c${_nextId++}',
      name: name,
      phone: phone,
      relation: relation,
    );
    store.add(created);
    return created;
  }

  @override
  Future<void> delete(String id) async {
    store.removeWhere((EmergencyContact c) => c.id == id);
  }
}

class _FakePicker implements ContactPicker {
  _FakePicker(this.onPick);

  final Future<PickedPhoneContact?> Function() onPick;

  @override
  Future<PickedPhoneContact?> pickPhoneContact() => onPick();
}

Widget _app({
  required EmergencyContactService service,
  ContactPicker? picker,
}) {
  return MaterialApp(
    home: SafetyScreen(
      contactService: service,
      contactPicker: picker ?? _FakePicker(() async => null),
    ),
  );
}

void main() {
  test('EmergencyContact.fromJson reads server fields', () {
    final EmergencyContact contact = EmergencyContact.fromJson(
      <String, dynamic>{
        'id': 'abc',
        'name': 'Mom',
        'phone': '(415) 555-0132',
        'relation': 'Family',
      },
    );
    expect(contact.id, 'abc');
    expect(contact.name, 'Mom');
    expect(contact.phone, '(415) 555-0132');
    expect(contact.relation, 'Family');
    expect(EmergencyContact.looksLikePhone(contact.phone), isTrue);
    expect(EmergencyContact.looksLikePhone('123'), isFalse);
  });

  testWidgets('loads saved contacts instead of placeholder names', (
    WidgetTester tester,
  ) async {
    final _FakeContactService service = _FakeContactService(
      <EmergencyContact>[
        const EmergencyContact(
          id: '1',
          name: 'Aunt June',
          phone: '4155550100',
        ),
      ],
    );

    await tester.pumpWidget(_app(service: service));
    await tester.pumpAndSettle();

    expect(find.text('Aunt June'), findsOneWidget);
    expect(find.text('4155550100'), findsOneWidget);
    expect(find.text('Mom'), findsNothing);
    expect(find.text('Dad'), findsNothing);
  });

  testWidgets('choosing a phone contact saves it on the list', (
    WidgetTester tester,
  ) async {
    final _FakeContactService service = _FakeContactService(
      <EmergencyContact>[],
    );
    final _FakePicker picker = _FakePicker(
      () async => const PickedPhoneContact(
        name: 'Sam Rivera',
        phones: <String>['4155550199'],
        selectedPhone: '4155550199',
      ),
    );

    await tester.pumpWidget(_app(service: service, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose from contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Sam Rivera'), findsOneWidget);
    expect(find.text('4155550199'), findsOneWidget);
    expect(service.store, hasLength(1));
  });

  testWidgets('typing a contact saves it instead of discarding on close', (
    WidgetTester tester,
  ) async {
    final _FakeContactService service = _FakeContactService(
      <EmergencyContact>[],
    );

    await tester.pumpWidget(_app(service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type a name and number'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Dad');
    await tester.enterText(find.byType(TextField).at(1), '415-555-0177');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Dad'), findsOneWidget);
    expect(find.text('415-555-0177'), findsOneWidget);
    expect(service.store.single.name, 'Dad');
    expect(service.store.single.phone, '415-555-0177');
  });

  testWidgets('removing a contact deletes it from the store', (
    WidgetTester tester,
  ) async {
    final _FakeContactService service = _FakeContactService(
      <EmergencyContact>[
        const EmergencyContact(id: '1', name: 'Mom', phone: '4155550132'),
      ],
    );

    await tester.pumpWidget(_app(service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Mom'), findsNothing);
    expect(service.store, isEmpty);
  });
}
