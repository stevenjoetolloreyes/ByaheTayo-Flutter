// Unit tests for the Map tab's 2D / 3D / Satellite view modes.
// Pure camera-parameter mapping only — no GoogleMap widget needed,
// so these run without a platform view.
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('2D mode is flat top-down standard tiles', () {
    expect(mapTypeForMode(MapViewMode.standard2d), MapType.normal);
    expect(tiltForMode(MapViewMode.standard2d), 0);
    expect(bearingForMode(MapViewMode.standard2d, 90), 0);
    expect(buildingsForMode(MapViewMode.standard2d), isFalse);
  });

  test('3D mode is tilted perspective with buildings, keeps bearing', () {
    expect(mapTypeForMode(MapViewMode.perspective3d), MapType.normal);
    expect(tiltForMode(MapViewMode.perspective3d), 60);
    expect(bearingForMode(MapViewMode.perspective3d, 90), 90);
    expect(buildingsForMode(MapViewMode.perspective3d), isTrue);
  });

  test('Satellite mode is aerial imagery with road labels, flat north-up',
      () {
    expect(mapTypeForMode(MapViewMode.satellite), MapType.satellite);
    expect(tiltForMode(MapViewMode.satellite), 0);
    expect(bearingForMode(MapViewMode.satellite, 90), 0);
    expect(buildingsForMode(MapViewMode.satellite), isFalse);
  });

  test('cameraForMode builds the per-mode camera position', () {
    const target = LatLng(17.79, 120.45);
    final perspective = cameraForMode(
      mode: MapViewMode.perspective3d,
      target: target,
      zoom: 17,
      bearing: 45,
    );
    expect(perspective.tilt, 60);
    expect(perspective.bearing, 45);
    expect(perspective.zoom, 17);
    expect(perspective.target, target);

    final flat = cameraForMode(
      mode: MapViewMode.standard2d,
      target: target,
      zoom: 15,
      bearing: 45,
    );
    expect(flat.tilt, 0);
    expect(flat.bearing, 0);
  });

  test('switching modes only re-derives camera params, never route data',
      () {
    // Guard for the preservation contract: the mode helpers take no
    // route/marker/polyline input and return camera params only, so
    // a mode switch cannot clear or rewrite route state by itself.
    const target = LatLng(17.79, 120.45);
    for (final mode in MapViewMode.values) {
      final cam = cameraForMode(mode: mode, target: target, zoom: 15);
      expect(cam.target, target);
      expect(cam.zoom, 15);
    }
  });
}
