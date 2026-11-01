// Tests for the Account dashboard (Account tab).
//
// Honest-state rules under test: guest header (no invented name/email),
// 0 points wallet with an honest empty history, no-backend actions show
// a SnackBar instead of faking success, theme switching really changes
// the app theme, and notification/language choices persist locally.
import 'package:byahetayo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notPorted =
    'Hindi pa available — hindi pa naka-port ang account system sa Flutter app.';
const _signedOut =
    'Walang naka-sign in — hindi pa naka-port ang account system sa Flutter app.';

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openAccount(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sidebar-item-Account')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dashboard sections all render', (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Mag-sign in para makita ang profile mo.'),
        findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Points Wallet'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('points-balance'))).data,
      '0 points',
    );
    expect(find.text('Earn Points'), findsOneWidget);
    expect(find.text('Transaction History'), findsWidgets);
    expect(find.text('Wala pang transactions.'), findsWidgets);
    expect(find.text('Account Information'), findsOneWidget);
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Student Information'), findsOneWidget);
    expect(find.text('Employment Information'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Notification Settings'), findsOneWidget);
    expect(find.text('Theme Settings'), findsOneWidget);
    expect(find.text('Language Settings'), findsOneWidget);
    expect(find.text('Security & Privacy'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Account Verification'), findsOneWidget);
    expect(find.text('Privacy Settings'), findsOneWidget);
    expect(find.text('Account Actions'), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('About ByaheTayo'), findsOneWidget);
    expect(find.text('Terms and Conditions'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    // No invented identity, no fake badge.
    expect(find.text('Steven'), findsNothing);
  });

  testWidgets('content is top-aligned, not vertically centered',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    final top = tester.getTopLeft(find.text('Guest')).dy;
    expect(top, lessThan(200));
  });

  testWidgets('dashboard scrolls to the last section',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    await tester.scrollUntilVisible(find.text('Sign Out'), 500, scrollable: find.descendant(of: find.byKey(const Key('account-scroll-view')), matching: find.byType(Scrollable)));
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('theme setting really switches the app theme',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    await tester.tap(find.text('Theme Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Guest'));
    expect(Theme.of(context).brightness, Brightness.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('byahetayo_theme_mode'), 'dark');
  });

  testWidgets('Edit Profile shows an honest SnackBar, not fake success',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    await tester.tap(find.text('Edit Profile'));
    await tester.pump();
    expect(find.text(_notPorted), findsOneWidget);
  });

  testWidgets('Sign Out shows an honest SnackBar, not a fake sign-out',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    await tester.scrollUntilVisible(find.text('Sign Out'), 500,
        scrollable: find.descendant(
            of: find.byKey(const Key('account-scroll-view')),
            matching: find.byType(Scrollable)));
    await tester.tap(find.text('Sign Out'));
    await tester.pump();
    expect(find.text(_signedOut), findsOneWidget);
  });

  testWidgets('notification setting persists locally',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('byahetayo_pref_notifications'), isFalse);
  });

  testWidgets('transaction history opens an honest empty state',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);

    await tester.tap(find.text('Transaction History').first);
    await tester.pumpAndSettle();
    expect(find.text('Transaction History'), findsNWidgets(2));
    expect(find.text('Wala pang transactions.'), findsWidgets);
  });

  testWidgets('no overflow at tablet portrait and landscape sizes',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);
    await tester.scrollUntilVisible(find.text('Sign Out'), 500, scrollable: find.descendant(of: find.byKey(const Key('account-scroll-view')), matching: find.byType(Scrollable)));

    await _setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(const ByaheTayoApp());
    await tester.pumpAndSettle();
    await _openAccount(tester);
    await tester.scrollUntilVisible(find.text('Sign Out'), 500, scrollable: find.descendant(of: find.byKey(const Key('account-scroll-view')), matching: find.byType(Scrollable)));
  });
}
