// Unit tests for the Map tab's pure route logic (no GoogleMap needed).
import 'dart:convert';

import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('dark map style is valid JSON in dark mode, none in light', () {
    final dark = mapStyleForBrightness(Brightness.dark);
    expect(dark, isNotNull);
    // Parses as a Google style array, charcoal-based like the preview.
    final decoded = jsonDecode(dark!) as List;
    expect(decoded, isNotEmpty);
    expect(dark, contains('#1e2126'));
    expect(mapStyleForBrightness(Brightness.light), isNull);
  });

  test('road distance Cabugao to Vigan matches the Fares rule', () {
    final km = roadKmBetween(17.78916, 120.45838, 17.56138, 120.38564);
    expect(km.toStringAsFixed(1), '32.3');
  });

  test('direction is northbound when the destination is further north', () {
    // Cabugao (17.79) -> Sinait (17.88): northbound.
    expect(directionOf(17.78916, 17.87538), Direction.northbound);
    // Cabugao (17.79) -> Vigan City (17.56): southbound.
    expect(directionOf(17.78916, 17.56138), Direction.southbound);
  });

  test('transit ETA Cabugao to Vigan matches the web model', () {
    // roadKm 32.3, not same region (Ilocos Sur vs Ilocos Region),
    // not mountain: 40 kph, 20 min allowance -> 70 min.
    final minutes = estimateTripMinutes(
      roadKm: 32.3,
      mountain: false,
      sameRegion: false,
      mode: TravelMode.transit,
    );
    expect(minutes, 70);
    expect(formatTripTime(minutes), '1 hr 10 min');
  });

  test('walking ETA uses the walking pace and minimum', () {
    final minutes = estimateTripMinutes(
      roadKm: 32.3,
      mountain: false,
      sameRegion: false,
      mode: TravelMode.walking,
    );
    expect(minutes, 430);
    expect(formatTripTime(430), '7 hr 10 min');
    expect(formatTripTime(45), '45 min');
    expect(formatTripTime(60), '1 hr');
  });

  test('mountain hubs are Baguio City, Bontoc, and Banaue', () {
    expect(isMountainHub(hubs[7]), isTrue); // Baguio City
    expect(isMountainHub(hubs[8]), isTrue); // Bontoc
    expect(isMountainHub(hubs[9]), isTrue); // Banaue
    expect(isMountainHub(hubs[2]), isFalse); // Cabugao
  });

  test('routesFrom sorts nearest first and skips the origin hub', () {
    final routes = routesFrom(17.78916, 120.45838, 'Cabugao');
    expect(routes, isNotEmpty);
    expect(routes.first.dest.name, 'San Juan, Ilocos Sur');
    expect(
      routes.map((r) => r.dest.name),
      isNot(contains('Cabugao')),
    );
    for (var i = 1; i < routes.length; i++) {
      expect(routes[i].roadKm, greaterThanOrEqualTo(routes[i - 1].roadKm));
    }
  });

  test('groupRoutesByDirection splits Cabugao routes 3 north / 12 south',
      () {
    final routes = routesFrom(17.78916, 120.45838, 'Cabugao');
    final grouped = groupRoutesByDirection(routes);
    expect(grouped[Direction.northbound]!.length, 3);
    expect(grouped[Direction.southbound]!.length, 12);
    expect(
      grouped[Direction.northbound]!.map((r) => r.dest.name),
      containsAll(['Sinait', 'Laoag City', 'Laoag Terminal']),
    );
    expect(
      grouped[Direction.southbound]!.map((r) => r.dest.name),
      contains('Vigan Bus Terminal'),
    );
  });

  test('filterRoutesByQuery matches destination name or region', () {
    final routes = routesFrom(17.78916, 120.45838, 'Cabugao');
    final filtered = filterRoutesByQuery(routes, 'Vigan');
    expect(filtered.length, 2);
    // The terminal is the nearer Vigan endpoint, so it sorts first.
    expect(filtered.first.dest.name, 'Vigan Bus Terminal');
    expect(
      filtered.map((r) => r.dest.name),
      contains('Vigan City'),
    );
    expect(filterRoutesByQuery(routes, '').length, routes.length);
    expect(filterRoutesByQuery(routes, 'zzz'), isEmpty);
  });

  test('known user-verified bus fares match the web table', () {
    expect(knownBusFares['Cabugao|Vigan City'], 60);
    expect(knownBusFares['Cabugao|Sinait'], 20);
    expect(knownBusFares['Vigan City|Sinait'], isNull);
  });

  test('Vigan Bus Terminal is a separate hub at Jose Singson / Rivero',
      () {
    final terminal = hubs.firstWhere((h) => h.name == 'Vigan Bus Terminal');
    expect(terminal.lat, 17.56641);
    expect(terminal.lng, 120.38590);
    expect(terminal.region, 'Ilocos Sur');
    // The old Vigan City hub is kept: community posts use its name.
    final city = hubs.firstWhere((h) => h.name == 'Vigan City');
    expect(city.lat, 17.56138);
    expect(city.lng, 120.38564);
    // Appended last, so earlier hub indices do not shift.
    expect(hubs.indexOf(terminal), 14);
    expect(hubs.length, 16);
  });

  test('Laoag Terminal is a separate hub from Laoag City', () {
    final terminal = hubs.firstWhere((h) => h.name == 'Laoag Terminal');
    expect(terminal.lat, 18.1958);
    expect(terminal.lng, 120.59062);
    expect(hubs.indexOf(terminal), 15);
  });

  test('terminal pairs use the verified Cabugao-Vigan ₱60 fare', () {
    expect(knownBusFares['Cabugao|Vigan Bus Terminal'], 60);
    expect(knownBusFares['Vigan Bus Terminal|Cabugao'], 60);
    // Sample fares are deliberately NOT verified fares.
    expect(knownBusFares['Vigan Bus Terminal|San Juan, Ilocos Sur'],
        isNull);
    expect(knownBusFares['Laoag Terminal|Vigan Bus Terminal'], isNull);
  });

  test('Quezon Ave via waypoint applies only to the terminal', () {
    final terminal = hubs.firstWhere((h) => h.name == 'Vigan Bus Terminal');
    final via = viaWaypointsForDestination(terminal);
    expect(via.length, 1);
    // Start of the Avenida Quezon leg (OSRM-verified Nov 6, 2026).
    expect(via.first.latitude, 17.576831);
    expect(via.first.longitude, 120.387462);
    final city = hubs.firstWhere((h) => h.name == 'Vigan City');
    expect(viaWaypointsForDestination(city), isEmpty);
    final sanJuan = hubs.firstWhere((h) => h.name == 'San Juan, Ilocos Sur');
    expect(viaWaypointsForDestination(sanJuan), isEmpty);
  });

  test('routesFrom Cabugao reaches both new hubs', () {
    final routes = routesFrom(17.78916, 120.45838, 'Cabugao');
    final names = routes.map((r) => r.dest.name).toList();
    expect(names, contains('Vigan Bus Terminal'));
    expect(names, contains('Laoag Terminal'));
    final toTerminal = routes.firstWhere(
      (r) => r.dest.name == 'Vigan Bus Terminal',
    );
    expect(toTerminal.roadKm.toStringAsFixed(1), '31.6');
    expect(toTerminal.direction, Direction.southbound);
    final toLaoag = routes.firstWhere(
      (r) => r.dest.name == 'Laoag Terminal',
    );
    // Cabugao → Laoag Terminal is 57.7 km; 89.4 km is the
    // Laoag Terminal → Vigan Bus Terminal leg (tested in the
    // fare test via resolveTransitFare).
    expect(toLaoag.roadKm.toStringAsFixed(1), '57.7');
    expect(toLaoag.direction, Direction.northbound);
    final toSanJuan = routesFrom(17.56641, 120.38590, 'Vigan Bus Terminal')
        .firstWhere((r) => r.dest.name == 'San Juan, Ilocos Sur');
    expect(toSanJuan.roadKm.toStringAsFixed(1), '25.3');
    expect(toSanJuan.direction, Direction.northbound);
  });



  test('filterRoutesByVehicle keeps all routes except Train', () {
    final routes = routesFrom(17.78916, 120.45838, 'Cabugao');
    expect(routes, isNotEmpty);
    expect(filterRoutesByVehicle(routes, VehicleType.train), isEmpty);
    expect(
      filterRoutesByVehicle(routes, VehicleType.bus).length,
      routes.length,
    );
    expect(
      filterRoutesByVehicle(routes, VehicleType.car).length,
      routes.length,
    );
    expect(
      filterRoutesByVehicle(routes, VehicleType.motorcycle).length,
      routes.length,
    );
    expect(
      filterRoutesByVehicle(routes, VehicleType.anyVehicle).length,
      routes.length,
    );
  });

  test('vehicleLabel names all five selections', () {
    expect(vehicleLabel(VehicleType.bus), 'Bus');
    expect(vehicleLabel(VehicleType.car), 'Car');
    expect(vehicleLabel(VehicleType.train), 'Train');
    expect(vehicleLabel(VehicleType.motorcycle), 'Motorcycle');
    expect(vehicleLabel(VehicleType.anyVehicle), 'Any Vehicle');
  });

  test('navLinePoints starts at the user and trims passed road points', () {
    const a = LatLng(17.0, 120.0);
    const b = LatLng(18.0, 120.0);
    const c = LatLng(19.0, 120.0);
    const user = LatLng(18.1, 120.0);
    final trimmed = navLinePoints(user: user, roadPoints: [a, b, c], dest: c);
    expect(trimmed.first, user);
    expect(trimmed, [user, b, c]);
    // No road points: direct user -> destination line.
    final direct = navLinePoints(user: user, roadPoints: null, dest: c);
    expect(direct, [user, c]);
  });


  test('estimatedArrivalText adds ETA minutes to now as a clock time', () {
    expect(
      estimatedArrivalText(DateTime(2026, 11, 1, 12, 0), 90),
      '1:30 PM',
    );
    expect(
      estimatedArrivalText(DateTime(2026, 11, 1, 11, 30), 30),
      '12:00 PM',
    );
    expect(
      estimatedArrivalText(DateTime(2026, 11, 1, 23, 45), 30),
      '12:15 AM',
    );
    expect(
      estimatedArrivalText(DateTime(2026, 11, 1, 9, 5), 5),
      '9:10 AM',
    );
  });



  test('nearestPointIndex picks the closest path point', () {
    const pts = [
      LatLng(17.0, 120.0),
      LatLng(18.0, 120.0),
      LatLng(19.0, 120.0),
    ];
    expect(nearestPointIndex(pts, const LatLng(18.1, 120.0)), 1);
    expect(nearestPointIndex(pts, const LatLng(19.5, 120.0)), 2);
  });

  test('pathKmBetween sums segments and returns 0 when reversed', () {
    const cabugao = LatLng(17.78916, 120.45838);
    const vigan = LatLng(17.56138, 120.38564);
    expect(
      pathKmBetween([cabugao, vigan], 0, 1).toStringAsFixed(1),
      '26.5',
    );
    expect(pathKmBetween([cabugao, vigan], 1, 0), 0);
    expect(pathKmBetween([cabugao], 0, 0), 0);
  });

  test('decodePolyline decodes the classic Google example', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.length, 3);
    expect(points[0].latitude, closeTo(38.5, 0.0001));
    expect(points[0].longitude, closeTo(-120.2, 0.0001));
    expect(points[1].latitude, closeTo(40.7, 0.0001));
    expect(points[1].longitude, closeTo(-120.95, 0.0001));
    expect(points[2].latitude, closeTo(43.252, 0.0001));
    expect(points[2].longitude, closeTo(-126.453, 0.0001));
    expect(decodePolyline(''), isEmpty);
    expect(decodePolyline('???'), isEmpty);
  });

  test('parseGoogleSteps reads instructions, locations, distances', () {
    final steps = parseGoogleSteps({
      'routes': [
        {
          'legs': [
            {
              'steps': [
                {
                  'navigationInstruction': {
                    'instructions': 'Head north on Manila North Road',
                  },
                  'startLocation': {
                    'latLng': {'latitude': 17.78916, 'longitude': 120.45838},
                  },
                  'distanceMeters': 1200,
                },
                {
                  'navigationInstruction': {
                    'instructions': 'Turn left onto Rizal Street',
                  },
                  'startLocation': {
                    'latLng': {'latitude': 17.60, 'longitude': 120.40},
                  },
                  'distanceMeters': 800,
                },
              ],
            },
          ],
        },
      ],
    });
    expect(steps.length, 2);
    expect(steps[0].instruction, 'Head north on Manila North Road');
    expect(steps[0].distanceMeters, 1200);
    expect(steps[0].location.latitude, 17.78916);
    expect(steps[1].instruction, 'Turn left onto Rizal Street');
    expect(parseGoogleSteps({'routes': []}), isEmpty);
    expect(parseGoogleSteps({}), isEmpty);
  });


  test('navArrowIcon maps instruction words to arrows', () {
    expect(navArrowIcon('Turn left onto Rizal Street'), Icons.turn_left);
    expect(navArrowIcon('Turn right onto Quezon Ave'), Icons.turn_right);
    expect(navArrowIcon('Make a U-turn onto the road'), Icons.u_turn_left);
    expect(navArrowIcon('At the roundabout, continue'), Icons.rotate_right);
    expect(navArrowIcon('Head south on Manila North Road'),
        Icons.arrow_upward);
    expect(navArrowIcon('Continue onto the road'), Icons.arrow_upward);
  });

  test('shortAction cuts the maneuver phrase from instructions', () {
    expect(shortAction('Turn left onto Rizal Street'), 'Turn left');
    expect(shortAction('Turn slightly right onto Quezon Ave'), 'Turn right');
    expect(shortAction('Head south on Manila North Road'), 'Head south');
    expect(shortAction('Make a U-turn onto the road'), 'Make a U-turn');
    expect(shortAction('At the roundabout, continue onto the road'),
        'At the roundabout');
    expect(shortAction('Continue onto the road'), 'Continue');
  });

  test('formatNavDistance uses meters below 1 km', () {
    expect(formatNavDistance(0.27), '270 m');
    expect(formatNavDistance(0.05), '50 m');
    expect(formatNavDistance(3.9), '3.9 km');
    expect(formatNavDistance(1.0), '1.0 km');
  });

  test('parseGoogleDuration reads the Routes duration string', () {
    expect(parseGoogleDuration('1136s'), 1136.0);
    expect(parseGoogleDuration(42), 42.0);
    expect(parseGoogleDuration(null), 0);
    expect(parseGoogleDuration('abc'), 0);
  });

  test('remainingMinutes scales the route duration by distance left', () {
    expect(
      remainingMinutes(remainingKm: 16, fullKm: 32, durationSec: 2280),
      20,
    );
    expect(remainingMinutes(remainingKm: 0, fullKm: 32, durationSec: 2280), 0);
    expect(remainingMinutes(remainingKm: 10, fullKm: 0, durationSec: 100), 0);
    expect(remainingMinutes(remainingKm: 10, fullKm: 32, durationSec: 0), 0);
  });

  test('routeModifiersJson carries the avoid toggles', () {
    expect(
      routeModifiersJson(
        avoidHighways: true,
        avoidTolls: false,
        avoidFerries: true,
      ),
      {
        'avoidHighways': true,
        'avoidTolls': false,
        'avoidFerries': true,
      },
    );
  });


  test('needsReroute fires only when far off-route and cooled down', () {
    final now = DateTime(2026, 11, 1, 7, 22);
    expect(
      needsReroute(offRouteKm: 0.1, lastRerouteAt: null, now: now),
      isFalse,
    );
    expect(
      needsReroute(offRouteKm: 0.5, lastRerouteAt: null, now: now),
      isTrue,
    );
    expect(
      needsReroute(
        offRouteKm: 0.5,
        lastRerouteAt: now.subtract(const Duration(seconds: 10)),
        now: now,
      ),
      isFalse,
    );
    expect(
      needsReroute(
        offRouteKm: 0.5,
        lastRerouteAt: now.subtract(const Duration(seconds: 40)),
        now: now,
      ),
      isTrue,
    );
    expect(
      needsReroute(
        offRouteKm: double.infinity,
        lastRerouteAt: null,
        now: now,
      ),
      isTrue,
    );
  });


  test('snapToRoute snaps near fixes to the road, keeps far ones raw', () {
    const pts = [LatLng(17.0, 120.0), LatLng(17.01, 120.0)];
    expect(snapToRoute(const LatLng(17.0002, 120.0), pts), pts[0]);
    expect(snapToRoute(const LatLng(17.05, 120.0), pts).latitude, 17.05);
    expect(snapToRoute(const LatLng(17.0, 120.0), null).latitude, 17.0);
  });


  test('mode icons map to the four travel modes', () {
    expect(modeIcon(TravelMode.transit), Icons.directions_bus);
    expect(modeIcon(TravelMode.motorcycle), Icons.two_wheeler);
    expect(modeIcon(TravelMode.bicycle), Icons.directions_bike);
    expect(modeIcon(TravelMode.walking), Icons.directions_walk);
  });


  test('shouldRefreshPreview fires only after 100 m and a 15 s gap', () {
    final now = DateTime(2026, 11, 1, 8, 6);
    expect(
      shouldRefreshPreview(movedKm: 0.05, lastRefreshAt: null, now: now),
      isFalse,
    );
    expect(
      shouldRefreshPreview(movedKm: 0.5, lastRefreshAt: null, now: now),
      isTrue,
    );
    expect(
      shouldRefreshPreview(
        movedKm: 0.5,
        lastRefreshAt: now.subtract(const Duration(seconds: 5)),
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldRefreshPreview(
        movedKm: 0.5,
        lastRefreshAt: now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      isTrue,
    );
  });

  test('Churches query is Catholic-only and Northern-Luzon-only', () {
    final body = placesChurchesBody();
    expect(body['textQuery'], 'Catholic church');
    expect(body['includedType'], 'church');
    expect(body['regionCode'], 'PH');
    expect(body.containsKey('pageToken'), isFalse);
    final restriction = body['locationRestriction'] as Map;
    final rect = restriction['rectangle'] as Map;
    final low = rect['low'] as Map;
    final high = rect['high'] as Map;
    expect(low['latitude'], 16.0);
    expect(low['longitude'], 119.8);
    expect(high['latitude'], 20.6);
    expect(high['longitude'], 122.4);
    expect(placesChurchesBody(pageToken: 'tok')['pageToken'], 'tok');
  });

  test('Places pagination token and verified dedup', () {
    expect(placesNextPageToken({'nextPageToken': 'abc'}), 'abc');
    expect(placesNextPageToken({}), isNull);
    expect(placesNextPageToken({'nextPageToken': ''}), isNull);
    final places = [
      const ChurchPlace(
        name: 'Saint Mark the Evangelist Parish Church',
        lat: 17.79,
        lng: 120.45,
        address: 'Cabugao',
      ),
      const ChurchPlace(
        name: 'Some Other Church',
        lat: 18.0,
        lng: 120.5,
        address: 'Elsewhere',
      ),
    ];
    final deduped = dedupePlacesChurches(places, verifiedChurches);
    expect(deduped.map((c) => c.name), ['Some Other Church']);
  });

  test('Church destination hub carries name + coordinates', () {
    const church = ChurchPlace(
      name: 'Paoay Church',
      lat: 18.062,
      lng: 120.52039,
      address: 'Paoay, Ilocos Norte',
    );
    final dest = churchDestinationHub(church);
    expect(dest.name, 'Paoay Church');
    expect(dest.lat, 18.062);
    expect(dest.lng, 120.52039);
  });

  test('Verified churches cover Ilocos Sur + Ilocos Norte', () {
    expect(verifiedChurches.length, 18);
    final names = verifiedChurches.map((c) => c.name).toSet();
    expect(names.contains('St. Paul Metropolitan Cathedral'), isTrue);
    expect(names.contains('Paoay Church'), isTrue);
    expect(names.contains('St. William Cathedral'), isTrue);
    // Every verified entry sits inside Northern Luzon.
    for (final c in verifiedChurches) {
      expect(c.lat, greaterThanOrEqualTo(16.0));
      expect(c.lat, lessThanOrEqualTo(20.6));
      expect(c.lng, greaterThanOrEqualTo(119.8));
      expect(c.lng, lessThanOrEqualTo(122.4));
    }
  });

  test('Churches style hides base-map POIs, keeps base on bad input',
      () {
    final fromNull = churchesOnlyStyle(null)!;
    final decodedNull = jsonDecode(fromNull) as List;
    expect(decodedNull.length, 1);
    expect(decodedNull.first['featureType'], 'poi');
    final fromDark = churchesOnlyStyle('[{"featureType":"road"}]')!;
    final decodedDark = jsonDecode(fromDark) as List;
    expect(decodedDark.length, 2);
    expect(decodedDark.last['featureType'], 'poi');
    expect(churchesOnlyStyle('not-json'), 'not-json');
  });

  test('Verified churches include St. Mark, Cabugao, at real coords',
      () {
    final cabugao = verifiedChurches.firstWhere(
      (c) => c.name == 'St. Mark the Evangelist Parish',
    );
    expect(cabugao.address, 'Cabugao, Ilocos Sur');
    expect(cabugao.lat, 17.79479);
    expect(cabugao.lng, 120.45627);
  });

  test('parsePlacesChurches reads real places, skips unusable ones', () {
    final found = parsePlacesChurches({
      'places': [
        {
          'displayName': {'text': 'Metropolitan Cathedral'},
          'location': {'latitude': 17.571, 'longitude': 120.387},
          'formattedAddress': 'Vigan City, Ilocos Sur',
        },
        {
          // No coordinates: skipped, never guessed.
          'displayName': {'text': 'Nameless Chapel'},
        },
        {
          // No name: skipped.
          'location': {'latitude': 16.6, 'longitude': 120.3},
        },
      ],
    });
    expect(found.length, 1);
    expect(found.first.name, 'Metropolitan Cathedral');
    expect(found.first.lat, 17.571);
    expect(found.first.address, 'Vigan City, Ilocos Sur');
    expect(parsePlacesChurches({}), isEmpty);
    expect(parsePlacesChurches({'places': 'nope'}), isEmpty);
  });

  group('routeStopPins', () {
    // Cabugao -> Vigan Bus Terminal, no road geometry yet:
    // origin + destination only.
    List<RouteStop> defaultStops() => routeStops(
      origin: const LatLng(17.78916, 120.45838),
      originName: 'Cabugao',
      dest: hubs.firstWhere((h) => h.name == 'Vigan Bus Terminal'),
      roadPoints: null,
      totalKm: 32.3,
    );

    test('default route has numbered pins 1..N in stop order', () {
      final stops = defaultStops();
      expect(stops.length, 2);
      final pins = routeStopPins(stops, null);
      expect(pins.map((p) => p.number), [1, 2]);
      expect(pins[0].lat, stops[0].lat);
      expect(pins[0].lng, stops[0].lng);
      expect(pins[1].lat, stops[1].lat);
      expect(pins[1].lng, stops[1].lng);
      expect(pins.every((p) => !p.selected), isTrue);
    });

    test('selected stop is flagged on its pin only', () {
      final pins = routeStopPins(defaultStops(), 1);
      expect(pins[0].selected, isFalse);
      expect(pins[1].selected, isTrue);
    });

    test('no stops means no pins', () {
      expect(routeStopPins(const [], null), isEmpty);
    });
  });
}