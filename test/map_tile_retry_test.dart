// Map tile retry bundle (Steven, Nov 7, 22:10 — blank map, no
// banner, no Retry): the one-shot probe passed on a single
// small rural tile, the watchdog was cancelled, and the app sat
// in a terminal "believes the map is fine" state while the
// viewport tiles never arrived. The fix hardens the probe
// (centre + neighbours, route midpoint), re-validates on
// returning to the tab, adds an always-available Reload button,
// and bounds the OSRM body read. MapLibre cannot render in
// flutter test, so these tests cover the pure helpers the fix
// is built from — the neighbour math and the probe-centre
// choice. The probe HTTP calls and the widget placement are
// verified by analyze + the on-device check, not here.
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('metaTileNeighbours', () {
    test('centre + east + south for Cabugao at zoom 8', () {
      // Cabugao (17.78916, 120.45838) at zoom 8 sits in tile
      // 213/115 (pinned by osm_routing_test).
      final tiles = metaTileNeighbours(
        lat: 17.78916,
        lng: 120.45838,
        z: 8,
      );
      expect(tiles.length, 3);
      expect(tiles[0], (x: 213, y: 115));
      expect(tiles[1], (x: 214, y: 115));
      expect(tiles[2], (x: 213, y: 116));
    });

    test('all three tiles are distinct', () {
      final tiles = metaTileNeighbours(
        lat: 17.78916,
        lng: 120.45838,
        z: 8,
      );
      expect(tiles.toSet().length, 3);
    });

    test('east wraps at the antimeridian', () {
      // lng 179.9 at zoom 2 (n = 4) is the last column (x = 3),
      // so the east neighbour wraps to column 0.
      final tiles = metaTileNeighbours(lat: 17.0, lng: 179.9, z: 2);
      expect(tiles[0].x, 3);
      expect(tiles[1], (x: 0, y: tiles[0].y));
    });

    test('south clamps at the bottom row', () {
      // lat -85 at zoom 2 (n = 4) is the bottom row (y = 3);
      // there is no tile below it.
      final tiles = metaTileNeighbours(lat: -85.0, lng: 0.0, z: 2);
      expect(tiles[0].y, 3);
      expect(tiles[2], (x: tiles[0].x, y: 3));
    });

    test('zoom clamps to the Meta tiles range (0–16)', () {
      final hi = metaTileNeighbours(lat: 16.9, lng: 121.05, z: 20);
      final at16 = metaTileNeighbours(lat: 16.9, lng: 121.05, z: 16);
      expect(hi, at16);
      // At zoom 0 there is a single tile: all three are (0, 0).
      final lo = metaTileNeighbours(lat: 16.9, lng: 121.05, z: -3);
      expect(lo, [
        (x: 0, y: 0),
        (x: 0, y: 0),
        (x: 0, y: 0),
      ]);
    });
  });

  group('mapProbeCenter', () {
    const cabugao = LatLng(17.78916, 120.45838);
    const viganTerminal = Hub(
      'Vigan Bus Terminal',
      'Ilocos Sur',
      17.56641,
      120.38590,
    );
    const camera = LatLng(16.9, 121.05);

    test('route midpoint when origin + destination are known', () {
      // Midpoint of Cabugao → Vigan Bus Terminal: on the route
      // corridor, not the init centre in central Luzon.
      final centre = mapProbeCenter(
        origin: cabugao,
        dest: viganTerminal,
        currentCenter: camera,
      );
      expect(centre.latitude, closeTo(17.677785, 1e-6));
      expect(centre.longitude, closeTo(120.42214, 1e-6));
    });

    test('falls back to the camera centre without a route', () {
      expect(
        mapProbeCenter(currentCenter: camera),
        camera,
      );
      expect(
        mapProbeCenter(origin: cabugao, currentCenter: camera),
        camera,
      );
      expect(
        mapProbeCenter(dest: viganTerminal, currentCenter: camera),
        camera,
      );
    });
  });

  group('mapTabBecameVisible', () {
    test('fires on a false → true transition (returning to the tab)', () {
      // The re-validate exists for exactly this case: the user
      // comes back to the Map tab and the tiles are re-checked.
      expect(
        mapTabBecameVisible(oldVisible: false, visible: true),
        isTrue,
      );
    });

    test('does NOT fire on a parent rebuild while already visible', () {
      // The old guard was inverted here: it returned on the
      // return transition and ran the body on rebuilds while
      // visible. A rebuild must not re-probe.
      expect(
        mapTabBecameVisible(oldVisible: true, visible: true),
        isFalse,
      );
    });

    test('does NOT fire while the tab stays hidden', () {
      expect(
        mapTabBecameVisible(oldVisible: false, visible: false),
        isFalse,
      );
    });

    test('does NOT fire when leaving the tab', () {
      expect(
        mapTabBecameVisible(oldVisible: true, visible: false),
        isFalse,
      );
    });
  });
}
