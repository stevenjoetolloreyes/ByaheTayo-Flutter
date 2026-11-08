// Tests for the shared OSRM geometry cache + the Fares-side
// consistency helpers (Fares × Map audit, Nov 7, 2026): the cache
// Fares and Map share so both tabs show the same distance/ETA/
// stops for the same route (F1/F2), the leg-summed custom-route
// distance (F3), the vehicle-matched LTFRB rate (F5), and the
// route's own distance in the breakdown (F10). No network is
// touched here: the cache-hit path is tested; the cache-miss
// path (a live OSRM fetch) is not.
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('RouteGeometryCache', () {
    test('put/get/clear round-trips', () {
      final cache = RouteGeometryCache();
      const geometry = RouteGeometry(
        points: [
          LatLng(17.78916, 120.45838),
          LatLng(17.56641, 120.38590),
        ],
        distanceKm: 27.5,
        durationSec: 2220,
      );
      expect(cache.get('Cabugao|Vigan Bus Terminal'), isNull);
      cache.put('Cabugao|Vigan Bus Terminal', geometry);
      expect(cache.get('Cabugao|Vigan Bus Terminal'), same(geometry));
      cache.clear();
      expect(cache.get('Cabugao|Vigan Bus Terminal'), isNull);
    });
  });

  group('routeGeometryKey', () {
    test('same inputs give the same key', () {
      expect(
        routeGeometryKey(
          oLat: 17.78916,
          oLng: 120.45838,
          dest: hubByName('Vigan Bus Terminal', [])!,
        ),
        routeGeometryKey(
          oLat: 17.78916,
          oLng: 120.45838,
          dest: hubByName('Vigan Bus Terminal', [])!,
        ),
      );
    });

    test('different destination or via points give different keys', () {
      final base = routeGeometryKey(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('Vigan Bus Terminal', [])!,
      );
      expect(
        routeGeometryKey(
          oLat: 17.78916,
          oLng: 120.45838,
          dest: hubByName('San Juan, Ilocos Sur', [])!,
        ),
        isNot(base),
      );
      expect(
        routeGeometryKey(
          oLat: 17.78916,
          oLng: 120.45838,
          dest: hubByName('Vigan Bus Terminal', [])!,
          via: const [LatLng(17.73979, 120.45719)],
        ),
        isNot(base),
      );
    });

    test('Vigan destination: empty via counts the same as the Quezon '
        'Ave waypoint', () {
      // The Quezon Ave → Jose Singson via-point applies to every
      // Vigan Bus Terminal route with no custom direction, so a
      // geometry cached with it must match a lookup with no via
      // points at all — otherwise Fares and Map would cache the
      // same road under two different keys.
      final noVia = routeGeometryKey(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('Vigan Bus Terminal', [])!,
      );
      final quezon = routeGeometryKey(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('Vigan Bus Terminal', [])!,
        via: const [LatLng(17.576831, 120.387462)],
      );
      expect(quezon, noVia);
    });

    test('a non-terminal destination does not get the Quezon waypoint',
        () {
      final noVia = routeGeometryKey(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('San Juan, Ilocos Sur', [])!,
      );
      final quezon = routeGeometryKey(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('San Juan, Ilocos Sur', [])!,
        via: const [LatLng(17.576831, 120.387462)],
      );
      expect(quezon, isNot(noVia));
    });
  });

  group('fetchRouteGeometry', () {
    test('returns the cached geometry without a network fetch', () async {
      routeGeometryCache.clear();
      const geometry = RouteGeometry(
        points: [LatLng(17.78916, 120.45838)],
        distanceKm: 27.5,
        durationSec: 2220,
      );
      final key = routeGeometryKey(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('Vigan Bus Terminal', [])!,
      );
      routeGeometryCache.put(key, geometry);
      final fetched = await fetchRouteGeometry(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: hubByName('Vigan Bus Terminal', [])!,
      );
      expect(fetched, same(geometry));
      routeGeometryCache.clear();
    });
  });

  group('hubPairStops with live geometry (F1)', () {
    test('adds the on-the-way hub the no-geometry list misses', () {
      final noGeometry = hubPairStops(
        from: hubByName('Cabugao', [])!,
        to: hubByName('Vigan Bus Terminal', [])!,
        totalKm: 31.6,
      );
      expect(
        noGeometry.map((s) => s.name).toList(),
        ['Cabugao', 'Vigan Bus Terminal'],
      );
      // A live OSRM line through San Juan (the real road passes
      // 0.08 km from it): the Fares sheet and the Map sheet now
      // show the same stops, in road order. Other bundled places
      // near the line may also appear — only the relative order
      // of the three known stops is pinned.
      final withGeometry = hubPairStops(
        from: hubByName('Cabugao', [])!,
        to: hubByName('Vigan Bus Terminal', [])!,
        totalKm: 27.5,
        roadPoints: const [
          LatLng(17.78916, 120.45838),
          LatLng(17.73979, 120.45719),
          LatLng(17.56641, 120.38590),
        ],
      );
      expect(
        withGeometry.map((s) => s.name).toList(),
        containsAllInOrder(
          ['Cabugao', 'San Juan, Ilocos Sur', 'Vigan Bus Terminal'],
        ),
      );
    });
  });

  group('popularRouteRoadKm with a custom route (F3)', () {
    test('uses the leg-summed distance, not the direct endpoint '
        'distance', () {
      const custom = CustomRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        operator: 'Partas',
        vehicle: 'Bus',
        fare: 60,
        viaHubs: ['San Juan, Ilocos Sur'],
      );
      final route = popularRouteFromCustomRoute(custom);
      final legSummed =
          popularRouteRoadKm(route, const [], customRoute: custom);
      expect(legSummed, customRouteRoadKm(custom, const []));
      // Direct endpoint-to-endpoint ignores the via stop.
      final direct =
          haversineKm(17.78916, 120.45838, 17.56641, 120.38590) * 1.22;
      expect(legSummed, isNot(closeTo(direct, 0.01)));
    });
  });

  group('popularRouteRoadKm uses the route\'s own distance (F10)', () {
    test('GMW route returns its stored 401.0 km', () {
      const gmw = PopularRoute(
        from: 'Bantay GMW Terminal',
        to: 'Tuguegarao GMW Terminal',
        operator: 'GMW Trans',
        vehicle: 'Bus',
        distanceKm: 401.0,
      );
      expect(popularRouteRoadKm(gmw, const []), 401.0);
    });

    test('Laoag Partas → Cubao returns null (unknown distance)', () {
      const route = PopularRoute(
        from: 'Laoag Partas Terminal',
        to: 'Cubao Partas Terminal',
        operator: 'Partas',
        vehicle: 'Bus',
      );
      expect(popularRouteRoadKm(route, const []), isNull);
    });
  });

  group('rateForRouteVehicle (F5)', () {
    test('Bus uses the provincial aircon rate', () {
      expect(rateForRouteVehicle('Bus')?.id, 'prov-aircon');
    });

    test('Jeepney uses the traditional jeepney rate', () {
      expect(rateForRouteVehicle('Jeepney')?.id, 'trad-jeep');
    });

    test('Van and Tricycle have no table rate', () {
      expect(rateForRouteVehicle('Van'), isNull);
      expect(rateForRouteVehicle('Tricycle'), isNull);
    });

    test('an unknown vehicle has no table rate', () {
      expect(rateForRouteVehicle('Kalesa'), isNull);
    });
  });
}
