// Widget tests for the Trips tab (no location, no storage needed).
import 'package:estudyantego/features/trips_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('Trips shows Find a Route and nearby routes by default',
      (tester) async {
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    expect(find.text('Find a Route'), findsOneWidget);
    // 16 hubs minus the Cabugao origin = 15 nearby routes.
    expect(find.text('Nearby Routes (15)'), findsOneWidget);
    // Nearest to the Cabugao default origin is San Juan, Ilocos Sur.
    expect(find.text('Cabugao → San Juan, Ilocos Sur'), findsOneWidget);
  });

  testWidgets('Search filters routes by destination', (tester) async {
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Vigan');
    await tester.pumpAndSettle();
    expect(find.text('Cabugao → Vigan City'), findsOneWidget);
    expect(find.text('Cabugao → San Juan, Ilocos Sur'), findsNothing);
  });

  testWidgets('View full route expands details and records a recent trip',
      (tester) async {
    // Tall viewport so the whole list (including recents, which render
    // below the nearby cards) builds without scrolling. Cards wrap to
    // two lines, so the viewport must clear ~3000px of content — now
    // taller with 15 nearby routes instead of 13.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 7000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View full route').first);
    await tester.pumpAndSettle();
    expect(find.text('Recent trips'), findsOneWidget);
    expect(find.text('Current session only'), findsOneWidget);
    expect(find.text('Estimated fare'), findsWidgets);
  });

  testWidgets('Bus vehicle filter reprices cards with the bus fare',
      (tester) async {
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    // Default Jeepney mode: the San Juan route costs ₱20.
    expect(find.text('₱20'), findsWidgets);
    await tester.tap(find.text('Bus'));
    await tester.pumpAndSettle();
    // Ordinary provincial bus has a ₱100 minimum, so short routes show ₱100.
    expect(find.text('₱100'), findsWidgets);
  });

  testWidgets('Routes Directory groups routes by direction', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    expect(find.text('Routes Directory · From Cabugao'), findsOneWidget);
    // 3 north (Sinait, Laoag City, Laoag Terminal) / 12 south
    // (the Vigan Bus Terminal joins the southbound group).
    expect(find.text('↑ NORTHBOUND (3)'), findsOneWidget);
    expect(find.text('↓ SOUTHBOUND (12)'), findsOneWidget);
  });

  testWidgets('Directory detail shows stops and View on map',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    var jumped = false;
    await tester.pumpWidget(wrap(TripsTab(onViewOnMap: () => jumped = true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('San Juan, Ilocos Sur'));
    await tester.pumpAndSettle();
    expect(find.text('First stop'), findsOneWidget);
    expect(find.text('Last stop'), findsOneWidget);
    expect(find.text('Direct route — no intermediate stops.'),
        findsOneWidget);
    await tester.tap(find.text('View on map'));
    await tester.pumpAndSettle();
    expect(jumped, isTrue);
  });
}
