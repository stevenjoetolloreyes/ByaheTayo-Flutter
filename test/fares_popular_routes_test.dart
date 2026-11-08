// Tests for the Fares tab restyle (Nov 6, 2026): Popular Routes
// list + filters, fare breakdown arithmetic, and the breakdown
// sheet. The calculator itself is unchanged — these tests pin that
// the breakdown always agrees with computeFare, and that the
// route list never carries a sample fare.
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
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
      final breakdown = fareBreakdownFor(rate('modern-jeep'), 31.6, true)!;
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
      final breakdown = fareBreakdownFor(rate('prov-aircon'), 32.3, false)!;
      expect(breakdown.formulaFare, closeTo(80.6, 0.001));
      expect(breakdown.minimumAdjustment, closeTo(19.4, 0.001));
      expect(breakdown.regular, 100);
      expect(breakdown.collected, 100);
    });

    test('discounted fare rounds to the nearest ₱0.25', () {
      expect(fareBreakdownFor(rate('trad-jeep'), 10.0, true)!.collected, 20.75);
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
      expect(popularRoutes.where((r) => r.operator == 'Dominion'), isEmpty);
    });

    test('named no-fare routes show no fare', () {
      final laoagCubao = popularRoutes.firstWhere(
        (r) => r.from == 'Laoag Partas Terminal',
      );
      expect(laoagCubao.operator, 'Partas');
      expect(laoagCubao.fare, isNull);
      final gmw = popularRoutes.firstWhere((r) => r.operator == 'GMW Trans');
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
          filterPopularRoutes(popularRoutes, vehicle: vehicle, operator: 'All'),
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
      expect(
        popularRouteMatchesOperator('Dominion Bus Lines', 'Dominion'),
        isTrue,
      );
      expect(popularRouteMatchesOperator('ALPS The Bus', 'ALPS'), isTrue);
      expect(
        popularRouteMatchesOperator('GV Florida Transport', 'GV Florida'),
        isTrue,
      );
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

    test('region filter matches either endpoint', () {
      expect(regionOfRouteEndpoint('Cabugao', []), 'Ilocos Sur');
      expect(regionOfRouteEndpoint('Vigan Bus Terminal', []), 'Ilocos Sur');
      expect(regionOfRouteEndpoint('Laoag Terminal', []), 'Ilocos Norte');
      // Terminal names are not places: no region is invented.
      expect(regionOfRouteEndpoint('Laoag Partas Terminal', []), isNull);
      expect(regionOfRouteEndpoint('Cubao Partas Terminal', []), isNull);
      expect(
        routeRegions(popularRoutes, []),
        ['Ilocos Sur', 'Ilocos Norte'],
      );
      // Ilocos Sur touches five routes (Laoag → Vigan via its
      // Vigan destination); Ilocos Norte touches one.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Ilocos Sur',
        ).length,
        5,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Ilocos Norte',
        ).length,
        1,
      );
      // The two terminal routes have no region: only 'All' shows
      // them.
      final ilocos = filterPopularRoutes(
        popularRoutes,
        vehicle: 'All',
        operator: 'All',
        region: 'Ilocos Sur',
      );
      expect(
        ilocos.map((r) => r.from),
        isNot(contains('Laoag Partas Terminal')),
      );
    });

    test('fare status reuses the breakdown sheet states', () {
      for (final route in popularRoutes) {
        if (route.fareLabel == 'Verified bus fare') {
          expect(popularRouteFareStatus(route), 'Verified');
        } else {
          expect(popularRouteFareStatus(route), 'Not set');
        }
      }
      // An admin override turns a verified fare into Admin-set
      // (the VERIFIED badge is suppressed for it).
      final overridden = popularRoutes.first.applyOverride(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          fare: 55,
        ),
      );
      expect(popularRouteFareStatus(overridden), 'Admin-set');
      // A custom route's own fare is admin-entered, also Admin-set.
      const custom = CustomRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        operator: 'Partas',
        vehicle: 'Bus',
        fare: 60,
      );
      expect(
        popularRouteFareStatus(popularRouteFromCustomRoute(custom)),
        'Admin-set',
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          fareStatus: 'Verified',
        ).length,
        3,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          fareStatus: 'Admin-set',
        ),
        isEmpty,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          fareStatus: 'Not set',
        ).length,
        4,
      );
    });

    test('filters combine across categories', () {
      // Bus + Ilocos Sur + Verified: the three verified routes.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'All',
          region: 'Ilocos Sur',
          fareStatus: 'Verified',
        ).length,
        3,
      );
      // Ilocos Norte + Verified: the Laoag → Vigan route has no
      // fare, so nothing matches.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Ilocos Norte',
          fareStatus: 'Verified',
        ),
        isEmpty,
      );
      // Partas + Ilocos Sur: the Partas route has no region.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'Partas',
          region: 'Ilocos Sur',
        ),
        isEmpty,
      );
    });

    test('routesCountLabel shows the total when unfiltered', () {
      expect(routesCountLabel(filtered: 7, total: 7), '7 routes');
      expect(routesCountLabel(filtered: 1, total: 1), '1 route');
      expect(routesCountLabel(filtered: 1, total: 7), '1 of 7');
      expect(routesCountLabel(filtered: 0, total: 7), '0 of 7');
      expect(routesCountLabel(filtered: 0, total: 1), '0 of 1');
    });
  });

  group('Fares tab restyle widgets', () {
    Future<void> pumpTab(
      WidgetTester tester, {
      VoidCallback? onViewOnMap,
    }) async {
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
      // Four filter rows, each carrying its own All chip.
      expect(find.widgetWithText(ChoiceChip, 'All'), findsNWidgets(4));
      for (final label in ['Bus', 'Van', 'Jeepney', 'Tricycle']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      // The operator row is a proper category now — always
      // visible, not hidden behind the Bus chip.
      expect(
        find.text('Bus operator — Luzon, city & provincial'),
        findsOneWidget,
      );
      // Region + fare rows, with only the regions that have routes.
      expect(find.text('Region'), findsOneWidget);
      expect(find.text('Fare'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Ilocos Sur'), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, 'Ilocos Norte'),
        findsOneWidget,
      );
      for (final label in ['Verified', 'Admin-set', 'Not set']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      // No filter active, so no Clear filters button.
      expect(find.text('Clear filters'), findsNothing);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
      expect(find.text('₱60'), findsOneWidget);
      expect(find.text('₱48 student'), findsOneWidget);
      expect(find.text('Fare not set'), findsWidgets);
      expect(find.text('Provincial'), findsWidgets);
      // No dead Find routes button when the host does not wire it.
      expect(find.text('Find routes'), findsNothing);
    });

    testWidgets(
      'operator row is always visible; switching vehicle disables it; '
      'empty states are honest',
      (tester) async {
        await pumpTab(tester);
        // The operator row is a proper category now — visible from
        // the start, not hidden behind the Bus chip.
        expect(
          find.text('Bus operator — Luzon, city & provincial'),
          findsOneWidget,
        );
        for (final label in ['Partas', 'GMW Trans', 'GV Florida']) {
          expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
        }
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bus'));
        await tester.pump();
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'GV Florida'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'GV Florida'));
        await tester.pump();
        expect(find.text('No GV Florida routes yet.'), findsOneWidget);
        expect(find.text('0 of 7'), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'GMW Trans'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'GMW Trans'));
        await tester.pump();
        expect(find.text('1 of 7'), findsOneWidget);
        expect(
          find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
          findsOneWidget,
        );
        // Switching vehicle resets the operator filter to All and
        // DISABLES the row (it stays visible — operators only
        // apply to Bus routes).
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Van'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Van'));
        await tester.pump();
        expect(
          find.text('Bus operator — Luzon, city & provincial'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Partas'),
              )
              .onSelected,
          isNull,
        );
        expect(find.text('No van routes yet.'), findsOneWidget);
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bus'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Bus'));
        await tester.pump();
        expect(find.text('7 routes'), findsOneWidget);
      },
    );

    testWidgets('region filter narrows the list by either endpoint', (
      tester,
    ) async {
      await pumpTab(tester);
      // Only the regions with routes are offered.
      expect(find.widgetWithText(ChoiceChip, 'Ilocos Sur'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Ilocos Norte'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'La Union'), findsNothing);
      // Ilocos Norte touches one route (Laoag Terminal → Vigan).
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Ilocos Norte'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ilocos Norte'));
      await tester.pump();
      expect(find.text('1 of 7'), findsOneWidget);
      expect(
        find.text('Laoag Terminal → Vigan Bus Terminal'),
        findsOneWidget,
      );
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsNothing);
      // Ilocos Sur touches five (the Laoag → Vigan route too, via
      // its Vigan destination).
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Ilocos Sur'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ilocos Sur'));
      await tester.pump();
      expect(find.text('5 of 7'), findsOneWidget);
      expect(
        find.text('Laoag Terminal → Vigan Bus Terminal'),
        findsOneWidget,
      );
      expect(
        find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
        findsNothing,
      );
      // Back to All via the region row's own All chip.
      final regionAll = find.descendant(
        of: find.byKey(const ValueKey('region-filter-row')),
        matching: find.widgetWithText(ChoiceChip, 'All'),
      );
      await tester.ensureVisible(regionAll);
      await tester.pumpAndSettle();
      await tester.tap(regionAll);
      await tester.pump();
      expect(find.text('7 routes'), findsOneWidget);
    });

    testWidgets('fare status filter shows verified / not-set routes', (
      tester,
    ) async {
      await pumpTab(tester);
      final fareAll = find.descendant(
        of: find.byKey(const ValueKey('fare-filter-row')),
        matching: find.widgetWithText(ChoiceChip, 'All'),
      );
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Verified'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Verified'));
      await tester.pump();
      expect(find.text('3 of 7'), findsOneWidget);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
      expect(find.text('Cabugao → San Juan, Ilocos Sur'), findsOneWidget);
      expect(find.text('Sinait → Cabugao'), findsOneWidget);
      expect(
        find.text('Vigan Bus Terminal → San Juan, Ilocos Sur'),
        findsNothing,
      );
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Not set'));
      await tester.pump();
      expect(find.text('4 of 7'), findsOneWidget);
      expect(
        find.text('Vigan Bus Terminal → San Juan, Ilocos Sur'),
        findsOneWidget,
      );
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsNothing);
      // No admin-set route exists in the seeded list.
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Admin-set'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Admin-set'));
      await tester.pump();
      expect(find.text('0 of 7'), findsOneWidget);
      expect(find.text('No admin-set routes yet.'), findsOneWidget);
      await tester.ensureVisible(fareAll);
      await tester.pumpAndSettle();
      await tester.tap(fareAll);
      await tester.pump();
      expect(find.text('7 routes'), findsOneWidget);
    });

    testWidgets('clear filters resets all four categories', (tester) async {
      await pumpTab(tester);
      expect(find.text('Clear filters'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bus'));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Verified'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Verified'));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Ilocos Sur'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ilocos Sur'));
      await tester.pump();
      // Bus + Ilocos Sur + Verified: the three verified routes.
      expect(find.text('3 of 7'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.pump();
      expect(find.text('7 routes'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('narrow phone: all four filter rows fit without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTab(tester);
      // All four rows render on a 390px phone (the preview's pill
      // nav overflowed this width by ~100px).
      for (final label in [
        'Bus operator — Luzon, city & provincial',
        'Region',
        'Fare',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
      }
      // Interact with every row: the rows scroll, they never
      // overflow.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bus'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bus'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Partas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Partas'));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Ilocos Norte'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ilocos Norte'));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Verified'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Verified'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a verified route opens its breakdown sheet', (
      tester,
    ) async {
      await pumpTab(tester);
      await tester.ensureVisible(find.text('Cabugao → Vigan Bus Terminal'));
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

    testWidgets(
      'tapping a no-fare route with a known distance shows its own '
      'estimate, no invented fare',
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
        // F10 (Fares × Map audit, Nov 7, 2026): the estimate now
        // uses the route's OWN stored distance (401.0 km) at the
        // route's own vehicle rate — not the Trip card's leftover
        // distance. The old test pinned the buggy behaviour where
        // the estimate hid because the Trip card was unset.
        expect(find.text('Calculator estimate'), findsOneWidget);
        expect(find.text('Amount to pay'), findsOneWidget);
      },
    );

    testWidgets('swap button exchanges From and To', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.text('Choose a hub'));
      await tester.pump();
      await tester.tap(find.byTooltip('Swap From and To'));
      await tester.pump();
      expect(find.text('Vigan Bus Terminal · Ilocos Sur'), findsOneWidget);
      expect(find.text('31.6 km'), findsOneWidget);
    });

    testWidgets('Find routes appears only when the host wires onViewOnMap', (
      tester,
    ) async {
      var opened = 0;
      await pumpTab(tester, onViewOnMap: () => opened++);
      expect(find.text('Find routes'), findsOneWidget);
      await tester.tap(find.text('Find routes'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('Find routes sets the Fares → Map jump before switching tabs', (
      tester,
    ) async {
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
        await tester.ensureVisible(find.text('Cabugao → Vigan Bus Terminal'));
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
      },
    );

    testWidgets('no-fare route sheet shows Fare not set status + ETA', (
      tester,
    ) async {
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
