import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/l10n/l10n.dart';
import 'package:openfamily/screens/welcome_screen.dart';
import 'package:openfamily/services/locale_preference.dart';
import 'package:openfamily/services/member_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((String k) => !k.startsWith('@')).toSet();

void main() {
  test('Spanish translates every English message', () {
    final Map<String, dynamic> en = _arb('app_en.arb');
    final Map<String, dynamic> es = _arb('app_es.arb');
    expect(_messageKeys(es), _messageKeys(en));
  });

  test('placeholders match between English and Spanish', () {
    final RegExp placeholder = RegExp(r'\{(\w+)\}');
    final Map<String, dynamic> en = _arb('app_en.arb');
    final Map<String, dynamic> es = _arb('app_es.arb');
    for (final String key in _messageKeys(en)) {
      final Set<String?> enNames = placeholder
          .allMatches(en[key] as String)
          .map((RegExpMatch m) => m.group(1))
          .toSet();
      final Set<String?> esNames = placeholder
          .allMatches(es[key] as String)
          .map((RegExpMatch m) => m.group(1))
          .toSet();
      expect(esNames, enNames, reason: 'placeholders differ for "$key"');
    }
  });

  test('the generated Spanish strings are used', () {
    final AppLocalizations es = lookupAppLocalizations(const Locale('es'));
    expect(es.actionCancel, 'Cancelar');
    expect(es.positionFromAgo('8h'), 'Posición de hace 8h');
  });

  test('stale addresses are recognised in every language', () {
    for (final Locale locale in AppLocalizations.supportedLocales) {
      final String address =
          lookupAppLocalizations(locale).positionFromAgo('8h');
      expect(isStaleAddress(address), isTrue, reason: '$locale');
    }
    expect(isStaleAddress('Stationary'), isFalse);
  });

  test('CurrentL10n follows the last resolved locale', () {
    CurrentL10n.update(lookupAppLocalizations(const Locale('es')));
    expect(CurrentL10n.value.addressStationary, 'Detenido');
    CurrentL10n.update(lookupAppLocalizations(const Locale('en')));
    expect(CurrentL10n.value.addressStationary, 'Stationary');
  });

  testWidgets('a screen renders in Spanish when the locale is es',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WelcomeScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Comenzar'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
  });

  test('server default applies only when the user has not chosen', () {
    const Locale es = Locale('es');
    const Locale en = Locale('en');
    expect(
      LocalePreferenceService.resolveLocale(LanguagePreference.system, 'es'),
      es,
    );
    expect(
      LocalePreferenceService.resolveLocale(LanguagePreference.system, null),
      isNull,
    );
    expect(
      LocalePreferenceService.resolveLocale(LanguagePreference.system, 'fr'),
      isNull,
    );
    expect(
      LocalePreferenceService.resolveLocale(LanguagePreference.english, 'es'),
      en,
    );
    expect(
      LocalePreferenceService.resolveLocale(LanguagePreference.spanish, 'en'),
      es,
    );
  });

  test('the server default is read from /config and remembered', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalePreferenceService.applyServerDefault(
      <String, dynamic>{'default_language': 'es'},
    );
    expect(LocalePreferenceService.serverDefault.value, 'es');

    // A server that predates the field must not clear a known value.
    await LocalePreferenceService.applyServerDefault(<String, dynamic>{});
    expect(LocalePreferenceService.serverDefault.value, 'es');

    // An empty value means "follow the device".
    await LocalePreferenceService.applyServerDefault(
      <String, dynamic>{'default_language': ''},
    );
    expect(LocalePreferenceService.serverDefault.value, isNull);

    await LocalePreferenceService.applyServerDefault(
      <String, dynamic>{'default_language': 'es'},
    );
    LocalePreferenceService.serverDefault.value = null;
    await LocalePreferenceService.load();
    expect(LocalePreferenceService.serverDefault.value, 'es');
  });
}
