// Reset All Directions regression (Steven, Nov 7, 20:41:
// "Mag Reset Direction ka ako na gagawa New Line" + "Lahat" —
// reset the direction for ALL routes; he draws the new lines
// himself via the Draw line tool).
//
// [resetAllDirectionsPlan] is pure: it clears BOTH the drawn
// line points (viaWaypoints) AND the named via stops (viaHubs)
// on every admin-added route and every seeded-route override —
// a full reset to each route's generated/OSRM path. Fares
// (regular / student / PWD / Senior) are NEVER changed: an
// override that still carries a fare is saved back with only
// the direction removed; one that carried only a direction is
// deleted (reset to the built-in route). Routes with no saved
// direction are left alone.
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

CustomRoute _custom({
  String from = 'Cabugao',
  String to = 'Vigan Bus Terminal',
  double fare = 60,
  List<String> viaHubs = const [],
  List<RouteWaypoint> viaWaypoints = const [],
}) =>
    CustomRoute(
      from: from,
      to: to,
      operator: 'Partas',
      vehicle: 'Bus',
      fare: fare,
      viaHubs: viaHubs,
      viaWaypoints: viaWaypoints,
    );

RouteFareOverride _override({
  String routeKey = 'Cabugao|Vigan Bus Terminal',
  double? fare,
  double? studentFare,
  List<String> viaHubs = const [],
  List<RouteWaypoint> viaWaypoints = const [],
}) =>
    RouteFareOverride(
      routeKey: routeKey,
      fare: fare,
      studentFare: studentFare,
      viaHubs: viaHubs,
      viaWaypoints: viaWaypoints,
    );

const _point = RouteWaypoint(lat: 17.72, lng: 120.45);

void main() {
  group('resetAllDirectionsPlan', () {
    test('no saved directions means an empty plan', () {
      final plan = resetAllDirectionsPlan(
        customs: [
          _custom(),
          _custom(from: 'Sinait', to: 'Cabugao', fare: 20),
        ],
        overrides: [_override(fare: 60)],
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.affectedCount, 0);
      expect(plan.clearedCustoms, isEmpty);
      expect(plan.clearedOverrides, isEmpty);
      expect(plan.deletedOverrideKeys, isEmpty);
    });

    test('a custom route with a drawn line is cleared, fare kept', () {
      final plan = resetAllDirectionsPlan(
        customs: [_custom(viaWaypoints: [_point])],
        overrides: const [],
      );
      expect(plan.affectedCount, 1);
      expect(plan.clearedCustoms.length, 1);
      expect(plan.clearedCustoms.first.viaWaypoints, isEmpty);
      expect(plan.clearedCustoms.first.viaHubs, isEmpty);
      expect(plan.clearedCustoms.first.fare, 60);
      expect(plan.clearedCustoms.first.from, 'Cabugao');
    });

    test('a custom route with named via stops only is cleared', () {
      final plan = resetAllDirectionsPlan(
        customs: [
          _custom(viaHubs: ['San Juan, Ilocos Sur']),
        ],
        overrides: const [],
      );
      expect(plan.affectedCount, 1);
      expect(plan.clearedCustoms.first.viaHubs, isEmpty);
      expect(plan.clearedCustoms.first.viaWaypoints, isEmpty);
    });

    test('an override with a fare + a direction is saved, fare kept', () {
      final plan = resetAllDirectionsPlan(
        customs: const [],
        overrides: [
          _override(fare: 60, studentFare: 60, viaWaypoints: [_point]),
        ],
      );
      expect(plan.affectedCount, 1);
      expect(plan.clearedOverrides.length, 1);
      expect(plan.clearedOverrides.first.routeKey,
          'Cabugao|Vigan Bus Terminal');
      expect(plan.clearedOverrides.first.fare, 60);
      expect(plan.clearedOverrides.first.studentFare, 60);
      expect(plan.clearedOverrides.first.viaWaypoints, isEmpty);
      expect(plan.clearedOverrides.first.viaHubs, isEmpty);
      expect(plan.deletedOverrideKeys, isEmpty);
    });

    test('an override with ONLY a direction is deleted', () {
      final plan = resetAllDirectionsPlan(
        customs: const [],
        overrides: [_override(viaWaypoints: [_point])],
      );
      expect(plan.affectedCount, 1);
      expect(plan.deletedOverrideKeys, ['Cabugao|Vigan Bus Terminal']);
      expect(plan.clearedOverrides, isEmpty);
    });

    test('an override with a fare + named via stops is saved', () {
      final plan = resetAllDirectionsPlan(
        customs: const [],
        overrides: [
          _override(fare: 45, viaHubs: ['San Juan, Ilocos Sur']),
        ],
      );
      expect(plan.affectedCount, 1);
      expect(plan.clearedOverrides.length, 1);
      expect(plan.clearedOverrides.first.fare, 45);
      expect(plan.clearedOverrides.first.viaHubs, isEmpty);
      expect(plan.deletedOverrideKeys, isEmpty);
    });

    test('counts sum customs + saved overrides + deleted overrides', () {
      final plan = resetAllDirectionsPlan(
        customs: [
          _custom(viaWaypoints: [_point]),
          _custom(from: 'Sinait', to: 'Cabugao', fare: 20),
        ],
        overrides: [
          _override(fare: 60, viaWaypoints: [_point]),
          _override(routeKey: 'Sinait|Cabugao', viaHubs: ['Magsingal']),
        ],
      );
      expect(plan.clearedCustoms.length, 1);
      expect(plan.clearedOverrides.length, 1);
      expect(plan.deletedOverrideKeys, ['Sinait|Cabugao']);
      expect(plan.affectedCount, 3);
    });
  });
}
