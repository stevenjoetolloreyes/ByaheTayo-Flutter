// Tests for the Fares tab restyle (Nov 6, 2026): Popular Routes
// list + filters, fare breakdown arithmetic, and the breakdown
// sheet. The calculator itself is unchanged — these tests pin that
// the breakdown always agrees with computeFare, and that the
// route list never carries a sample fare.
//
// Nov 8, 2026 redesign (Steven: pasted spec, approved with
// resolutions): Vehicle chips → Region dropdown (all 17 regions)
// → Additional Filters (Operator / Province / Sort By), with
// STAGED Apply / Reset. The Fare filter was removed — fare info
// still shows on the cards and sheets, it is just no longer a
// filter. Region now resolves to the ADMINISTRATIVE region via
// the bundled places data (Hub.region is a province for most
// hubs), and Province follows the selected region.
import 'package:estudyantego/features/bus_stops.dart';
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
      // No 'Modern Jeepney' route vehicle type exists in the
      // data — it is a fare-category label, not a route vehicle —
      // so it is never offered as a chip.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Modern Jeepney',
          operator: 'All',
        ),
        isEmpty,
      );
      expect(vehicleFilters, ['All', 'Bus', 'Van', 'Jeepney', 'Tricycle']);
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
      // No creation date on the custom route: none is invented.
      expect(converted.createdAt, isNull);
      final filtered = filterPopularRoutes(
        [...popularRoutes, converted],
        vehicle: 'Bus',
        operator: 'Partas',
      );
      expect(filtered.length, 2);
      expect(filtered, contains(converted));
    });

    test('region filter resolves each endpoint to its administrative region', () {
      // Built-in hubs carry a PROVINCE in Hub.region; the filter
      // resolves it to the administrative region via the bundled
      // places — Ilocos Sur / Ilocos Norte → Ilocos Region.
      expect(
        administrativeRegionOfEndpoint('Cabugao', []),
        'Ilocos Region',
      );
      expect(
        administrativeRegionOfEndpoint('Vigan Bus Terminal', []),
        'Ilocos Region',
      );
      expect(
        administrativeRegionOfEndpoint('Laoag Terminal', []),
        'Ilocos Region',
      );
      // Hubs whose region is already administrative pass through.
      expect(
        administrativeRegionOfEndpoint('Laoag City', []),
        'Ilocos Region',
      );
      expect(
        administrativeRegionOfEndpoint('Baguio City', []),
        'Cordillera Administrative Region',
      );
      // Province → region through the bundled places.
      expect(
        administrativeRegionOfEndpoint('Banaue', []),
        'Cordillera Administrative Region',
      );
      expect(
        administrativeRegionOfEndpoint('Tuguegarao City', []),
        'Cagayan Valley',
      );
      expect(
        administrativeRegionOfEndpoint('Dagupan City', []),
        'Ilocos Region',
      );
      // Terminal names are not places: no region is invented.
      expect(
        administrativeRegionOfEndpoint('Laoag Partas Terminal', []),
        isNull,
      );
      expect(
        administrativeRegionOfEndpoint('Cubao Partas Terminal', []),
        isNull,
      );
      // Documented gaps: these provinces have no bundled place,
      // so their endpoints match only 'All'.
      expect(
        administrativeRegionOfEndpoint('San Fernando City', []),
        isNull,
      );
      expect(administrativeRegionOfEndpoint('Bontoc', []), isNull);
      // All 17 regions are offered, north to south.
      expect(allAdministrativeRegions.length, 17);
      expect(allAdministrativeRegions.first, 'Ilocos Region');
      expect(allAdministrativeRegions.last, 'BARMM');
    });

    test('region filter matches either endpoint', () {
      // Ilocos Region touches five routes (all but the two
      // terminal routes, which have no region).
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Ilocos Region',
        ).length,
        5,
      );
      // No route touches Cagayan Valley or CAR — the terminal
      // names are not the places Tuguegarao City / Baguio City.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Cagayan Valley',
        ),
        isEmpty,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Cordillera Administrative Region',
        ),
        isEmpty,
      );
      final ilocos = filterPopularRoutes(
        popularRoutes,
        vehicle: 'All',
        operator: 'All',
        region: 'Ilocos Region',
      );
      expect(
        ilocos.map((r) => r.from),
        isNot(contains('Laoag Partas Terminal')),
      );
    });

    test('province filter matches either endpoint', () {
      expect(provinceOfRouteEndpoint('Cabugao', []), 'Ilocos Sur');
      expect(
        provinceOfRouteEndpoint('Vigan Bus Terminal', []),
        'Ilocos Sur',
      );
      expect(provinceOfRouteEndpoint('Laoag Terminal', []), 'Ilocos Norte');
      // A hub whose region is already administrative has no
      // province in the data.
      expect(provinceOfRouteEndpoint('Laoag City', []), isNull);
      expect(provinceOfRouteEndpoint('Makati', []), isNull);
      expect(
        provinceOfRouteEndpoint('Laoag Partas Terminal', []),
        isNull,
      );
      // Ilocos Sur touches five routes; Ilocos Norte one.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          province: 'Ilocos Sur',
        ).length,
        5,
      );
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          province: 'Ilocos Norte',
        ).length,
        1,
      );
      // Cagayan has no route: Tuguegarao is a terminal name, not
      // the place Tuguegarao City.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          province: 'Cagayan',
        ),
        isEmpty,
      );
    });

    test('province list follows the selected region', () {
      // Ilocos Region: the bundled provinces, alphabetical.
      expect(
        provincesInRegion('Ilocos Region'),
        ['Ilocos Norte', 'Ilocos Sur', 'Pangasinan'],
      );
      // 'La Union' has no bundled place, so it is never offered.
      expect(
        provincesInRegion('Ilocos Region'),
        isNot(contains('La Union')),
      );
      // Cagayan Valley: the bundled provinces only.
      expect(
        provincesInRegion('Cagayan Valley'),
        ['Batanes', 'Cagayan', 'Isabela', 'Nueva Vizcaya'],
      );
      // All Regions → every province in the bundled data;
      // 'Metro Manila' is a region, not a province, so it never
      // appears.
      final all = provincesInRegion('All');
      expect(all, contains('Ilocos Sur'));
      expect(all, contains('Cebu'));
      expect(all, contains('Cagayan'));
      expect(all, contains('Basilan'));
      expect(all, isNot(contains('Metro Manila')));
      expect(all, isNot(contains('La Union')));
      expect(all, isNot(contains('Mountain Province')));
      // The list is sorted.
      expect(all, equals([...all]..sort()));
    });

    test('route operators come from the route data', () {
      // First-seen order, Bus routes only, no operator invented:
      // the five hub routes carry no operator.
      expect(routeOperators(popularRoutes), ['Partas', 'GMW Trans']);
      expect(routeOperators([]), isEmpty);
    });

    test('region display labels carry the spec prefixes', () {
      expect(regionDisplayLabel('All'), 'All Regions');
      expect(
        regionDisplayLabel('Ilocos Region'),
        'Region I – Ilocos Region',
      );
      expect(
        regionDisplayLabel('Cagayan Valley'),
        'Region II – Cagayan Valley',
      );
      expect(
        regionDisplayLabel('CALABARZON'),
        'Region IV-A – CALABARZON',
      );
      expect(regionDisplayLabel('MIMAROPA'), 'MIMAROPA – Region IV-B');
      expect(
        regionDisplayLabel('Metro Manila'),
        'NCR – National Capital Region',
      );
      expect(
        regionDisplayLabel('Cordillera Administrative Region'),
        'CAR – Cordillera Administrative Region',
      );
      expect(
        regionDisplayLabel('BARMM'),
        'BARMM – Bangsamoro Autonomous Region',
      );
      // Every region has a label, and the label differs from the
      // value (the value stays the plain region name for matching).
      for (final region in allAdministrativeRegions) {
        expect(regionDisplayLabel(region), isNot(region));
      }
    });

    test('filters combine across categories', () {
      // Bus + Ilocos Region: the five regional routes.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'All',
          region: 'Ilocos Region',
        ).length,
        5,
      );
      // Ilocos Region + Ilocos Norte: the Laoag Terminal route.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Ilocos Region',
          province: 'Ilocos Norte',
        ).length,
        1,
      );
      // Ilocos Region + Ilocos Sur: five — every Ilocos Region
      // route touches Ilocos Sur.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Ilocos Region',
          province: 'Ilocos Sur',
        ).length,
        5,
      );
      // Partas + Ilocos Region: the Partas route has no region.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'Bus',
          operator: 'Partas',
          region: 'Ilocos Region',
        ),
        isEmpty,
      );
      // Cagayan Valley + Cagayan: no route touches either.
      expect(
        filterPopularRoutes(
          popularRoutes,
          vehicle: 'All',
          operator: 'All',
          region: 'Cagayan Valley',
          province: 'Cagayan',
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

  group('sortPopularRoutes', () {
    test('Most Popular keeps the list order', () {
      expect(
        sortPopularRoutes(popularRoutes, 'Most Popular'),
        orderedEquals(popularRoutes),
      );
    });

    test('Lowest Fare is fare ascending, no-fare last', () {
      final sorted = sortPopularRoutes(popularRoutes, 'Lowest Fare');
      expect(
        sorted.map((r) => r.fare).toList(),
        [20, 20, 60, null, null, null, null],
      );
      expect(sorted[0].from, 'Cabugao');
      expect(sorted[0].to, 'San Juan, Ilocos Sur');
      expect(sorted[1].from, 'Sinait');
      expect(sorted[1].to, 'Cabugao');
      expect(sorted[2].from, 'Cabugao');
      expect(sorted[2].to, 'Vigan Bus Terminal');
      // No-fare routes keep their relative order.
      expect(
        sorted.sublist(3).map((r) => r.from).toList(),
        [
          'Vigan Bus Terminal',
          'Laoag Terminal',
          'Laoag Partas Terminal',
          'Bantay GMW Terminal',
        ],
      );
    });

    test('Newest Routes puts admin-added routes first, seeded keep order', () {
      final older = popularRouteFromCustomRoute(
        CustomRoute(
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
          operator: 'Partas',
          vehicle: 'Bus',
          fare: 60,
          createdAt: DateTime(2026, 11, 1),
        ),
      );
      final newer = popularRouteFromCustomRoute(
        CustomRoute(
          from: 'Sinait',
          to: 'Cabugao',
          operator: 'Partas',
          vehicle: 'Bus',
          fare: 20,
          createdAt: DateTime(2026, 11, 8),
        ),
      );
      // The creation date survives the conversion — it is the
      // CustomRoute's own timestamp, never invented here.
      expect(newer.createdAt, DateTime(2026, 11, 8));
      expect(older.createdAt, DateTime(2026, 11, 1));
      final sorted = sortPopularRoutes(
        [...popularRoutes, older, newer],
        'Newest Routes',
      );
      expect(sorted[0], newer);
      expect(sorted[1], older);
      expect(sorted.sublist(2), orderedEquals(popularRoutes));
    });

    test('Newest Routes with no timestamps keeps the list order', () {
      // The seeded routes have no creation date, so none is
      // invented and their order is unchanged.
      expect(
        sortPopularRoutes(popularRoutes, 'Newest Routes'),
        orderedEquals(popularRoutes),
      );
    });

    test('unknown sort keeps the list order', () {
      expect(
        sortPopularRoutes(popularRoutes, 'Something else'),
        orderedEquals(popularRoutes),
      );
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

    /// Opens the dropdown under [fieldKey] without picking.
    Future<void> openDropdown(
      WidgetTester tester,
      ValueKey<String> fieldKey,
    ) async {
      final field = find.descendant(
        of: find.byKey(fieldKey),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
    }

    /// Scrolls the open dropdown menu until the item labelled
    /// [itemLabel] is built. The menu lazily builds its items
    /// (only the visible window exists), so a far-down item —
    /// 'Cebu' in an 80-province list, 'BARMM' last of 17
    /// regions — is not in the tree until the menu scrolls. The
    /// menu can also open scrolled to the bottom (when its field
    /// sits at the screen's top edge), so this tries down first,
    /// then up — the item is found in one of the directions.
    Future<void> scrollMenuToItem(
      WidgetTester tester,
      String itemLabel,
    ) async {
      final item = find.widgetWithText(
        DropdownMenuItem<String>,
        itemLabel,
      );
      for (var i = 0; i < 40 && item.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byType(Scrollable).last,
          const Offset(0, -400),
        );
        await tester.pump();
      }
      for (var i = 0; i < 40 && item.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byType(Scrollable).last,
          const Offset(0, 400),
        );
        await tester.pump();
      }
    }

    /// Opens the dropdown under [fieldKey] and picks the menu item
    /// labelled [itemLabel], scrolling the menu first when the
    /// item is below the visible window.
    Future<void> pickDropdownItem(
      WidgetTester tester,
      ValueKey<String> fieldKey,
      String itemLabel,
    ) async {
      await openDropdown(tester, fieldKey);
      await scrollMenuToItem(tester, itemLabel);
      final item = find.widgetWithText(
        DropdownMenuItem<String>,
        itemLabel,
      );
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    /// Closes an open dropdown menu by tapping the scrim.
    Future<void> closeDropdownMenu(WidgetTester tester) async {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    /// Taps [finder] after scrolling it into view — the Fares tab
    /// scrolls, so a chip or button below the fold would
    /// otherwise miss (the tap lands outside the viewport).
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump();
    }

    /// Expands the Additional Filters section.
    Future<void> expandAdditionalFilters(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Additional Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Additional Filters'));
      await tester.pumpAndSettle();
    }

    /// The dropdown under [fieldKey], as a widget, for asserting
    /// its items and current value.
    DropdownButtonFormField<String> dropdown(
      WidgetTester tester,
      ValueKey<String> fieldKey,
    ) {
      return tester.widget<DropdownButtonFormField<String>>(
        find.descendant(
          of: find.byKey(fieldKey),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
    }

    testWidgets('hero, chips, dropdowns, and Popular Routes render', (
      tester,
    ) async {
      await pumpTab(tester);
      expect(find.text('Know your fare before you go'), findsOneWidget);
      expect(find.text('Popular Routes'), findsOneWidget);
      expect(find.text('7 routes'), findsOneWidget);
      // Vehicle chips only: the types with routes. No empty
      // Motorcycle / Car / Train / Modern Jeepney chips.
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      for (final label in ['Bus', 'Van', 'Jeepney', 'Tricycle']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      for (final label in ['Motorcycle', 'Car', 'Train', 'Modern Jeepney']) {
        expect(find.widgetWithText(ChoiceChip, label), findsNothing);
      }
      // Region is a dropdown (All Regions), not a chip row.
      expect(find.text('Region'), findsOneWidget);
      expect(find.text('All Regions'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Ilocos Sur'), findsNothing);
      // The Fare filter is gone — fare info still shows on the
      // cards, it is just no longer a filter.
      expect(find.text('Fare'), findsNothing);
      for (final label in ['Verified', 'Admin-set', 'Not set']) {
        expect(find.widgetWithText(ChoiceChip, label), findsNothing);
      }
      // Additional Filters is collapsed by default; the
      // operator / province / sort dropdowns are not in the tree.
      expect(find.text('Additional Filters'), findsOneWidget);
      expect(find.text('Operator'), findsNothing);
      expect(find.text('Province'), findsNothing);
      expect(find.text('Sort By'), findsNothing);
      // Staged Apply / Reset replace Clear filters.
      expect(
        find.widgetWithText(FilledButton, 'Apply Filters'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Reset'), findsOneWidget);
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
      'Additional Filters is collapsed by default; expanding shows '
      'Operator, Province, Sort By',
      (tester) async {
        await pumpTab(tester);
        expect(find.text('Operator'), findsNothing);
        await expandAdditionalFilters(tester);
        expect(find.text('Operator'), findsOneWidget);
        expect(find.text('Province'), findsOneWidget);
        expect(find.text('Sort By'), findsOneWidget);
        // Operator options come from the route data, not a
        // hardcoded list: Partas and GMW Trans only. The
        // operator dropdown only enables once Bus is picked
        // (operators apply to Bus routes).
        await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Bus'));
        await openDropdown(
          tester,
          const ValueKey('operator-filter-dropdown'),
        );
        for (final label in ['Partas', 'GMW Trans']) {
          expect(
            find.widgetWithText(DropdownMenuItem<String>, label),
            findsOneWidget,
          );
        }
        await closeDropdownMenu(tester);
        // Province with All Regions: every bundled province.
        // The menu lazily builds its items, so scroll to each
        // one before asserting it is offered.
        await openDropdown(
          tester,
          const ValueKey('province-filter-dropdown'),
        );
        await scrollMenuToItem(tester, 'Ilocos Sur');
        expect(
          find.widgetWithText(DropdownMenuItem<String>, 'Ilocos Sur'),
          findsOneWidget,
        );
        await scrollMenuToItem(tester, 'Cebu');
        expect(
          find.widgetWithText(DropdownMenuItem<String>, 'Cebu'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(DropdownMenuItem<String>, 'Metro Manila'),
          findsNothing,
        );
        await closeDropdownMenu(tester);
        // Sort By offers all three orders.
        await openDropdown(
          tester,
          const ValueKey('sort-filter-dropdown'),
        );
        for (final label in ['Lowest Fare', 'Newest Routes']) {
          expect(
            find.widgetWithText(DropdownMenuItem<String>, label),
            findsOneWidget,
          );
        }
        // 'Most Popular' appears twice: the button's current
        // value plus the menu item (every dropdown button
        // renders its selected value as a DropdownMenuItem).
        expect(
          find.widgetWithText(DropdownMenuItem<String>, 'Most Popular'),
          findsWidgets,
        );
        await closeDropdownMenu(tester);
        expect(
          dropdown(
            tester,
            const ValueKey('sort-filter-dropdown'),
          ).initialValue,
          'Most Popular',
        );
        // Collapse again: the dropdowns leave the tree.
        await tapVisible(tester, find.text('Additional Filters'));
        expect(find.text('Operator'), findsNothing);
      },
    );

    testWidgets(
      'region dropdown lists all 17 regions; selecting stages, '
      'Apply updates',
      (tester) async {
        await pumpTab(tester);
        // The menu lists all 17 regions: the first is visible
        // on open, the last only after scrolling (the menu
        // lazily builds its items).
        await openDropdown(
          tester,
          const ValueKey('region-filter-dropdown'),
        );
        expect(find.text('Region I – Ilocos Region'), findsOneWidget);
        await scrollMenuToItem(
          tester,
          'BARMM – Bangsamoro Autonomous Region',
        );
        expect(
          find.text('BARMM – Bangsamoro Autonomous Region'),
          findsOneWidget,
        );
        // Scroll back to the top of the same open menu and pick
        // the first region.
        await scrollMenuToItem(tester, 'Region I – Ilocos Region');
        await tester.tap(
          find.widgetWithText(
            DropdownMenuItem<String>,
            'Region I – Ilocos Region',
          ),
        );
        await tester.pumpAndSettle();
        // Staged, not applied: the list still shows all 7.
        expect(find.text('7 routes'), findsOneWidget);
        expect(find.text('Region I – Ilocos Region'), findsOneWidget);
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Apply Filters'),
        );
        expect(find.text('5 of 7'), findsOneWidget);
        expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
        expect(
          find.text('Laoag Terminal → Vigan Bus Terminal'),
          findsOneWidget,
        );
        expect(
          find.text('Laoag Partas Terminal → Cubao Partas Terminal'),
          findsNothing,
        );
        expect(
          find.text('Bantay GMW Terminal → Tuguegarao GMW Terminal'),
          findsNothing,
        );
      },
    );

    testWidgets('province list follows the selected region', (
      tester,
    ) async {
      await pumpTab(tester);
      // With All Regions, the province menu offers every
      // province — including one far from Ilocos.
      await expandAdditionalFilters(tester);
      await pickDropdownItem(
        tester,
        const ValueKey('province-filter-dropdown'),
        'Cebu',
      );
      // Staged, not applied: the list still shows all 7.
      expect(find.text('7 routes'), findsOneWidget);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      // No route touches Cebu.
      expect(find.text('0 of 7'), findsOneWidget);
      expect(find.text('No routes in Cebu yet.'), findsOneWidget);
      // Now narrow the region to Ilocos Region: the province
      // resets to All, and the menu offers only its provinces.
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reset'));
      expect(find.text('7 routes'), findsOneWidget);
      await pickDropdownItem(
        tester,
        const ValueKey('region-filter-dropdown'),
        'Region I – Ilocos Region',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('5 of 7'), findsOneWidget);
      await openDropdown(
        tester,
        const ValueKey('province-filter-dropdown'),
      );
      for (final province in ['Ilocos Norte', 'Ilocos Sur', 'Pangasinan']) {
        expect(
          find.widgetWithText(DropdownMenuItem<String>, province),
          findsOneWidget,
        );
      }
      expect(
        find.widgetWithText(DropdownMenuItem<String>, 'Cebu'),
        findsNothing,
      );
      await tester.tap(
        find.widgetWithText(DropdownMenuItem<String>, 'Ilocos Norte'),
      );
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('1 of 7'), findsOneWidget);
      expect(
        find.text('Laoag Terminal → Vigan Bus Terminal'),
        findsOneWidget,
      );
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsNothing);
    });

    testWidgets(
      'operator dropdown is data-driven; a non-Bus vehicle disables '
      'it and resets it to All',
      (tester) async {
        await pumpTab(tester);
        await expandAdditionalFilters(tester);
        // The operator dropdown only enables once Bus is picked
        // (operators apply to Bus routes).
        await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Bus'));
        expect(
          dropdown(
            tester,
            const ValueKey('operator-filter-dropdown'),
          ).onChanged,
          isNotNull,
        );
        await pickDropdownItem(
          tester,
          const ValueKey('operator-filter-dropdown'),
          'Partas',
        );
        expect(
          dropdown(
            tester,
            const ValueKey('operator-filter-dropdown'),
          ).initialValue,
          'Partas',
        );
        // Staged, not applied: the list still shows all 7.
        expect(find.text('7 routes'), findsOneWidget);
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Apply Filters'),
        );
        expect(find.text('1 of 7'), findsOneWidget);
        expect(
          find.text('Laoag Partas Terminal → Cubao Partas Terminal'),
          findsOneWidget,
        );
        // Switching vehicle resets the operator to All and
        // DISABLES the dropdown (it stays visible — operators
        // only apply to Bus routes).
        await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Van'));
        expect(
          dropdown(
            tester,
            const ValueKey('operator-filter-dropdown'),
          ).initialValue,
          'All',
        );
        expect(
          dropdown(
            tester,
            const ValueKey('operator-filter-dropdown'),
          ).onChanged,
          isNull,
        );
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Apply Filters'),
        );
        expect(find.text('No van routes yet.'), findsOneWidget);
        await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Bus'));
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Apply Filters'),
        );
        expect(find.text('7 routes'), findsOneWidget);
      },
    );

    testWidgets('sort by Lowest Fare orders cheapest first, no-fare last', (
      tester,
    ) async {
      await pumpTab(tester);
      await expandAdditionalFilters(tester);
      await pickDropdownItem(
        tester,
        const ValueKey('sort-filter-dropdown'),
        'Lowest Fare',
      );
      // Staging a sort marks the section Active.
      expect(find.text('Active'), findsOneWidget);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('7 routes'), findsOneWidget);
      // The ₱20 routes sit above the ₱60 route, and the ₱60
      // route sits above the no-fare routes.
      final first20 = tester
          .getTopLeft(find.text('Cabugao → San Juan, Ilocos Sur'))
          .dy;
      final second20 = tester
          .getTopLeft(find.text('Sinait → Cabugao'))
          .dy;
      final sixty = tester
          .getTopLeft(find.text('Cabugao → Vigan Bus Terminal'))
          .dy;
      final noFare = tester
          .getTopLeft(find.text('Vigan Bus Terminal → San Juan, Ilocos Sur'))
          .dy;
      expect(first20, lessThan(sixty));
      expect(second20, lessThan(sixty));
      expect(sixty, lessThan(noFare));
      // Newest Routes with seeded-only data keeps the list order
      // (the built-ins have no creation date).
      await pickDropdownItem(
        tester,
        const ValueKey('sort-filter-dropdown'),
        'Newest Routes',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      final first = tester
          .getTopLeft(find.text('Cabugao → Vigan Bus Terminal'))
          .dy;
      final second = tester
          .getTopLeft(find.text('Cabugao → San Juan, Ilocos Sur'))
          .dy;
      expect(first, lessThan(second));
    });

    testWidgets('Apply stages then updates; Reset restores defaults', (
      tester,
    ) async {
      await pumpTab(tester);
      // Nothing staged: Apply and Reset are both disabled.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Filters'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Reset'),
            )
            .onPressed,
        isNull,
      );
      // Tapping a chip only STAGES it — the list does not change.
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Van'));
      expect(find.text('7 routes'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply Filters'),
            )
            .onPressed,
        isNotNull,
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('0 of 7'), findsOneWidget);
      expect(find.text('No van routes yet.'), findsOneWidget);
      // Reset restores everything: the list, the vehicle chip,
      // and the region dropdown.
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reset'));
      expect(find.text('7 routes'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'))
            .selected,
        isTrue,
      );
      expect(find.text('All Regions'), findsOneWidget);
      await expandAdditionalFilters(tester);
      expect(
        dropdown(
          tester,
          const ValueKey('sort-filter-dropdown'),
        ).initialValue,
        'Most Popular',
      );
      expect(find.text('Active'), findsNothing);
    });

    testWidgets('narrow phone: filters fit without overflow at 390px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTab(tester);
      expect(find.text('Popular Routes'), findsOneWidget);
      expect(find.text('7 routes'), findsOneWidget);
      // Stage + apply a vehicle filter: the short '0 of 7'
      // count label never overflows the header Row (the f1cf15c
      // lesson — the old 'X of Y routes' label overflowed 39px).
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Van'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('0 of 7'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Reset'));
      // Region dropdown + Apply at 390px.
      await pickDropdownItem(
        tester,
        const ValueKey('region-filter-dropdown'),
        'Region I – Ilocos Region',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('5 of 7'), findsOneWidget);
      // Expand Additional Filters and apply a sort at 390px.
      await expandAdditionalFilters(tester);
      await pickDropdownItem(
        tester,
        const ValueKey('sort-filter-dropdown'),
        'Lowest Fare',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Filters'),
      );
      expect(find.text('5 of 7'), findsOneWidget);
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
