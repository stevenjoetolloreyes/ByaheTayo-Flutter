// Smoke tests for the ByaheTayo shell: all 6 destinations render and tab
// switching changes the visible tab on both wide (collapsible sidebar)
// and phone (NavigationBar) layouts.
import 'package:byahetayo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _labels = [
  'Map',
  'Fares',
  'Student',
  'Friends',
  'Communities',
  'Account',
];

void main() {
  testWidgets('Map tab shows a real Google Map on launch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ByaheTayoApp());
    expect(find.byType(GoogleMap), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('Wide layout shows collapsible sidebar with all 6 destinations',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ByaheTayoApp());

    expect(find.byKey(const Key('sidebar-container')), findsOneWidget);
    for (final label in _labels) {
      expect(find.text(label), findsWidgets);
    }

    // Switch to Communities: the moved Community section follows.
    await tester.tap(find.byKey(const Key('sidebar-item-Communities')));
    await tester.pumpAndSettle();
    expect(find.text('Know something that can help commuters?'),
        findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    // First launch seeds the pending CTransco sample, so the tab
    // shows it instead of the empty state.
    expect(find.text('Vigan City → Cabugao'), findsOneWidget);
    expect(find.text('Pending verification'), findsOneWidget);

    // Switch to Account; the AppBar title and the dashboard follow.
    await tester.tap(find.byKey(const Key('sidebar-item-Account')));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Points Wallet'), findsOneWidget);
  });

  testWidgets('Phone layout shows bottom bar and switches tabs',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const ByaheTayoApp());

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in _labels) {
      expect(find.text(label, skipOffstage: true), findsWidgets);
    }

    await tester.tap(find.text('Student', skipOffstage: true));
    await tester.pumpAndSettle();
    expect(
      find.text('Student Hub', skipOffstage: true),
      findsOneWidget,
    );

    // Communities sits after Friends: switching shows the moved section.
    // (The section title sits below the share card, so the finder needs
    // skipOffstage: false in this phone viewport even though the tab
    // is selected and the content is in the tree.)
    await tester.tap(find.text('Communities', skipOffstage: true));
    await tester.pumpAndSettle();
    expect(
      find.text('Community', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Share info', skipOffstage: true),
      findsOneWidget,
    );
  });
}
