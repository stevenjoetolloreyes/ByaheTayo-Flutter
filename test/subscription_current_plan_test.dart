// Tests for the REAL current plan display + honest Subscribe flow
// (Builder 3).
//
// Covers:
//   - Account tab shows the real plan from the local profile
//     (Standard / Pro, with its storage limit), defaulting to Free
//     when the profile has no plan.
//   - Subscription screen marks the correct current-plan card and
//     header line from the local profile's plan — never from the
//     transient card selection.
//   - Subscribe on Standard/Pro shows the admin-assignment message
//     and records nothing (the plan is unchanged afterwards).
//   - Subscribe on Free assigns nothing: the Free action stays
//     disabled and the plan stays Free.
//
// Fakes only — no live Firebase is touched. The profile (including
// its admin-assigned `plan`, cached locally) comes from the mocked
// SharedPreferences JSON, exactly like the read-path tests.
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

/// Pumps the full app with a local profile whose cached `plan` is
/// [plan] (null = no `plan` key at all, i.e. a profile written
/// before the plan field existed).
Future<void> _pumpApp(WidgetTester tester, {String? plan}) async {
  final profileJson = plan == null
      ? '{"displayName":"Steven Reyes","email":"steven@example.com"}'
      : '{"displayName":"Steven Reyes","email":"steven@example.com",'
          '"plan":"$plan"}';
  SharedPreferences.setMockInitialValues({
    'byahetayo_onboarding_done': true,
    'byahetayo_profile_setup_done_uid-1': true,
    'byahetayo_profile_uid-1': profileJson,
  });
  await tester.pumpWidget(
    EstudyanteGOApp(
      authService: FakeAuthService(user: _user),
      permissionService: FakePermissionService(),
    ),
  );
  // Anime splash (Nov 7): one master animation drives the whole
  // ~4.9 s intro, so a single settle carries it to the handoff.
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

Future<void> _backToAccount(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Back to Account'));
  await tester.pumpAndSettle();
}

/// The 'Current Plan' pill on the given plan card.
Finder _currentPlanPillOn(String planId) => find.descendant(
  of: find.byKey(Key('plan-card-$planId')),
  matching: find.text('Current Plan'),
);

void main() {
  group('Account tab shows the real current plan', () {
    testWidgets('Standard plan from the profile, with its storage limit', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester, plan: 'standard');
      await _openAccount(tester);

      expect(find.text('Subscription Member'), findsOneWidget);
      expect(find.text('Standard Plan'), findsOneWidget);
      expect(find.text('12 GB storage'), findsOneWidget);
      expect(find.text('Free Plan'), findsNothing);
    });

    testWidgets('Pro plan from the profile, with its storage limit', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester, plan: 'pro');
      await _openAccount(tester);

      expect(find.text('Pro Plan'), findsOneWidget);
      expect(find.text('30 GB storage'), findsOneWidget);
      expect(find.text('Free Plan'), findsNothing);
    });

    testWidgets('no plan on the profile defaults to Free', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester);
      await _openAccount(tester);

      expect(find.text('Free Plan'), findsOneWidget);
      expect(find.text('2 GB storage'), findsOneWidget);
    });
  });

  group('Subscription screen marks the real current plan', () {
    testWidgets('Standard is marked current; Free and Pro are not', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester, plan: 'standard');
      await _openAccount(tester);
      await _openMembership(tester);

      expect(
        find.text('Current plan: Standard — 12 GB storage'),
        findsOneWidget,
      );
      expect(_currentPlanPillOn('standard'), findsOneWidget);
      expect(_currentPlanPillOn('free'), findsNothing);
      expect(_currentPlanPillOn('pro'), findsNothing);
      // Storage lines from the show-only build are unchanged.
      expect(find.text('2 GB storage'), findsOneWidget);
      expect(find.text('12 GB storage'), findsOneWidget);
      expect(find.text('30 GB storage'), findsOneWidget);
    });

    testWidgets('tapping another card never moves the current-plan mark', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester, plan: 'standard');
      await _openAccount(tester);
      await _openMembership(tester);

      await tester.tap(find.byKey(const Key('plan-card-pro')));
      await tester.pumpAndSettle();

      // The selection moved (action button follows it) but the
      // current-plan mark did not.
      expect(find.text('Upgrade to Pro'), findsOneWidget);
      expect(
        find.text('Current plan: Standard — 12 GB storage'),
        findsOneWidget,
      );
      expect(_currentPlanPillOn('standard'), findsOneWidget);
      expect(_currentPlanPillOn('pro'), findsNothing);
    });

    testWidgets('Pro current: pill on Pro, action button disabled', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester, plan: 'pro');
      await _openAccount(tester);
      await _openMembership(tester);

      expect(
        find.text('Current plan: Pro — 30 GB storage'),
        findsOneWidget,
      );
      expect(_currentPlanPillOn('pro'), findsOneWidget);
      expect(_currentPlanPillOn('standard'), findsNothing);
      // Pro is pre-selected AND current, so the button says
      // 'Current Plan' (pill + button = 2) and is disabled.
      expect(find.text('Current Plan'), findsNWidgets(2));
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('membership-action-button')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('Subscribe flow is honest (admin-assigned plans)', () {
    testWidgets('Subscribe on Standard shows the admin message, plan stays Free', (
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

      await tester.tap(find.byKey(const Key('subscribe-now-button')));
      await tester.pumpAndSettle();
      expect(find.text('Plan upgrade'), findsOneWidget);
      expect(find.textContaining('assigned by the admin'), findsOneWidget);
      expect(
        find.textContaining('upgrade your plan to Standard'),
        findsOneWidget,
      );
      expect(find.textContaining('hasn\'t changed'), findsOneWidget);
      // No success / activation state anywhere.
      expect(find.textContaining('activated'), findsNothing);
      expect(find.textContaining('Welcome to Standard'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Plan upgrade'), findsNothing);

      // Back to Account: still Free — nothing was recorded.
      await _backToAccount(tester);
      expect(find.text('Subscription Member'), findsOneWidget);
      expect(find.text('Free Plan'), findsOneWidget);
      expect(find.text('Standard Plan'), findsNothing);
    });

    testWidgets('Subscribe on Free assigns nothing', (
      WidgetTester tester,
    ) async {
      await _setSurface(tester, const Size(800, 1280));
      await _pumpApp(tester);
      await _openAccount(tester);
      await _openMembership(tester);

      // Free is the current plan, so its action stays disabled.
      await tester.tap(find.byKey(const Key('plan-card-free')));
      await tester.pumpAndSettle();
      expect(find.text('Current Plan'), findsNWidgets(2));
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('membership-action-button')),
      );
      expect(button.onPressed, isNull);

      // Tapping the disabled button goes nowhere.
      await tester.tap(find.byKey(const Key('membership-action-button')));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade Your Experience'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to Account'));
      await tester.pumpAndSettle();
      expect(find.text('Free Plan'), findsOneWidget);
    });
  });
}
