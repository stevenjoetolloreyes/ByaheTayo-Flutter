// Widget tests for the Trips tab (no location, no storage needed).
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/trips_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

/// Scrolls the Trips list until [target] is built, then returns.
/// The list holds ~179 route cards, so off-screen rows are not
/// built until scrolled into view — a tall viewport alone cannot
/// cover them. The target is made fully visible before returning,
/// or a tap on it can miss (scrolling stops as soon as the row is
/// built, even if only its edge shows).
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Trips shows Find a Route and nearby routes by default',
      (tester) async {
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    expect(find.text('Find a Route'), findsOneWidget);
    // 16 hubs + 164 bundled places, minus the Cabugao origin.
    expect(
      find.text('Nearby Routes (${allHubs([]).length - 1})'),
      findsOneWidget,
    );
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
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View full route').first);
    await tester.pumpAndSettle();
    // The expanded detail is at the top — check it before scrolling
    // down, or it scrolls out of the tree.
    expect(find.text('Estimated fare'), findsWidgets);
    // Recents render below the ~179 nearby cards — scroll to them.
    await scrollTo(tester, find.text('Recent trips'));
    expect(find.text('Recent trips'), findsOneWidget);
    expect(find.text('Current session only'), findsOneWidget);
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
    await tester.pumpWidget(wrap(const TripsTab()));
    await tester.pumpAndSettle();
    // The directory sits below the ~179 nearby cards — scroll to it.
    await scrollTo(tester, find.text('Routes Directory · From Cabugao'));
    expect(find.text('Routes Directory · From Cabugao'), findsOneWidget);
    // Northbound is dest lat >= Cabugao's (17.78916); the bundled
    // Philippines list adds destinations in every direction, so the
    // split is derived from the data, not pinned to the old
    // 16-hub counts (3 north / 12 south).
    final north = allHubs([]).where(
      (h) => h.name != 'Cabugao' && h.lat >= 17.78916,
    ).length;
    final south = allHubs([]).where(
      (h) => h.name != 'Cabugao' && h.lat < 17.78916,
    ).length;
    await scrollTo(tester, find.text('↑ NORTHBOUND ($north)'));
    expect(find.text('↑ NORTHBOUND ($north)'), findsOneWidget);
    await scrollTo(tester, find.text('↓ SOUTHBOUND ($south)'));
    expect(find.text('↓ SOUTHBOUND ($south)'), findsOneWidget);
  });

  testWidgets('Directory detail shows stops and View on map',
      (tester) async {
    var jumped = false;
    await tester.pumpWidget(wrap(TripsTab(onViewOnMap: () => jumped = true)));
    await tester.pumpAndSettle();
    // The directory sits below the ~179 nearby cards — scroll to it
    // first, so the row found is the directory row, not a nearby
    // card.
    await scrollTo(tester, find.text('Routes Directory · From Cabugao'));
    await scrollTo(tester, find.text('San Juan, Ilocos Sur'));
    await tester.tap(find.text('San Juan, Ilocos Sur'));
    await tester.pumpAndSettle();
    expect(find.text('First stop'), findsOneWidget);
    expect(find.text('Last stop'), findsOneWidget);
    expect(find.text('Direct route — no intermediate stops.'),
        findsOneWidget);
    await tester.ensureVisible(find.text('View on map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on map'));
    await tester.pumpAndSettle();
    expect(jumped, isTrue);
  });
}
