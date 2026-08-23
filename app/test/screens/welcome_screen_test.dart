import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/welcome_screen.dart';
import 'package:whereabouts/theme/app_theme.dart';

void main() {
  testWidgets('hero copy stays Ice ink under the Night theme',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const WelcomeScreen(),
      ),
    );

    final Text title = tester.widget<Text>(find.text('Whereabouts'));
    expect(title.style?.color, AppColors.iceInk);

    final Text tagline = tester.widget<Text>(
      find.text('Know where your family is — privately.'),
    );
    expect(tagline.style?.color, AppColors.iceMuted);

    final TextButton login = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Log In'),
    );
    expect(
      login.style?.foregroundColor?.resolve(const <WidgetState>{}),
      AppColors.iceInk,
    );
  });
}
