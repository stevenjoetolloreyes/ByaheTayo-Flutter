// Tests for the Map tab's 3D buildings extrusion layer.
// Pure layer-definition checks only — the layer is a const
// value, so these run without a live native map (which cannot
// render in flutter test).
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';

void main() {
  test('extrusion layer uses the Meta style building source', () {
    final layer = kBuildings3dExtrusionLayer;
    expect(layer, isA<FillExtrusionStyleLayer>());
    expect(layer.id, kBuildings3dLayerId);
    expect(layer.sourceId, 'facebook');
    expect(layer.sourceLayerId, 'buildings');
    // Same zoom window as the style's flat building fills, so
    // buildings only extrude when zoomed in (minzoom 16).
    expect(layer.minZoom, 16);
    expect(layer.maxZoom, 24);
    expect(layer.layout['visibility'], 'visible');
  });

  test('extrusion sits above the flat building fills', () {
    // The anchor is the style's flat "buildings-elevated" fill:
    // the 3D blocks sit exactly where the flat footprints sit,
    // with the style's roads, bridges and labels above them.
    expect(kBuildings3dAnchorLayerId, 'buildings-elevated');
  });

  test('height uses the real height when present, else defaults', () {
    final height = kBuildings3dExtrusionLayer.paint['fill-extrusion-height'];
    expect(height, isA<List>());
    final expr = height as List;
    // case: elevated buildings get the taller default, the rest
    // get the normal default; both read ["height"] first, and
    // real heights are floored so a 3.4 m shed still reads as a
    // 3D block (verified: tiles carry real heights, Nov 11).
    expect(expr[0], 'case');
    expect(expr[1], ['==', ['get', 'elevated'], 'yes']);
    expect(expr[2], [
      'max',
      ['to-number', ['get', 'height'], kBuildings3dElevatedHeightM],
      kBuildings3dElevatedHeightM,
    ]);
    expect(expr[3], [
      'max',
      ['to-number', ['get', 'height'], kBuildings3dDefaultHeightM],
      kBuildings3dMinHeightM,
    ]);
    expect(kBuildings3dMinHeightM, 5);
    expect(kBuildings3dDefaultHeightM, 10);
    expect(kBuildings3dElevatedHeightM, 18);
  });

  test('base, colour and opacity fit the dark map', () {
    final paint = kBuildings3dExtrusionLayer.paint;
    expect(
      paint['fill-extrusion-base'],
      ['to-number', ['get', 'min_height'], 0],
    );
    // A shade lighter than the flat building fill so the blocks
    // read against the dark basemap; sides shaded by gradient.
    expect(paint['fill-extrusion-color'], '#47657b');
    expect(paint['fill-extrusion-opacity'], 0.9);
    expect(paint['fill-extrusion-vertical-gradient'], isTrue);
  });

  test('extrusion is tied to 3D mode only', () {
    // The layer is added in 3D and removed in 2D (see
    // _syncBuildingsExtrusion); the mode helper is the switch.
    expect(buildingsForMode(MapViewMode.perspective3d), isTrue);
    expect(buildingsForMode(MapViewMode.standard2d), isFalse);
    expect(buildingsForMode(MapViewMode.satellite), isFalse);
  });
}
