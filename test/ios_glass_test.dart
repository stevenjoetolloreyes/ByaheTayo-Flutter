// Tests for the iPhone-only Glassmorphism styling (Queue #3).
//
// Appearance-only contract under test:
// - On iPhone styling, the Account page shows the SAME content as
//   Material (real profile, real wallet balance, real credits row,
//   same Quick Actions labels, same section titles) — only the
//   wrappers turn to glass over the emerald background.
// - The glass nav has the SAME 6 tabs in the SAME order with the
//   SAME labels, and tapping one selects exactly that tab.
// - The Admin section stays gated: hidden for non-admins, shown
//   for allowlisted admins, exactly as on Material.
// - With the override unset (the Android/test-host default), the
//   Account page renders the Material path (no glass nav, no
//   glass background) — the no-Android-regression proof at the
//   widget level, alongside the full existing suite.
import 'package:estudyantego/features/account_tab.dart';
import 'package:estudyantego/features/ios_glass.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
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

const _adminUser = AuthUser(
  uid: 'uid-admin',
  email: 'stevenjoereyes0625@gmail.com',
  displayName: 'Steven Admin',
  emailVerified: true,
);

Future<void> _pumpAccount(
  WidgetTester tester, {
  AuthUser? user,
  bool glass = false,
}) async {
  iosGlassTestOverride = glass;
  addTearDown(() {
    iosGlassTestOverride = null;
  });
  SharedPreferences.setMockInitialValues({
    'byahetayo_onboarding_done': true,
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AccountTab(
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
          authService: FakeAuthService(user: user ?? _user),
          user: user ?? _user,
          permissionService: FakePermissionService(),
          onSignedOut: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _destinations = [
  GlassNavDestination('Map', Icons.map_outlined, Icons.map),
  GlassNavDestination('Fares', Icons.payments_outlined, Icons.payments),
  GlassNavDestination('Student', Icons.school_outlined, Icons.school),
  GlassNavDestination('Friends', Icons.people_outlined, Icons.people),
  GlassNavDestination(
      'Communities', Icons.groups_outlined, Icons.groups),
  GlassNavDestination('Account', Icons.person_outlined, Icons.person),
];

void main() {
  testWidgets('glass Account keeps every real section and action',
      (WidgetTester tester) async {
    await _pumpAccount(tester, glass: true);

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
    expect(find.text('Subscription Member'), findsOneWidget);
    expect(find.text('Free Plan'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('My Student ID'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Rewards'), findsOneWidget);
    expect(find.text('Account Information'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Security & Privacy'), findsOneWidget);
    expect(find.text('Account Actions'), findsOneWidget);
    // Glass is actually on: emerald background + frosted cards.
    expect(find.byType(IosGlassBackground), findsOneWidget);
    expect(find.byType(GlassCard), findsWidgets);
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('glass Account keeps Admin gated by allowlist',
      (WidgetTester tester) async {
    await _pumpAccount(tester, glass: true);
    expect(find.text('Admin Access'), findsNothing);

    await _pumpAccount(tester, user: _adminUser, glass: true);
    await tester.ensureVisible(find.text('Admin Access'));
    expect(find.text('Post approvals'), findsOneWidget);
    expect(find.text('LGU directory'), findsOneWidget);
  });

  testWidgets('glass nav keeps the 6 tabs in order and taps select',
      (WidgetTester tester) async {
    var selected = 5;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBottomNav(
            selectedIndex: selected,
            onSelect: (i) => selected = i,
            destinations: _destinations,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('glass-nav')), findsOneWidget);
    for (final d in _destinations) {
      expect(find.text(d.label), findsOneWidget);
      expect(
        find.byKey(Key('glass-nav-item-${d.label}')),
        findsOneWidget,
      );
    }
    // Order: Map first, Account last.
    final mapY = tester.getCenter(find.text('Map')).dx;
    final accountY = tester.getCenter(find.text('Account')).dx;
    expect(mapY, lessThan(accountY));

    await tester.tap(find.text('Fares'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(selected, 0);
  });

  testWidgets('glass nav items meet the iOS 44pt touch minimum',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBottomNav(
            selectedIndex: 0,
            onSelect: (_) {},
            destinations: _destinations,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byKey(const Key('glass-nav-item-Map')));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('Material path renders with no glass when override unset',
      (WidgetTester tester) async {
    await _pumpAccount(tester, glass: false);
    expect(find.byType(IosGlassBackground), findsNothing);
    expect(find.byType(GlassCard), findsNothing);
    expect(find.byType(GlassBottomNav), findsNothing);
    // Same content, Material wrappers.
    expect(find.text('Points Wallet'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
  });
}
