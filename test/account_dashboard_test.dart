// Tests for the premium Account dashboard (Account tab).
//
// Honest-state rules under test: authenticated header (real name/email,
// real Verified badge, no "Guest" identity anywhere), 0 points wallet
// with an honest empty history, theme switching really changes the app
// theme, notification settings show the REAL permission status (no dead
// toggle), language honestly shows English only, Edit Profile opens the
// real profile screen, and Sign Out really signs out to the sign-in
// screen. Auth/permission behavior goes through the fakes.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/permission_service.dart';
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpApp(
  WidgetTester tester, {
  FakeAuthService? auth,
  FakePermissionService? permissions,
  Map<String, Object>? extraPrefs,
}) async {
  SharedPreferences.setMockInitialValues({
    'byahetayo_onboarding_done': true,
    'byahetayo_profile_setup_done_uid-1': true,
    'byahetayo_profile_uid-1':
        '{"displayName":"Steven Reyes","email":"steven@example.com"}',
    ...?extraPrefs,
  });
  await tester.pumpWidget(EstudyanteGOApp(
    authService: auth ?? FakeAuthService(user: _user),
    permissionService: permissions ?? FakePermissionService(),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openAccount(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sidebar-item-Account')));
  await tester.pumpAndSettle();
}

/// Taps a row that may sit below the fold: scrolls it into view first.
/// (The premium layout is taller than the old settings list, so lower
/// sections are off-screen at phone/tablet-portrait heights.)
Future<void> _tapVisible(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard sections all render', (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    expect(find.text('Steven Reyes'), findsOneWidget);
    expect(find.text('steven@example.com'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Points Wallet'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('points-balance'))).data,
      '0 points',
    );
    expect(find.text('Earn Points'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('My Student ID'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Rewards'), findsOneWidget);
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
    expect(find.text('About EstudyanteGO'), findsOneWidget);
    expect(find.text('Terms and Conditions'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    // No invented identity, no guest wording, no fake badge.
    expect(find.text('Guest'), findsNothing);
    expect(find.text('No account signed in'), findsNothing);
  });

  testWidgets('Student Information shows the synced school field',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    // The per-UID JSON holds a STALE school; the flat contract key
    // holds the current one. Account must show the flat-key value —
    // the same value Profile Setup edits.
    await _pumpApp(tester, extraPrefs: {
      'byahetayo_profile_uid-1':
          '{"displayName":"Steven Reyes","email":"steven@example.com",'
          '"school":"Old School Name"}',
      'byahetayo_profile_school': 'University of Northern Philippines',
    });
    await _openAccount(tester);

    expect(find.text('Student Information'), findsOneWidget);
    expect(
      find.textContaining('University of Northern Philippines'),
      findsWidgets,
    );
    expect(find.textContaining('Old School Name'), findsNothing);
  });

  testWidgets('content is top-aligned, not vertically centered',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    final top = tester.getTopLeft(find.text('Steven Reyes')).dy;
    expect(top, lessThan(200));
  });

  testWidgets('dashboard scrolls to the last section',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('theme setting really switches the app theme',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    await _tapVisible(tester, 'Theme Settings');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Steven Reyes'));
    expect(Theme.of(context).brightness, Brightness.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('byahetayo_theme_mode'), 'dark');
  });

  testWidgets('Edit Profile opens the real profile screen',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Steven Reyes'), findsOneWidget);
  });

  testWidgets('Sign Out really signs out to the sign-in screen',
      (WidgetTester tester) async {
    final auth = FakeAuthService(user: _user);
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester, auth: auth);
    await _openAccount(tester);

    await _tapVisible(tester, 'Sign Out');
    expect(auth.currentUser, isNull);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
  });

  testWidgets('notification setting shows real status + explanation',
      (WidgetTester tester) async {
    final permissions = FakePermissionService(
      initial: NotificationPermissionStatus.denied,
    );
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester, permissions: permissions);
    await _openAccount(tester);

    expect(find.text('Not allowed'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);

    await _tapVisible(tester, 'Notification Settings');
    expect(find.text('Allow notifications?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(permissions.requestCount, 0);

    await _tapVisible(tester, 'Notification Settings');
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(permissions.requestCount, 1);
    expect(find.text('Allowed'), findsOneWidget);
  });

  testWidgets('language setting honestly shows English only',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    await _tapVisible(tester, 'Language Settings');
    expect(find.text('English'), findsWidgets);
  });

  testWidgets('transaction history opens an honest empty state',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    await _tapVisible(tester, 'Transactions');
    // The dashboard tile and the opened sheet both show these texts.
    expect(find.text('Transaction History'), findsNWidgets(2));
    expect(find.text('No transactions yet.'), findsWidgets);
  });

  testWidgets('no overflow at tablet portrait and landscape sizes',
      (WidgetTester tester) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);
    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();

    await _setSurface(tester, const Size(1280, 800));
    await _pumpApp(tester);
    await _openAccount(tester);
    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();
  });
}
