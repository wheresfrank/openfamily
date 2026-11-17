import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// The localizations most recently resolved by the app root, for code that has
/// no [BuildContext] (models, mappers). English until the app root runs.
class CurrentL10n {
  CurrentL10n._();

  static AppLocalizations? _value;

  static AppLocalizations get value =>
      _value ?? lookupAppLocalizations(const Locale('en'));

  static void update(AppLocalizations value) => _value = value;
}

extension AppLocalizationsContext on BuildContext {
  /// The localized strings for this context. Falls back to English when no
  /// localizations delegate is installed above the widget (widget tests).
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('en'));
}
