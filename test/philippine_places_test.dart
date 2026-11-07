// Bundled Philippines places (Nov 7, 2026 — Steven: the Fares
// From/To list only had the 16 built-in hubs, "ang liit").
//
// The bundled list (major cities + provincial capitals + major
// municipalities, grouped by region) is built into the app so the
// pickers work offline. These tests pin the data contract:
// every coordinate is real (OpenStreetMap via Nominatim, one
// lookup per place at build time) and verifiable, names are
// unique, the 16 hubs keep their indices, and the pickers stay
// searchable + grouped by region.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/philippine_places.dart';
import 'package:estudyantego/features/place_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('philippinePlaces data', () {
    test('164 places, all with a name, a province, and real PH coordinates', () {
      expect(philippinePlaces.length, 164);
      for (final place in philippinePlaces) {
        expect(place.name, isNotEmpty, reason: 'unnamed place');
        expect(place.region, isNotEmpty, reason: '${place.name} has no province');
        expect(place.lat, greaterThanOrEqualTo(4.5));
        expect(place.lat, lessThanOrEqualTo(21.5));
        expect(place.lng, greaterThanOrEqualTo(116.0));
        expect(place.lng, lessThanOrEqualTo(127.0));
      }
    });

    test('names are unique and never collide with a built-in hub', () {
      final names = philippinePlaces.map((p) => p.name).toList();
      expect(names.toSet().length, names.length);
      for (final name in names) {
        expect(hubs.any((h) => h.name == name), isFalse, reason: name);
      }
    });

    test('every place has a real region in the region order — none in Other places', () {
      final regions = <String>{};
      for (final place in philippinePlaces) {
        final region = philippineRegionOf(place);
        expect(region, isNot('Other places'), reason: place.name);
        expect(philippineRegionOrder, contains(region), reason: place.name);
        regions.add(region);
      }
      // All 17 regions are represented.
      expect(regions.length, philippineRegionOrder.length);
    });

    test('ordered by region (north to south), alphabetical within each region', () {
      String? currentRegion;
      String? previousName;
      for (final place in philippinePlaces) {
        final region = philippineRegionOf(place);
        final regionIndex = philippineRegionOrder.indexOf(region);
        if (region != currentRegion) {
          expect(
            regionIndex,
            greaterThan(currentRegion == null
                ? -1
                : philippineRegionOrder.indexOf(currentRegion)),
            reason: 'region $region out of order',
          );
          currentRegion = region;
          previousName = null;
        }
        if (previousName != null) {
          expect(
            place.name.compareTo(previousName),
            greaterThan(0),
            reason: '${place.name} after $previousName in $region',
          );
        }
        previousName = place.name;
      }
    });

    test('spot-checks: well-known city centres land where they should', () {
      Hub at(String name) =>
          philippinePlaces.firstWhere((p) => p.name == name);
      final manila = at('Manila');
      expect(manila.lat, inInclusiveRange(14.55, 14.65));
      expect(manila.lng, inInclusiveRange(120.95, 121.02));
      final cebu = at('Cebu City');
      expect(cebu.lat, inInclusiveRange(10.25, 10.35));
      expect(cebu.lng, inInclusiveRange(123.85, 123.95));
      final davao = at('Davao City');
      expect(davao.lat, inInclusiveRange(7.05, 7.10));
      expect(davao.lng, inInclusiveRange(125.55, 125.65));
      final zamboanga = at('Zamboanga City');
      expect(zamboanga.lat, inInclusiveRange(6.85, 6.95));
      expect(zamboanga.lng, inInclusiveRange(122.03, 122.12));
    });

    test('region counts match the build record', () {
      final counts = <String, int>{};
      for (final place in philippinePlaces) {
        final region = philippineRegionOf(place);
        counts[region] = (counts[region] ?? 0) + 1;
      }
      expect(counts['Metro Manila'], 17);
      expect(counts['Central Luzon'], 16);
      expect(counts['CALABARZON'], 19);
      expect(counts['Ilocos Region'], 12);
    });
  });

  group('allHubs / resolveHub with bundled places', () {
    test('16 hubs keep their indices; bundled places append after the stops', () {
      final merged = allHubs([]);
      expect(merged.length, 16 + philippinePlaces.length);
      expect(merged[2].name, 'Cabugao');
      expect(merged[14].name, 'Vigan Bus Terminal');
      expect(merged[16].name, philippinePlaces.first.name);
    });

    test('a bundled place resolves by name, with its real coordinates', () {
      final cebu = resolveHub('Cebu City', []);
      expect(cebu, isNotNull);
      expect(cebu!.region, 'Cebu');
      expect(cebu.lat, inInclusiveRange(10.25, 10.35));
      final manila = resolveHub('Manila', []);
      expect(manila, isNotNull);
      expect(manila!.lat, inInclusiveRange(14.55, 14.65));
    });

    test('hubs win on a name clash; the disambiguated name resolves', () {
      // 'San Fernando City' is the La Union hub — the Pampanga
      // city is stored with its province in parentheses.
      final hub = resolveHub('San Fernando City', []);
      expect(hub, isNotNull);
      expect(hub!.lat, 16.59756);
      expect(hub.lng, 120.30610);
      final pampanga = resolveHub('San Fernando City (Pampanga)', []);
      expect(pampanga, isNotNull);
      expect(pampanga!.region, 'Pampanga');
    });

    test('unknown names stay null; hubByName resolves bundled places too', () {
      expect(resolveHub('No Such Place', []), isNull);
      expect(hubByName('Davao City'), isNotNull);
      expect(hubByName('No Such Place'), isNull);
    });
  });

  group('filterPlaces / placeSectionName', () {
    late List<Hub> merged;
    setUp(() => merged = allHubs([]));

    test('empty query returns the whole merged list', () {
      expect(filterPlaces(merged, ''), merged);
      expect(filterPlaces(merged, '   '), merged);
    });

    test('name match: cebu finds the Cebu places, not Cabugao', () {
      final names =
          filterPlaces(merged, 'cebu').map((h) => h.name).toList();
      expect(names, contains('Cebu City'));
      expect(names, contains('Mandaue'));
      expect(names, isNot(contains('Cabugao')));
    });

    test('province match: Pampanga finds its cities', () {
      final names =
          filterPlaces(merged, 'Pampanga').map((h) => h.name).toList();
      expect(names, contains('Angeles City'));
      expect(names, contains('San Fernando City (Pampanga)'));
      expect(names, contains('Mabalacat'));
      expect(names, isNot(contains('Manila')));
    });

    test('region match: Central Luzon finds its places only', () {
      final found = filterPlaces(merged, 'Central Luzon');
      expect(found.length, 16);
      expect(found.map((h) => h.name), contains('Angeles City'));
      expect(found.map((h) => h.name), isNot(contains('Manila')));
    });

    test('no match returns an empty list', () {
      expect(filterPlaces(merged, 'zzz-no-such-place'), isEmpty);
    });

    test('sections: Hubs first, then the regions in order', () {
      expect(placeSectionName(merged, 0, 0), 'Hubs');
      expect(placeSectionName(merged, 15, 0), 'Hubs');
      expect(placeSectionName(merged, 16, 0), 'Ilocos Region');
      expect(placeSectionLabel('Central Luzon', 16), 'Central Luzon · 16');
    });

    test('sections: an admin stop sits between the hubs and the regions', () {
      final withStop = allHubs([
        BusStop(name: 'Cabugao Public Market', region: 'Ilocos Sur', lat: 17.79, lng: 120.45),
      ]);
      expect(placeSectionName(withStop, 16, 1), 'My bus stops');
      expect(placeSectionName(withStop, 17, 1), 'Ilocos Region');
    });
  });

  group('route math for bundled places', () {
    test('Manila to Quezon City is a short hop, and the LTFRB formula still prices it', () {
      final manila = resolveHub('Manila', [])!;
      final quezon = resolveHub('Quezon City', [])!;
      final direct = haversineKm(manila.lat, manila.lng, quezon.lat, quezon.lng);
      expect(direct, greaterThan(5));
      expect(direct, lessThan(15));
      final roadKm = direct * 1.22;
      final rate = fareRates.firstWhere((r) => r.id == 'prov-ordinary');
      final fare = computeFare(rate, roadKm, false);
      expect(fare.regular, greaterThan(0));
    });
  });

  group('place picker sheet', () {
    testWidgets('search filters and tapping a row pops the Hub', (tester) async {
      Hub? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  picked = await showPlacePicker(
                    context: context,
                    places: allHubs([]),
                    stopsCount: 0,
                    title: 'From',
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(find.text('From'), findsOneWidget);
      expect(find.text('Hubs · 16'), findsOneWidget);
      await tester.enterText(
        find.byType(CupertinoTextField),
        'cebu',
      );
      await tester.pump();
      expect(find.text('Cebu City'), findsOneWidget);
      expect(find.text('Cabugao'), findsNothing);
      await tester.tap(find.text('Cebu City'));
      await tester.pumpAndSettle();
      expect(picked, isNotNull);
      expect(picked!.name, 'Cebu City');
      expect(picked!.region, 'Cebu');
    });

    testWidgets('multi-picker keeps tap order and Done pops the names', (tester) async {
      List<String>? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  picked = await showPlaceMultiPicker(
                    context: context,
                    places: allHubs([]),
                    stopsCount: 0,
                    selected: const [],
                    title: 'Via stops',
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'cebu');
      await tester.pump();
      // The filtered list is a ListView.builder — scroll each row
      // into view before tapping it. The scrollable must be named
      // explicitly (the sheet also holds the search field's own
      // Scrollable, so the default find.byType(Scrollable) matches
      // several), and it must be the Scrollable itself — ListView
      // is a widget that builds one, not a Scrollable.
      final listScrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Mandaue'),
        100,
        scrollable: listScrollable,
      );
      // scrollUntilVisible stops as soon as the row is built, even
      // if only its edge shows — make it fully visible before
      // tapping, or the tap misses.
      await tester.ensureVisible(find.text('Mandaue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mandaue'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Cebu City'),
        -100,
        scrollable: listScrollable,
      );
      await tester.ensureVisible(find.text('Cebu City'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cebu City'));
      await tester.pump();
      expect(find.text('Done · 2'), findsOneWidget);
      await tester.tap(find.text('Done · 2'));
      await tester.pumpAndSettle();
      expect(picked, ['Mandaue', 'Cebu City']);
    });

    testWidgets('Fares Trip card From field opens the picker and swaps the place', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FaresTab())),
      );
      await tester.tap(find.text('Choose a hub'));
      await tester.pump();
      expect(find.text('Cabugao · Ilocos Sur'), findsOneWidget);
      expect(find.text('31.6 km'), findsOneWidget);
      await tester.tap(find.text('Cabugao · Ilocos Sur'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'davao');
      await tester.pump();
      await tester.tap(find.text('Davao City'));
      await tester.pumpAndSettle();
      expect(find.text('Davao City · Davao del Sur'), findsOneWidget);
      expect(find.text('31.6 km'), findsNothing);
    });
  });
}
