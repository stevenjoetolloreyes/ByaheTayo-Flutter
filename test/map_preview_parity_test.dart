// Preview parity: the Map tab matches the Fares Phone Preview
// (Nov 7, 2026) — clean map (only the active route's numbered
// stop pins), centred draggable ETA • FARE sheet, no search bar,
// no chips, no Nearby Routes / Plan a Trip sheet. Before this
// rebuild the Map showed all 16 hub pins plus church clusters,
// a search bar + Malls/Schools/Hospitals/Churches chips, and the
// Nearby Routes sheet with filters.
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'byahetayo_onboarding_done': true});
  await tester.pumpWidget(const EstudyanteGOApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('splash-start')));
  await tester.pumpAndSettle();
}

Future<void> _openMap(WidgetTester tester) async {
  await _pumpApp(tester);
  await tester.tap(find.byKey(const Key('top-nav-item-Map')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Map tab is clean: no search, no chips, no Nearby Routes',
      (tester) async {
    await _openMap(tester);

    // The old Map UI is gone entirely.
    expect(find.text('Nearby Routes'), findsNothing);
    expect(find.text('Plan a Trip'), findsNothing);
    expect(find.text('Malls'), findsNothing);
    expect(find.text('Schools'), findsNothing);
    expect(find.text('Hospitals'), findsNothing);
    expect(find.text('Churches'), findsNothing);
    expect(find.text('All stops'), findsNothing);
    expect(find.text('Live Tracking'), findsNothing);

    // No hub pins: the old scattered pins were Icons.place
    // markers; the clean map shows numbered stop pins only.
    expect(find.byIcon(Icons.place), findsNothing);

    // The numbered stop pins are on the map (origin + destination
    // without road geometry; more stops appear once OSRM loads).
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('Map sheet is the preview ETA • FARE sheet on the default route',
      (tester) async {
    await _openMap(tester);

    // Fixed header: ETA • FARE + route title + verified badge.
    expect(find.text('ETA • FARE'), findsOneWidget);
    expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
    expect(find.text('VERIFIED FARE'), findsOneWidget);

    // Fare cards: the verified ₱60 / ₱48. (The app's shared
    // peso() formatter drops trailing '.00', so the cards read
    // '₱60' / '₱48' where the preview shows '₱60.00' / '₱48.00'
    // — same verified values, different trailing zeros.)
    expect(find.text('REGULAR FARE'), findsOneWidget);
    expect(find.text('₱60'), findsOneWidget);
    expect(find.text('DISCOUNTED -20%'), findsOneWidget);
    expect(find.text('₱48'), findsOneWidget);

    // Duration + distance (estimate model until OSRM loads: the
    // 32.3 km in the preview is the live OSRM road length; the
    // app's roadKm estimate for this pair is 31.6 km).
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('1 hr 10 min'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('31.6 km'), findsOneWidget);

    // Stops list (origin + destination without road geometry).
    expect(find.text('STOPS ALONG THE WAY'), findsOneWidget);
    expect(find.text('Cabugao'), findsWidgets);
    expect(find.text('Vigan Bus Terminal'), findsWidgets);

    // The draggable sheet's centred state label (Peek by default).
    expect(find.textContaining('PEEK'), findsOneWidget);
  });

  testWidgets('Map sheet hides and returns via the bus button',
      (tester) async {
    await _openMap(tester);

    expect(find.text('ETA • FARE'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide bottom panel'));
    await tester.pumpAndSettle();
    expect(find.text('ETA • FARE'), findsNothing);

    await tester.tap(find.byTooltip('Show bottom panel'));
    await tester.pumpAndSettle();
    expect(find.text('ETA • FARE'), findsOneWidget);
  });
}
