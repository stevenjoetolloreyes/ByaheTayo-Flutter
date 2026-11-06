// Smoke tests for the EstudyanteGO shell: all 6 destinations render and tab
// switching changes the visible tab on both wide (collapsible sidebar)
// and phone (icon-only top nav) layouts.
//
// The app now boots through the first-time gate (splash -> dashboard
// when onboarding is already done), so these tests set the onboarding
// flag in mock prefs and settle past the 1.2s splash. Student is the
// default tab on open; the top nav order is Student, Friends, Fares,
// Map, Communities, Account.
import 'package:estudyantego/features/top_nav.dart';
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _labels = [
  'Student',
  'Friends',
  'Fares',
  'Map',
  'Communities',
  'Account',
];

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'byahetayo_onboarding_done': true});
  await tester.pumpWidget(const EstudyanteGOApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Student tab is the default tab on launch', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);
    expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);
  });

  testWidgets('Map tab shows a real OpenStreetMap when selected', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('sidebar-item-Map')));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('Wide layout shows collapsible sidebar with all 6 destinations', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('sidebar-container')), findsOneWidget);
    for (final label in _labels) {
      expect(find.text(label), findsWidgets);
    }

    // Switch to Communities: the moved Community section follows.
    await tester.tap(find.byKey(const Key('sidebar-item-Communities')));
    await tester.pumpAndSettle();
    expect(
      find.text('Know something that can help commuters?'),
      findsOneWidget,
    );
    expect(find.text('Community'), findsOneWidget);
    // First launch seeds the pending CTransco sample, so the tab
    // shows it instead of the empty state.
    expect(find.text('Vigan City → Cabugao'), findsOneWidget);
    expect(find.text('In Review'), findsOneWidget);

    // Switch to Account; the AppBar title and the dashboard follow.
    // No Firebase in tests, so the account shows the honest
    // signed-out state — never a "Guest" identity.
    await tester.tap(find.byKey(const Key('sidebar-item-Account')));
    await tester.pumpAndSettle();
    expect(find.text('No account signed in'), findsOneWidget);
    expect(find.text('Points Wallet'), findsOneWidget);
    expect(find.text('Guest'), findsNothing);
  });

  testWidgets('Phone layout shows top nav and switches tabs', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    await _pumpApp(tester);

    expect(find.byType(TopNavBar), findsOneWidget);
    expect(find.byKey(const Key('floating-nav')), findsNothing);
    // The top nav is icon-only: labels live on semantics/tooltips.
    for (final label in _labels) {
      expect(
        find.byKey(Key('top-nav-item-$label')),
        findsOneWidget,
      );
    }
    // Header: plain "EstudyanteGO" wordmark + notifications bell.
    expect(find.text('EstudyanteGO'), findsOneWidget);
    expect(
      find.byKey(const Key('header-notifications')),
      findsOneWidget,
    );
    // Student is the default tab.
    expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);

    await tester.tap(find.byKey(const Key('top-nav-item-Student')));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub', skipOffstage: true), findsOneWidget);

    // Communities sits after Friends: switching shows the moved section.
    // (The section title sits below the share card, so the finder needs
    // skipOffstage: false in this phone viewport even though the tab
    // is selected and the content is in the tree.)
    await tester.tap(find.byKey(const Key('top-nav-item-Communities')));
    await tester.pumpAndSettle();
    expect(find.text('Community', skipOffstage: false), findsOneWidget);
    expect(find.text('Share info', skipOffstage: true), findsOneWidget);
  });
}
