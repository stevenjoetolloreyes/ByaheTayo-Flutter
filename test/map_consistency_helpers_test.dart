// Tests for the Map-side consistency helpers (Fares × Map audit,
// Nov 7, 2026): the "My location" jump origin (J2), the
// admin-stop origin in the ETA preview (F9), the LTFRB estimate
// on the Map sheet (F4), the discounted label (F6), the
// operator/vehicle line (F8), and the guard that hides a discount
// with no regular fare. All pure helpers — no MapLibre, no
// network.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('resolveJumpOrigin (J2)', () {
    final homeHub = hubByName('Cabugao', [])!;
    const userPos = LatLng(17.73979, 120.45719);

    test('the jump coordinates win over the Map\'s last position', () {
      final origin = resolveJumpOrigin(
        jumpLat: 18.20207,
        jumpLng: 120.53721,
        userPos: userPos,
        homeHub: homeHub,
      );
      expect(origin.lat, 18.20207);
      expect(origin.lng, 120.53721);
      expect(origin.isUserLocation, isTrue);
    });

    test('no jump coordinates: the Map\'s last position is used', () {
      final origin = resolveJumpOrigin(
        userPos: userPos,
        homeHub: homeHub,
      );
      expect(origin.lat, userPos.latitude);
      expect(origin.lng, userPos.longitude);
      expect(origin.isUserLocation, isTrue);
    });

    test('no coordinates anywhere: the home hub, not a user location',
        () {
      final origin = resolveJumpOrigin(homeHub: homeHub);
      expect(origin.lat, homeHub.lat);
      expect(origin.lng, homeHub.lng);
      expect(origin.isUserLocation, isFalse);
    });

    test('a jump latitude without a longitude is ignored', () {
      final origin = resolveJumpOrigin(
        jumpLat: 18.20207,
        userPos: userPos,
        homeHub: homeHub,
      );
      expect(origin.lat, userPos.latitude);
      expect(origin.isUserLocation, isTrue);
    });
  });

  group('previewMinutesForRoute (F9)', () {
    test('an admin-added stop as origin uses its region', () {
      // Origin: an admin stop in Ilocos Sur; destination: Cabugao
      // (Ilocos Sur) — same region, 100 km, transit → 200 min.
      // Before the fix the origin was looked up in the 16
      // built-in hubs only, so it came back null and the same
      // trip priced as a different-region trip (170 min).
      final route = RouteInfo(
        originName: 'My Admin Stop',
        dest: hubByName('Cabugao', [])!,
        roadKm: 100,
        direction: Direction.southbound,
      );
      const adminStop = BusStop(
        name: 'My Admin Stop',
        region: 'Ilocos Sur',
        lat: 17.79,
        lng: 120.46,
      );
      expect(
        previewMinutesForRoute(
          route: route,
          stops: const [adminStop],
          mode: TravelMode.transit,
        ),
        200,
      );
      expect(
        previewMinutesForRoute(
          route: route,
          stops: const [],
          mode: TravelMode.transit,
        ),
        170,
      );
    });

    test('a mountain destination still uses the mountain speed', () {
      final route = RouteInfo(
        originName: 'Cabugao',
        dest: hubByName('Bontoc', [])!,
        roadKm: 100,
        direction: Direction.northbound,
      );
      expect(
        previewMinutesForRoute(
          route: route,
          stops: const [],
          mode: TravelMode.transit,
        ),
        235,
      );
    });
  });

  group('mapSheetEstimateFare (F4)', () {
    test('Bus 89.4 km uses the provincial aircon rate (₱220.25)', () {
      expect(
        mapSheetEstimateFare(vehicle: 'Bus', roadKm: 89.4),
        closeTo(220.25, 0.01),
      );
    });

    test('Jeepney 31.6 km uses the traditional jeepney rate (₱70)', () {
      expect(
        mapSheetEstimateFare(vehicle: 'Jeepney', roadKm: 31.6),
        closeTo(70.0, 0.01),
      );
    });

    test('Van, Tricycle and an unknown vehicle have no estimate', () {
      expect(mapSheetEstimateFare(vehicle: 'Van', roadKm: 89.4), isNull);
      expect(
        mapSheetEstimateFare(vehicle: 'Tricycle', roadKm: 5),
        isNull,
      );
      expect(
        mapSheetEstimateFare(vehicle: null, roadKm: 89.4),
        isNull,
      );
    });
  });

  group('mapDiscountLabel (F6)', () {
    test('an admin-set student fare shows no -20% claim', () {
      expect(mapDiscountLabel(studentFareSet: true), 'DISCOUNTED');
    });

    test('a derived student fare keeps the -20% label', () {
      expect(mapDiscountLabel(studentFareSet: false), 'DISCOUNTED -20%');
    });
  });

  group('mapRouteOperatorVehicle (F8)', () {
    test('a custom route shows its own operator and vehicle', () {
      const custom = CustomRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        operator: 'My Bus Co',
        vehicle: 'Bus',
        fare: 60,
      );
      expect(
        mapRouteOperatorVehicle(
          customRoute: custom,
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
        ),
        (operator: 'My Bus Co', vehicle: 'Bus'),
      );
    });

    test('a seeded route shows the seeded operator and vehicle', () {
      // The seeded Cabugao → Vigan route stores a vehicle ('Bus')
      // but no operator — the 'Partas' name lives only in the
      // preview, not in the app's route data, so nothing is
      // invented here: the header shows 'Bus' alone.
      expect(
        mapRouteOperatorVehicle(
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
        ),
        (operator: null, vehicle: 'Bus'),
      );
    });

    test('a generic hub-to-hub route shows neither', () {
      expect(
        mapRouteOperatorVehicle(
          from: 'Sinait',
          to: 'San Juan, Ilocos Sur',
        ),
        (operator: null, vehicle: null),
      );
    });
  });

  group('resolveMapSheetFares guard', () {
    test('an admin-set student fare with no regular fare is hidden',
        () {
      // Laoag Terminal → Vigan Bus Terminal has no set fare;
      // an override that sets ONLY the student fare must not
      // produce a discount card with no fare to discount — the
      // Fares tab's effective fares return null the same way.
      const override = RouteFareOverride(
        routeKey: 'Laoag Terminal|Vigan Bus Terminal',
        studentFare: 60,
      );
      final fares = resolveMapSheetFares(
        override: override,
        from: 'Laoag Terminal',
        to: 'Vigan Bus Terminal',
      );
      expect(fares.regular, isNull);
      expect(fares.discounted, isNull);
      expect(fares.pwd, isNull);
      expect(fares.senior, isNull);
    });
  });
}
