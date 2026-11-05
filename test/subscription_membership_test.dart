// Tests for the Subscription Membership flow (Account → Membership →
// Plan Details). Approved preview, implemented as UI + navigation
// only: there is no payment provider, so Subscribe Now must stop at
// a confirmation sheet with an honest note — never a charge,
// verification, or activation.
import 'package:estudyantego/features/floating_nav.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
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

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'byahetayo_onboarding_done': true,
    'byahetayo_profile_setup_done_uid-1': true,
    'byahetayo_profile_uid-1':
        '{"displayName":"Steven Reyes","email":"steven@example.com"}',
  });
  await tester.pumpWidget(
    EstudyanteGOApp(
      authService: FakeAuthService(user: _user),
      permissionService: FakePermissionService(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAccount(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sidebar-item-Account')));
  await tester.pumpAndSettle();
}

Future<void> _openMembership(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('subscription-member-card')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('subscription-member-card')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Account shows Subscription Member card with Free Plan', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);

    expect(find.text('Subscription Member'), findsOneWidget);
    expect(
      find.text('Your current membership plan'),
      findsOneWidget,
    );
    expect(find.text('Free Plan'), findsOneWidget);
  });

  testWidgets('card tap opens Membership and keeps tab navigation visible', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);
    await _openMembership(tester);

    expect(find.text('Byahe Tayo Premium'), findsOneWidget);
    expect(find.text('Upgrade Your Experience'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Save up to 20%'), findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsOneWidget);
    // Membership lives inside the Account tab: the tab navigation
    // (sidebar here) stays visible, and Account content is swapped out.
    expect(find.byKey(const Key('sidebar-item-Account')), findsOneWidget);
    expect(find.text('Quick Actions'), findsNothing);
  });

  testWidgets('Monthly/Yearly switching updates all displayed prices', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);
    await _openMembership(tester);

    expect(find.text('₱99 / month'), findsOneWidget);
    expect(find.text('₱299 / month'), findsOneWidget);

    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    expect(find.text('₱950 / year'), findsOneWidget);
    expect(find.text('₱2,870 / year'), findsOneWidget);
    expect(find.text('≈ ₱79/mo'), findsOneWidget);
    expect(find.text('≈ ₱239/mo'), findsOneWidget);
    expect(find.text('₱99 / month'), findsNothing);
    expect(find.text('₱299 / month'), findsNothing);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('₱99 / month'), findsOneWidget);
    expect(find.text('₱299 / month'), findsOneWidget);
  });

  testWidgets('plan selection updates action button and details screen', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);
    await _openMembership(tester);

    await tester.tap(find.byKey(const Key('plan-card-standard')));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Standard'), findsOneWidget);

    await tester.tap(find.byKey(const Key('membership-action-button')));
    await tester.pumpAndSettle();
    expect(find.text('Standard Plan'), findsNWidgets(2));
    expect(find.text('₱99 / month'), findsOneWidget);
    expect(find.text('All Free features'), findsOneWidget);
    expect(find.text('No advertisements'), findsOneWidget);
    expect(find.text('Auto-renew (cancel anytime)'), findsOneWidget);
    // Details is a pushed route: the tab navigation is NOT visible.
    expect(find.byKey(const Key('sidebar-item-Account')), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Upgrade Your Experience'), findsOneWidget);
  });

  testWidgets('Subscribe Now stops at confirmation, never activates', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(800, 1280));
    await _pumpApp(tester);
    await _openAccount(tester);
    await _openMembership(tester);

    await tester.tap(find.byKey(const Key('membership-action-button')));
    await tester.pumpAndSettle();
    expect(find.text('Pro Plan'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('subscribe-now-button')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm subscription'), findsOneWidget);
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Billing'), findsWidgets);
    expect(find.text('Price'), findsWidgets);
    expect(find.text('Renewal'), findsWidgets);
    expect(find.text('₱299 / month'), findsWidgets);
    expect(find.textContaining('payment provider'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    // No success / activation state anywhere.
    expect(find.textContaining('now Pro'), findsNothing);
    expect(find.textContaining('Welcome to Pro'), findsNothing);
    expect(find.textContaining('activated'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm subscription'), findsNothing);

    // Back to Account: still Free — nothing was purchased.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Account'));
    await tester.pumpAndSettle();
    expect(find.text('Subscription Member'), findsOneWidget);
    expect(find.text('Free Plan'), findsOneWidget);
  });

  testWidgets('phone width: nav visible on Membership, hidden on Details', (
    WidgetTester tester,
  ) async {
    await _setSurface(tester, const Size(390, 844));
    await _pumpApp(tester);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await _openMembership(tester);

    expect(find.byType(FloatingGlassNav), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('membership-action-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('membership-action-button')));
    await tester.pumpAndSettle();
    expect(find.text('Pro Plan'), findsNWidgets(2));
    expect(find.byType(FloatingGlassNav), findsNothing);
  });
}
