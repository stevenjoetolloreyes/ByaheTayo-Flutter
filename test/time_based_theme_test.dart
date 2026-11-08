// Tests for the Time Based theme option (Nov 8): Light 6:00 AM–6:00 PM,
// Dark 6:00 PM–6:00 AM, resolved against the clock. The resolver takes
// the time as a parameter, so the boundaries are testable without
// waiting for 6 AM.
import 'package:estudyantego/features/account_tab.dart';
import 'package:estudyantego/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  group('resolveThemeMode — Time Based', () {
    test('10:00 AM resolves to Light', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 10, 0),
        ),
        ThemeMode.light,
      );
    });

    test('10:00 PM resolves to Dark', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 22, 0),
        ),
        ThemeMode.dark,
      );
    });

    test('6:00 AM boundary resolves to Light', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 6, 0),
        ),
        ThemeMode.light,
      );
    });

    test('5:59 AM resolves to Dark', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 5, 59),
        ),
        ThemeMode.dark,
      );
    });

    test('5:59 PM resolves to Light', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 17, 59),
        ),
        ThemeMode.light,
      );
    });

    test('6:00 PM boundary resolves to Dark', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 18, 0),
        ),
        ThemeMode.dark,
      );
    });

    test('midnight resolves to Dark', () {
      expect(
        resolveThemeMode(
          AppThemePreference.timeBased,
          DateTime(2026, 11, 8, 0, 0),
        ),
        ThemeMode.dark,
      );
    });
  });

  group('resolveThemeMode — other options pass through', () {
    test('System passes through as ThemeMode.system', () {
      expect(
        resolveThemeMode(
          AppThemePreference.system,
          DateTime(2026, 11, 8, 10, 0),
        ),
        ThemeMode.system,
      );
    });

    test('Light and Dark pass through regardless of the clock', () {
      expect(
        resolveThemeMode(
          AppThemePreference.light,
          DateTime(2026, 11, 8, 22, 0),
        ),
        ThemeMode.light,
      );
      expect(
        resolveThemeMode(
          AppThemePreference.dark,
          DateTime(2026, 11, 8, 10, 0),
        ),
        ThemeMode.dark,
      );
    });
  });

  group('appThemePreferenceFromString', () {
    test('parses all four stored values', () {
      expect(
        appThemePreferenceFromString('system'),
        AppThemePreference.system,
      );
      expect(
        appThemePreferenceFromString('light'),
        AppThemePreference.light,
      );
      expect(
        appThemePreferenceFromString('dark'),
        AppThemePreference.dark,
      );
      expect(
        appThemePreferenceFromString('timeBased'),
        AppThemePreference.timeBased,
      );
    });

    test('unknown or missing values fall back to dark (existing default)', () {
      expect(appThemePreferenceFromString(null), AppThemePreference.dark);
      expect(appThemePreferenceFromString(''), AppThemePreference.dark);
      expect(
        appThemePreferenceFromString('sepia'),
        AppThemePreference.dark,
      );
    });
  });

  group('appThemePreferenceForThemeMode', () {
    test('maps each ThemeMode onto its preference', () {
      expect(
        appThemePreferenceForThemeMode(ThemeMode.light),
        AppThemePreference.light,
      );
      expect(
        appThemePreferenceForThemeMode(ThemeMode.dark),
        AppThemePreference.dark,
      );
      expect(
        appThemePreferenceForThemeMode(ThemeMode.system),
        AppThemePreference.system,
      );
    });
  });

  testWidgets('Theme Settings dialog offers Time Based and reports it',
      (WidgetTester tester) async {
    AppThemePreference? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountTab(
            themePreference: AppThemePreference.dark,
            onThemePreferenceChanged: (value) => picked = value,
            authService: FakeAuthService(),
            user: null,
            permissionService: FakePermissionService(),
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Theme Settings'));
    await tester.tap(find.text('Theme Settings'));
    await tester.pumpAndSettle();

    // All four options are offered; Time Based is the new one. The
    // options are scoped to the SimpleDialog — the Account page itself
    // also shows the current value ("Dark"), so a bare find.text
    // would match two widgets.
    for (final option in ['System', 'Light', 'Dark', 'Time Based']) {
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text(option),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.text('Time Based'),
    ));
    await tester.pumpAndSettle();
    expect(picked, AppThemePreference.timeBased);
  });
}
