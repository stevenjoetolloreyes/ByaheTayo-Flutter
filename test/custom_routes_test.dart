// Tests for the admin-only Add Route feature (Nov 6, 2026):
// validation, the custom line, distance/ETA, JSON round-trip,
// and the admin gate on the local repository. Firestore is not
// touched here — the local repository covers the same rules.
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = AuthUser(
  uid: 'admin-1',
  email: 'stevenjoereyes0625@gmail.com',
);
const _adminUpper = AuthUser(
  uid: 'admin-2',
  email: 'STEVENJOEREYES23@GMAIL.COM',
);
const _regular = AuthUser(uid: 'user-1', email: 'student@example.com');

CustomRoute _route({
  String from = 'Cabugao',
  String to = 'Vigan Bus Terminal',
  String operator = 'Partas',
  String vehicle = 'Bus',
  double fare = 60,
  List<String> viaHubs = const [],
}) {
  return CustomRoute(
    from: from,
    to: to,
    operator: operator,
    vehicle: vehicle,
    fare: fare,
    viaHubs: viaHubs,
  );
}

void main() {
  group('validateCustomRoute', () {
    test('a complete route is valid', () {
      expect(
        validateCustomRoute(
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
          operator: 'Partas',
          vehicle: 'Bus',
          fareText: '60',
        ),
        isNull,
      );
    });

    test('blocks empty From / To / unknown hubs', () {
      expect(
        validateCustomRoute(
          from: null,
          to: 'Vigan Bus Terminal',
          operator: 'Partas',
          vehicle: 'Bus',
          fareText: '60',
        ),
        isNotNull,
      );
      expect(
        validateCustomRoute(
          from: 'Cabugao',
          to: 'Nowhere',
          operator: 'Partas',
          vehicle: 'Bus',
          fareText: '60',
        ),
        isNotNull,
      );
    });

    test('blocks same From and To', () {
      expect(
        validateCustomRoute(
          from: 'Cabugao',
          to: 'Cabugao',
          operator: 'Partas',
          vehicle: 'Bus',
          fareText: '60',
        ),
        contains('same'),
      );
    });

    test('blocks missing operator / vehicle', () {
      expect(
        validateCustomRoute(
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
          operator: '  ',
          vehicle: 'Bus',
          fareText: '60',
        ),
        isNotNull,
      );
      expect(
        validateCustomRoute(
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
          operator: 'Partas',
          vehicle: 'Train',
          fareText: '60',
        ),
        isNotNull,
      );
    });

    test('blocks missing, non-numeric, zero, and negative fares', () {
      for (final fare in ['', 'abc', '0', '-5']) {
        expect(
          validateCustomRoute(
            from: 'Cabugao',
            to: 'Vigan Bus Terminal',
            operator: 'Partas',
            vehicle: 'Bus',
            fareText: fare,
          ),
          isNotNull,
          reason: 'fare "$fare" must be rejected',
        );
      }
    });
  });

  group('custom route line and numbers', () {
    test('line points follow From → via → To in order', () {
      final route = _route(
        from: 'Vigan Bus Terminal',
        to: 'San Juan, Ilocos Sur',
        viaHubs: const ['Magsingal'],
      );
      // Magsingal is not a hub, so it is skipped: the line is
      // From → To. Via stops must be hub names to draw.
      final points = customRouteLinePoints(route);
      expect(points.length, 2);
      expect(points.first, const LatLng(17.56641, 120.38590));
      expect(points.last, const LatLng(17.73979, 120.45719));
    });

    test('line points include hub via-stops in order', () {
      final route = _route(
        from: 'Laoag Terminal',
        to: 'Vigan Bus Terminal',
        viaHubs: const ['Cabugao', 'San Juan, Ilocos Sur'],
      );
      final points = customRouteLinePoints(route);
      expect(points.length, 4);
      expect(points[0], const LatLng(18.1958, 120.59062));
      expect(points[1], const LatLng(17.78916, 120.45838));
      expect(points[2], const LatLng(17.73979, 120.45719));
      expect(points[3], const LatLng(17.56641, 120.38590));
    });

    test('road km sums each leg with the ×1.22 rule', () {
      final route = _route(
        from: 'Vigan Bus Terminal',
        to: 'San Juan, Ilocos Sur',
      );
      expect(customRouteRoadKm(route).toStringAsFixed(1), '25.3');
      final long = _route(from: 'Laoag Terminal', to: 'Vigan Bus Terminal');
      expect(customRouteRoadKm(long).toStringAsFixed(1), '89.4');
    });

    test('ETA uses the existing transit model', () {
      final route = _route(
        from: 'Vigan Bus Terminal',
        to: 'San Juan, Ilocos Sur',
      );
      // 25.3 km, same region (Ilocos Sur): 32 kph + 10 min
      // allowance = 57.4 min, rounded to 5 → 55 min.
      expect(customRouteEtaMinutes(route), 55);
      expect(formatTripTime(customRouteEtaMinutes(route)), '55 min');
    });

    test('RouteInfo carries the custom route for card and line', () {
      final info = customRouteToRouteInfo(_route(fare: 45));
      expect(info.customRoute, isNotNull);
      expect(info.customRoute!.fare, 45);
      expect(info.originName, 'Cabugao');
      expect(info.dest.name, 'Vigan Bus Terminal');
      expect(info.direction, Direction.southbound);
      expect(info.roadKm.toStringAsFixed(1), '31.6');
    });
  });

  group('JSON round-trip', () {
    test('toJson/fromJson keeps id, fare, and via-stops', () {
      final route = _route().copyWith(
        id: 'abc123',
        viaHubs: const ['Cabugao'],
        authorUid: 'admin-1',
        authorEmail: 'stevenjoereyes0625@gmail.com',
      );
      final restored = CustomRoute.fromJson('abc123', route.toJson());
      expect(restored.id, 'abc123');
      expect(restored.from, 'Cabugao');
      expect(restored.to, 'Vigan Bus Terminal');
      expect(restored.fare, 60);
      expect(restored.viaHubs, ['Cabugao']);
      expect(restored.authorEmail, 'stevenjoereyes0625@gmail.com');
    });
  });

  group('LocalCustomRouteRepository admin gate', () {
    late LocalCustomRouteRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = LocalCustomRouteRepository();
    });

    test('regular users cannot create, update, or delete', () async {
      await expectLater(
        repo.create(_route(), _regular),
        throwsStateError,
      );
      expect(await repo.loadAll(), isEmpty);
      final created = await repo.create(_route(), _admin);
      await expectLater(
        repo.update(created, _regular),
        throwsStateError,
      );
      await expectLater(
        repo.delete(created, _regular),
        throwsStateError,
      );
      expect((await repo.loadAll()).length, 1);
    });

    test('admin email check is case-insensitive', () async {
      final created = await repo.create(_route(), _adminUpper);
      expect(created.authorEmail, 'STEVENJOEREYES23@GMAIL.COM');
      await repo.delete(created, _adminUpper);
      expect(await repo.loadAll(), isEmpty);
    });

    test('admin create/update/delete round-trips and persists', () async {
      final created = await repo.create(_route(fare: 60), _admin);
      expect(created.id, isNotNull);
      final updated = await repo.update(
        created.copyWith(fare: 65),
        _admin,
      );
      expect(updated.fare, 65);
      final loaded = await repo.loadAll();
      expect(loaded.length, 1);
      expect(loaded.first.fare, 65);
      // A fresh repository instance reads the same cache.
      final again = await LocalCustomRouteRepository().loadAll();
      expect(again.length, 1);
      expect(again.first.fare, 65);
      await repo.delete(updated, _admin);
      expect(await repo.loadAll(), isEmpty);
    });

    test('invalid routes are rejected even for admins', () async {
      await expectLater(
        repo.create(_route(fare: 0), _admin),
        throwsArgumentError,
      );
      await expectLater(
        repo.create(_route(from: 'Cabugao', to: 'Cabugao'), _admin),
        throwsArgumentError,
      );
      expect(await repo.loadAll(), isEmpty);
    });
  });
}
