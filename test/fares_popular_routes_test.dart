// Tests for the Fares tab restyle (Nov 6, 2026): Popular Routes
// list + filters, fare breakdown arithmetic, and the breakdown
// sheet. The calculator itself is unchanged — these tests pin that
// the breakdown always agrees with computeFare, and that the
// route list never carries a sample fare.
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FareRate rate(String id) => fareRates.firstWhere((r) => r.id == id);

void main() {
  group('fareBreakdownFor', () {
    test('agrees with computeFare for every rate and distance', () {
      const distances = [0.5, 4.0, 5.0, 10.0, 31.6, 100.0];
      for (final r in fareRates) {
        for (final km in distances) {
          for (final discounted in [false, true]) {
            final expected = computeFare(r, km, discounted);
            final breakdown = fareBreakdownFor(r, km, discounted)!;
            expect(breakdown.regular, expected.regular);
            expect(breakdown.collected, expected.collected);
            // The rows add up: base + distance (+ minimum) = regular.
            expect(
              breakdown.base +
                  breakdown.distanceFare +
                  breakdown.minimumAdjustment,
              closeTo(breakdown.regular, 0.001),
            );
          }
        }
      }
    });

    test('brief verified example: modern jeepney, 31.6 km, student', () {
      // Cabugao -> Vigan Bus Terminal by the formula: base ₱17 +
      // 28 km x ₱2.40 = ₱84.20; 20% off -> ₱67.25.
      final breakdown =
          fareBreakdownFor(rate('modern-jeep'), 31.6, true)!;
      expect(breakdown.base, 17);
      expect(breakdown.billableKm, 28);
      expect(breakdown.distanceFare, closeTo(67.2, 0.001));
      expect(breakdown.formulaFare, closeTo(84.2, 0.001));
      expect(breakdown.minimumAdjustment, 0);
      expect(breakdown.regular, closeTo(84.2, 0.001));
      expect(breakdown.collected, 67.25);
    });

    test('provincial minimum beats the formula, shown as adjustment', () {
      // Air-con provincial bus at 32.3 km: formula ₱80.60, raised
      // to the ₱100 minimum.
      final breakdown =
          fareBreakdownFor(rate('prov-aircon'), 32.3, false)!;
      expect(breakdown.formulaFare, closeTo(80.6, 0.001));
      expect(breakdown.minimumAdjustment, closeTo(19.4, 0.001));
      expect(breakdown.regular, 100);
      expect(breakdown.collected, 100);
    });

    test('discounted fare rounds to the nearest ₱0.25', () {
      expect(
        fareBreakdownFor(rate('trad-jeep'), 10.0, true)!.collected,
        20.75,
      );
      expect(discountedFareOf(60), 48);
      expect(discountedFareOf(20), 16);
    });
  });

  group('popularRoutes data honesty', () {
    test('verified fares only — no sample fare anywhere', () {
      for (final route in popularRoutes) {
        // Preview samples that must never appear as real fares.
        expect(route.fare, isNot(45));
        expect(route.fare, isNot(120));
      }
      final cabugaoVigan = popularRoutes.firstWhere(
        (r) => r.from == 'Cabugao' && r.to == 'Vigan Bus Terminal',
      );
      expect(cabugaoVigan.fare, 60);
      expect(cabugaoVigan.fareLabel, 'Verified bus fare');
      // The sample-only Dominion Van route is omitted entirely.
      expect(
        popularRoutes.where((r) => r.operator == 'Dominion'),
        isEmpty,
      );
    });

    test('named no-fare routes show no fare', () {
      final laoagCubao = popularRoutes.firstWhere(
        (r) => r.from == 'Laoag Partas Terminal',
      );
      expect(laoagCubao.operator, 'Partas');
      expect(laoagCubao.fare, isNull);
      final gmw = popularRoutes.firstWhere(
        (r) => r.operator == 'GMW Trans',
      );
      expect(gmw.fare, isNull);
      expect(gmw.distanceKm, 401.0);
    });

    test('hub routes compute the calculator road distance', () {
      final cabugaoVigan = popularRoutes.firstWhere(
        (r) => r.from == 'Cabugao' && r.to == 'Vigan Bus Terminal',
      );
      expect(cabugaoVigan.roadKm, closeTo(31.6, 0.05));
      expect(cabugaoVigan.hasHubEndpoints, isTrue);
      final laoagCubao = popularRoutes.firstWhere(
        (r) => r.from == 'Laoag Partas Terminal',
      );
      expect(laoagCubao.hasHubEndpoints, isFalse);
      expect(laoagCubao.roadKm, isNull);
    });

    test('every listed route is a bus route with a Provincial scope', () {
      expect(popularRoutes.length, 7);
      for (final route in popularRoutes) {
        expect(route.vehicle, 'Bus');
        expect(route.isBus, isTrue);
      }
    });
  });

  group('filterPopularRoutes', () {
    test('vehicle filter: all 7 are bus routes', () {
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
        ).length,
        7,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'All',
        ).length,
        7,
      );
      for (final vehicle in ['Van', 'Jeepney', 'Tricycle']) {
        expect(
          filterPopularRoutes(
            popularRoutes,
            vehicle: vehicle,
            operator: 'All',
          ),
          isEmpty,
        );
      }
    });

    test('operator filter matches the preview counts', () {
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'Partas',
        ).length,
        1,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'GMW Trans',
        ).length,
        1,
      );
      for (final operator in [
        'GV Florida',
        'Dominion',
        'Viron',
        'Victory Liner',
        'Solid North',
        'Dagupan Bus',
        'Genesis',
        'Five Star',
        'JAC Liner',
        'ALPS',
        'Bicol Isarog',
      ]) {
        expect(
          filterPopularRoutes(
            popularRoutes,
            vehicle: 'Bus',
            operator: operator,
          ),
          isEmpty,
        );
      }
    });

    test('operator matching tolerates full vs short names', () {
      expect(popularRouteMatchesOperator('Dominion Bus Lines', 'Dominion'),
          isTrue);
      expect(popularRouteMatchesOperator('ALPS The Bus', 'ALPS'), isTrue);
      expect(
          popularRouteMatchesOperator('GV Florida Transport', 'GV Florida'),
          isTrue);
      expect(popularRouteMatchesOperator('Partas', 'Partas'), isTrue);
      expect(popularRouteMatchesOperator(null, 'Partas'), isFalse);
      expect(popularRouteMatchesOperator(null, 'All'), isTrue);
      expect(popularRouteMatchesOperator('Partas', 'All'), isTrue);
    });

    test('admin custom routes join the list with their own fare', () {
      const custom = CustomRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        operator: 'Partas',
        vehicle: 'Bus',
        fare: 60,
      );
      final converted = popularRouteFromCustomRoute(custom);
      expect(converted.fare, 60);
      expect(converted.fareLabel, 'Admin-entered fare');
      final filtered = filterPopularRoutes(
        [...popularRoutes, converted],
        vehicle: 'Bus',
        operator: 'Partas',
      );
      expect(filtered.length, 2);
      expect(filtered, contains(converted));
    });
  });

  group('Fares tab restyle widgets', () {
    Future<void> pumpTab(WidgetTester tester, {VoidCallback? onViewOnMap}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FaresTab(onViewOnMap: onViewOnMap)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hero, chips, and Popular Routes render', (tester) async {
      await pumpTab(tester);
      expect(find.text('Know your fare before you go'), findsOneWidget);
      expect(find.text('Popular Routes'), findsOneWidget);
      expect(find.text('7 routes'), findsOneWidget);
      for (final label in ['All', 'Bus', 'Van', 'Jeepney', 'Tricycle']) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
        );
      }
      // Bus operator row only appears with the Bus chip active.
      expect(
        find.text('Bus operator — Luzon, city & provincial'),
        findsNothing,
      );
      expect(
        find.text('Cabugao → Vigan Bus Terminal'),
        findsOneWidget,
      );
      expect(find.text('₱60'), findsOneWidget);
      expect(find.text('₱48 student'), findsOneWidget);
      expect(find.text('Fare not set'), findsWidgets);
      expect(find.text('Provincial'), findsWidgets);
      // No dead Find routes button when the host does not wire it.
      expect(find.text('Find routes'), findsNothing);
    });

    testWidgets('Bus chip reveals the operator row; empty states are honest',
        (tester) async {
      await pumpTab(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bus'));
      await tester.pump();
      expect(
        find.text('Bus operator — Luzon, city & provincial'),
        findsOneWidget,
      );
      // 'All' is skipped here: the vehicle row and the operator row
      // both carry an All chip once the operator row is visible.
      for (final label in ['Partas', 'GMW Trans', 'GV Florida']) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'GV Florida'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'GV Florida'));
      await tester.pump();
      expect(find.text('No GV Florida routes yet.'), findsOneWidget);
      expect(find.text('0 routes'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'GMW Trans'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'GMW Trans'));
      await tester.pump();
      expect(find.text('1 route'), findsOneWidget);
      expect(
        find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
        findsOneWidget,
      );
      // Switching vehicle resets the operator filter to All.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Van'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Van'));
      await tester.pump();
      expect(
        find.text('Bus operator — Luzon, city & provincial'),
        findsNothing,
      );
      expect(find.text('No van routes yet.'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bus'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bus'));
      await tester.pump();
      expect(find.text('7 routes'), findsOneWidget);
    });

    testWidgets('tapping a verified route opens its breakdown sheet',
        (tester) async {
      await pumpTab(tester);
      await tester.ensureVisible(
        find.text('Cabugao → Vigan Bus Terminal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('Fare breakdown'), findsOneWidget);
      expect(find.text('Verified bus fare'), findsOneWidget);
      // ₱48 three times now: one row per discount group (Student,
      // PWD, Senior Citizen — preview parity, Nov 6).
      expect(find.text('₱48'), findsNWidgets(3));
      // Tapping loaded the route into the calculator, so the real
      // LTFRB breakdown for the current vehicle is shown too.
      expect(find.text('Calculator estimate'), findsOneWidget);
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('Amount to pay'), findsOneWidget);
      // Close the sheet: the calculator now holds the loaded route.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('31.6 km'), findsOneWidget);
    });

    testWidgets('tapping a no-fare route shows Fare not set, no invented fare',
        (tester) async {
      await pumpTab(tester);
      await tester.ensureVisible(
        find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fare breakdown'), findsOneWidget);
      expect(find.text('Fare not set'), findsWidgets);
      expect(
        find.text('No fare has been set for this route yet.'),
        findsOneWidget,
      );
      expect(find.text('401.0 km'), findsOneWidget);
      expect(find.text('Calculator estimate'), findsNothing);
    });

    testWidgets('See breakdown shows the real arithmetic (₱67.25 example)',
        (tester) async {
      await pumpTab(tester);
      await tester.tap(find.text('Choose a hub'));
      await tester.pump();
      expect(find.text('See breakdown'), findsOneWidget);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modern jeepney'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Student / Senior / PWD · 20% off'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student / Senior / PWD · 20% off'));
      await tester.pump();
      await tester.ensureVisible(find.text('See breakdown'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See breakdown'));
      await tester.pumpAndSettle();
      expect(find.text('Fare breakdown'), findsOneWidget);
      expect(find.text('Calculator estimate'), findsOneWidget);
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('28 km × ₱2.40 per km'), findsOneWidget);
      expect(find.text('≈ ₱67.25'), findsWidgets);
    });

    testWidgets('swap button exchanges From and To', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.text('Choose a hub'));
      await tester.pump();
      await tester.tap(find.byTooltip('Swap From and To'));
      await tester.pump();
      expect(find.text('Vigan Bus Terminal · Ilocos Sur'), findsOneWidget);
      expect(find.text('31.6 km'), findsOneWidget);
    });

    testWidgets('Find routes appears only when the host wires onViewOnMap',
        (tester) async {
      var opened = 0;
      await pumpTab(tester, onViewOnMap: () => opened++);
      expect(find.text('Find routes'), findsOneWidget);
      await tester.tap(find.text('Find routes'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets(
        'Find routes sets the Fares → Map jump before switching tabs',
        (tester) async {
      faresMapJump.value = null;
      var opened = 0;
      await pumpTab(tester, onViewOnMap: () => opened++);
      // Hub origin: the default origin hub is Cabugao and the
      // default destination is Vigan Bus Terminal.
      await tester.tap(find.text('Choose a hub'));
      await tester.pump();
      await tester.tap(find.text('Find routes'));
      await tester.pump();
      expect(opened, 1);
      expect(faresMapJump.value?.from, 'Cabugao');
      expect(faresMapJump.value?.to, 'Vigan Bus Terminal');
      faresMapJump.value = null;
    });

    testWidgets(
        'verified route sheet shows ETA, fare status, separate discounts, stops',
        (tester) async {
      // onViewOnMap wired: the sheet's 'Show direction on Map'
      // button only renders when the host provides it.
      await pumpTab(tester, onViewOnMap: () {});
      await tester.ensureVisible(
        find.text('Cabugao → Vigan Bus Terminal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('Fare breakdown'), findsOneWidget);
      // Preview parity (Nov 6): ETA next to the distance, fare
      // status, and one row per discount group.
      expect(find.text('ETA'), findsOneWidget);
      expect(find.text('Fare status'), findsOneWidget);
      expect(find.text('Verified fare'), findsWidgets);
      expect(find.text('Student discount'), findsOneWidget);
      expect(find.text('PWD discount'), findsOneWidget);
      expect(find.text('Senior Citizen discount'), findsOneWidget);
      expect(find.text('₱48'), findsWidgets);
      expect(
        find.text(
          'The discounted fare applies to students, PWD, and senior citizens with a valid ID.',
        ),
        findsOneWidget,
      );
      // Stops along the way: origin + destination, no invented
      // intermediate towns (the Map tab adds those from OSRM).
      expect(find.text('Stops along the way'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.text('Show direction on Map'), findsOneWidget);
    });

    testWidgets('no-fare route sheet shows Fare not set status + ETA',
        (tester) async {
      // onViewOnMap wired: the sheet's 'Show direction on Map'
      // button only renders when the host provides it.
      await pumpTab(tester, onViewOnMap: () {});
      await tester.ensureVisible(
        find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fare breakdown'), findsOneWidget);
      expect(find.text('Fare status'), findsOneWidget);
      expect(find.text('Fare not set'), findsWidgets);
      expect(find.text('ETA'), findsOneWidget);
      expect(find.text('401.0 km'), findsOneWidget);
    });
  });
}
