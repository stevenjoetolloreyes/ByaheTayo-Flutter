// Unit tests for the OSM routing helpers (no map widget, no
// network — fixtures only).
import 'dart:convert';

import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('parseOsrmRoute', () {
    test('parses GeoJSON geometry, distance, duration and steps', () {
      final route = parseOsrmRoute({
        'routes': [
          {
            'distance': 27534.5,
            'duration': 2194.3,
            'geometry': {
              'coordinates': [
                [120.45838, 17.78916],
                [120.45719, 17.73979],
                [120.38590, 17.56641],
              ],
            },
            'legs': [
              {
                'steps': [
                  {
                    'maneuver': {
                      'type': 'depart',
                      'location': [120.45838, 17.78916],
                    },
                    'name': 'MacArthur Highway',
                    'distance': 5500.0,
                  },
                  {
                    'maneuver': {
                      'type': 'turn',
                      'modifier': 'left',
                      'location': [120.387462, 17.576831],
                    },
                    'name': 'Avenida Quezon',
                    'distance': 1200.0,
                  },
                  {
                    'maneuver': {
                      'type': 'arrive',
                      'location': [120.38590, 17.56641],
                    },
                    'name': '',
                    'distance': 0.0,
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(route, isNotNull);
      expect(route!.points.length, 3);
      // GeoJSON [lng, lat] is flipped to LatLng(lat, lng).
      expect(route.points.first.latitude, closeTo(17.78916, 1e-5));
      expect(route.points.first.longitude, closeTo(120.45838, 1e-5));
      expect(route.distanceKm, closeTo(27.5345, 0.001));
      expect(route.durationSec, closeTo(2194.3, 0.01));
      expect(route.steps.length, 3);
      expect(route.steps[0].instruction, 'Head out on MacArthur Highway');
      expect(
        route.steps[1].instruction,
        'Turn left onto Avenida Quezon',
      );
      expect(route.steps[2].instruction, 'Arrive at destination');
    });

    test('returns null for missing or unusable routes', () {
      expect(parseOsrmRoute({}), isNull);
      expect(parseOsrmRoute({'routes': []}), isNull);
      expect(
        parseOsrmRoute({
          'routes': [
            {
              'geometry': {
                'coordinates': [
                  [120.0, 17.0],
                ],
              },
            },
          ],
        }),
        isNull,
      );
    });
  });

  group('osrmRouteUrl', () {
    test('orders lng,lat and inserts the via point', () {
      final dest = hubs.firstWhere((h) => h.name == 'Vigan Bus Terminal');
      final url = osrmRouteUrl(
        oLat: 17.78916,
        oLng: 120.45838,
        dest: dest,
        via: const [LatLng(17.576831, 120.387462)],
      );
      expect(
        url,
        contains(
          '120.45838,17.78916;120.387462,17.576831;120.3859,17.56641',
        ),
      );
      expect(url, contains('overview=full'));
      expect(url, contains('geometries=geojson'));
      expect(url, contains('steps=true'));
    });
  });

  group('parseNominatimChurches', () {
    test('parses name + coordinates, skips unusable entries', () {
      final places = parseNominatimChurches([
        {
          'display_name':
              'Vigan Cathedral, Burgos Street, Vigan City, Ilocos Sur, Philippines',
          'lat': '17.571234',
          'lon': '120.387123',
        },
        {'display_name': 'No coords here'},
        {'display_name': '', 'lat': '17.0', 'lon': '120.0'},
      ]);
      expect(places.length, 1);
      expect(places.first.name, 'Vigan Cathedral');
      expect(places.first.lat, closeTo(17.571234, 1e-6));
      expect(places.first.lng, closeTo(120.387123, 1e-6));
      expect(places.first.address, contains('Vigan City'));
    });
  });

  group('nominatimChurchesUrl', () {
    test('is bounded to the Northern Luzon viewbox', () {
      final url = nominatimChurchesUrl();
      expect(url, contains('bounded=1'));
      expect(url, contains('viewbox=119.9,15.9,122.3,18.7'));
      expect(url, contains('Catholic'));
    });
  });

  group('routeStops', () {
    final dest = hubs.firstWhere((h) => h.name == 'Vigan Bus Terminal');
    // Hand-made road line Cabugao -> San Juan -> Vigan Terminal.
    // San Juan hub sits exactly on the line; Sinait is ~10 km off
    // it; Vigan City hub sits at the destination end.
    final road = <LatLng>[
      const LatLng(17.78916, 120.45838),
      const LatLng(17.73979, 120.45719),
      const LatLng(17.65, 120.42),
      const LatLng(17.60, 120.40),
      const LatLng(17.56641, 120.38590),
    ];

    test('origin, on-the-way hubs in road order, destination', () {
      final stops = routeStops(
        origin: const LatLng(17.78916, 120.45838),
        originName: 'Cabugao',
        dest: dest,
        roadPoints: road,
        totalKm: 27.5,
      );
      expect(
        stops.map((s) => s.name).toList(),
        ['Cabugao', 'San Juan, Ilocos Sur', 'Vigan Bus Terminal'],
      );
      expect(stops.first.role, 'Start');
      expect(stops[1].role, 'Stop');
      expect(stops.last.role, 'End');
      expect(stops.first.kmFromOrigin, 0);
      expect(stops.last.kmFromOrigin, greaterThan(20));
      // San Juan's distance from origin is measured along the
      // road, not as the crow flies.
      expect(stops[1].kmFromOrigin, greaterThan(4));
      expect(stops[1].kmFromOrigin, lessThan(8));
    });

    test('no road geometry yet means origin + destination only', () {
      final stops = routeStops(
        origin: const LatLng(17.78916, 120.45838),
        originName: 'Cabugao',
        dest: dest,
        roadPoints: null,
        totalKm: 27.5,
      );
      expect(
        stops.map((s) => s.name).toList(),
        ['Cabugao', 'Vigan Bus Terminal'],
      );
      expect(stops.last.kmFromOrigin, 27.5);
    });

    test('via-hubs of a custom route are always stops', () {
      final stops = routeStops(
        origin: const LatLng(17.78916, 120.45838),
        originName: 'Cabugao',
        dest: dest,
        roadPoints: null,
        totalKm: 27.5,
        viaHubNames: const ['San Juan, Ilocos Sur'],
      );
      expect(
        stops.map((s) => s.name).toList(),
        ['Cabugao', 'San Juan, Ilocos Sur', 'Vigan Bus Terminal'],
      );
    });
  });

  group('splitPathAt', () {
    test('split point belongs to both parts, no gap', () {
      final pts = [
        const LatLng(17.0, 120.0),
        const LatLng(17.1, 120.1),
        const LatLng(17.2, 120.2),
        const LatLng(17.3, 120.3),
      ];
      final split = splitPathAt(pts, 1);
      expect(split.before.length, 2);
      expect(split.after.length, 3);
      expect(split.before.last, split.after.first);
    });
  });

  group('estimatedStopMinutes', () {
    test('scales by distance and rounds to 5', () {
      expect(
        estimatedStopMinutes(
          kmFromOrigin: 13.75,
          totalKm: 27.5,
          totalMinutes: 40,
        ),
        20,
      );
      expect(
        estimatedStopMinutes(
          kmFromOrigin: 0,
          totalKm: 27.5,
          totalMinutes: 40,
        ),
        0,
      );
      expect(
        estimatedStopMinutes(
          kmFromOrigin: 5,
          totalKm: 0,
          totalMinutes: 40,
        ),
        0,
      );
    });
  });

  group('tileUrlTemplate', () {
    test('light is standard OSM, dark is CartoDB Dark Matter', () {
      expect(
        tileUrlTemplate(),
        contains('tile.openstreetmap.org'),
      );
      expect(
        tileUrlTemplate(dark: true),
        contains('basemaps.cartocdn.com/dark_all'),
      );
    });

    test('attribution follows the tile layer', () {
      expect(mapAttributionText(dark: false), '© OpenStreetMap contributors');
      expect(
        mapAttributionText(dark: true),
        '© OpenStreetMap contributors © CARTO',
      );
      expect(
        mapAttributionUrl(dark: false),
        contains('openstreetmap.org'),
      );
      expect(mapAttributionUrl(dark: true), contains('carto.com'));
    });
  });

  group('metaMapStyleUrl', () {
    test('dark is Canterbury Dark, light is canterbury_1_0', () {
      expect(
        metaMapStyleUrl(dark: true),
        'https://external.xx.fbcdn.net/maps/vt/style/dark/',
      );
      expect(
        metaMapStyleUrl(dark: false),
        'https://external.xx.fbcdn.net/maps/vt/style/canterbury_1_0/',
      );
      // The /style/light/ path returns HTTP 500 — it is never used.
      expect(metaMapStyleUrl(dark: false), isNot(contains('/style/light/')));
    });

    test('Meta attribution is Meta itself (no attribution in the style)', () {
      expect(metaMapAttributionText, '© Meta');
    });
  });

  group('cartoFallbackStyleJson', () {
    test('dark is a valid MapLibre raster style for Dark Matter', () {
      final decoded = jsonDecode(cartoFallbackStyleJson(dark: true))
          as Map<String, dynamic>;
      expect(decoded['version'], 8);
      expect(decoded['name'], contains('Dark Matter'));
      final sources = decoded['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['carto-dark']);
      final source = sources['carto-dark'] as Map<String, dynamic>;
      expect(source['type'], 'raster');
      expect(
        source['attribution'],
        '© OpenStreetMap contributors © CARTO',
      );
      final tiles = source['tiles'] as List;
      expect(tiles.single, contains('basemaps.cartocdn.com/dark_all'));
      // No flutter_map {r} placeholder: MapLibre only expands {z}/{x}/{y}.
      expect(tiles.single, isNot(contains('{r}')));
      final layers = decoded['layers'] as List;
      expect(layers.length, 1);
      expect((layers.single as Map)['type'], 'raster');
      expect((layers.single as Map)['source'], 'carto-dark');
    });

    test('light is a valid MapLibre raster style for Positron', () {
      final decoded = jsonDecode(cartoFallbackStyleJson(dark: false))
          as Map<String, dynamic>;
      expect(decoded['version'], 8);
      expect(decoded['name'], contains('Positron'));
      final sources = decoded['sources'] as Map<String, dynamic>;
      expect(sources.keys, ['carto-light']);
      final source = sources['carto-light'] as Map<String, dynamic>;
      expect(source['type'], 'raster');
      expect(source['attribution'], '© OpenStreetMap contributors');
      final tiles = source['tiles'] as List;
      expect(tiles.single, contains('basemaps.cartocdn.com/light_all'));
      expect(tiles.single, isNot(contains('{r}')));
      final layers = decoded['layers'] as List;
      expect(layers.length, 1);
      expect((layers.single as Map)['type'], 'raster');
      expect((layers.single as Map)['source'], 'carto-light');
    });
  });

  group('metaVectorTileUrl / metaTileXy', () {
    test('tile URL follows the Meta vtp endpoint', () {
      expect(
        metaVectorTileUrl(z: 8, x: 213, y: 115),
        'https://external.xx.fbcdn.net/maps/vtp/s1/88/8/213/115/',
      );
      expect(
        metaVectorTileUrlTemplate,
        contains('external.xx.fbcdn.net/maps/vtp/s1/88'),
      );
    });

    test('tile coordinates cover Cabugao at zoom 8', () {
      // Cabugao (17.78916, 120.45838) at zoom 8 sits in tile 213/115.
      final tile = metaTileXy(lat: 17.78916, lng: 120.45838, z: 8);
      expect(tile.x, 213);
      expect(tile.y, 115);
    });

    test('zoom clamps to the Meta tiles range (0–16)', () {
      final hi = metaTileXy(lat: 16.9, lng: 121.05, z: 20);
      final at16 = metaTileXy(lat: 16.9, lng: 121.05, z: 16);
      expect(hi, at16);
      final lo = metaTileXy(lat: 16.9, lng: 121.05, z: -3);
      final at0 = metaTileXy(lat: 16.9, lng: 121.05, z: 0);
      expect(lo, at0);
    });
  });

  group('cartoTileUrl', () {
    test('dark and light tile URLs follow the CartoDB endpoints', () {
      expect(
        cartoTileUrl(dark: true, z: 8, x: 213, y: 115),
        'https://basemaps.cartocdn.com/dark_all/8/213/115.png',
      );
      expect(
        cartoTileUrl(dark: false, z: 8, x: 213, y: 115),
        'https://basemaps.cartocdn.com/light_all/8/213/115.png',
      );
    });

    test('fallback style JSON uses the same tile URLs', () {
      // The style document's tile template and the probe URL
      // must stay consistent, or the probe would validate a
      // different source than the map renders.
      final dark = jsonDecode(cartoFallbackStyleJson(dark: true))
          as Map<String, dynamic>;
      final darkSources = dark['sources'] as Map<String, dynamic>;
      final darkSource = darkSources['carto-dark'] as Map<String, dynamic>;
      expect(
        (darkSource['tiles'] as List).single,
        'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      );
      final light = jsonDecode(cartoFallbackStyleJson(dark: false))
          as Map<String, dynamic>;
      final lightSources = light['sources'] as Map<String, dynamic>;
      final lightSource = lightSources['carto-light'] as Map<String, dynamic>;
      expect(
        (lightSource['tiles'] as List).single,
        'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
      );
    });
  });

  group('distanceAlongPath / nearestPathIndex', () {
    test('sums segments between indices', () {
      final pts = [
        const LatLng(17.78916, 120.45838),
        const LatLng(17.73979, 120.45719),
        const LatLng(17.56641, 120.38590),
      ];
      final leg = distanceAlongPath(pts, 0, 1);
      expect(leg, greaterThan(4));
      expect(distanceAlongPath(pts, 0, 2), greaterThan(leg));
      expect(distanceAlongPath(pts, 1, 1), 0);
      expect(
        nearestPathIndex(pts, const LatLng(17.74, 120.457)),
        1,
      );
    });
  });
}
