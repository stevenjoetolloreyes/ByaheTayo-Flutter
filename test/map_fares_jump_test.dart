// End-to-end: Fares "Find routes" / "Show direction on Map" open
// the Map tab WITH the selected route (preview parity, Nov 6,
// 2026) — direction line + route title + ETA • FARE + verified
// fare on the draggable sheet. Before this change the buttons only
// switched tabs and the Map opened with no route at all.
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
  // Anime splash (Nov 7): one master animation drives the whole
  // ~4.9 s intro, so a single settle carries it to the handoff.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Find routes opens the Map tab with the selected route',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('top-nav-item-Fares')));
    await tester.pumpAndSettle();

    // Hub origin: the default origin hub is Cabugao, destination
    // Vigan Bus Terminal.
    await tester.tap(find.text('Choose a hub'));
    await tester.pump();
    // The Trip card's picker fields are taller than the old
    // dropdowns, so Find routes sits just below the fold on a
    // 390×844 phone — scroll it into view before tapping.
    await tester.ensureVisible(find.text('Find routes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find routes'));
    await tester.pumpAndSettle();

    // The Map tab is now selected and shows the route title in its
    // fixed sheet header, with the VERIFIED FARE badge for the
    // ₱60/₱48 trip.
    expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
    expect(find.text('VERIFIED FARE'), findsOneWidget);
  });

  testWidgets('route sheet Show direction on Map jumps to the Map route',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('top-nav-item-Fares')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.text('Cabugao → Vigan Bus Terminal'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
    await tester.pumpAndSettle();
    expect(find.text('Fare breakdown'), findsOneWidget);
    // The sheet scrolls: the action sits below the fold on a
    // 390px phone, so scroll it into view before tapping.
    await tester.ensureVisible(find.text('Show direction on Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show direction on Map'));
    await tester.pumpAndSettle();

    expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
    expect(find.text('VERIFIED FARE'), findsOneWidget);
  });

  testWidgets('route sheet Start Ride jumps to the Map route', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('top-nav-item-Fares')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.text('Cabugao → Vigan Bus Terminal'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
    await tester.pumpAndSettle();
    expect(find.text('Fare breakdown'), findsOneWidget);
    // Start Ride sits above 'Show direction on Map' in the
    // sheet's action row (Nov 8, 2026).
    expect(find.text('Start Ride'), findsOneWidget);
    await tester.ensureVisible(find.text('Start Ride'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Ride'));
    await tester.pumpAndSettle();

    // The jump draws the route on the Map. Live Follow itself
    // cannot start in a widget test (no location platform
    // channel) — _startLiveFollow catches that and shows the
    // honest message instead of crashing, so the route still
    // lands.
    expect(find.text('Cabugao → Vigan Bus Terminal'), findsWidgets);
    expect(find.text('VERIFIED FARE'), findsOneWidget);
  });
}
