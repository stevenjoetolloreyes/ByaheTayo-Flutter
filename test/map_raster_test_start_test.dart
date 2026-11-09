// Tests for the Nov 9, 2026 raster diagnostic (Huawei P30 Lite
// blank map): the Map tab starts on the CartoDB raster basemap
// instead of Meta's Canterbury vector style, so we can tell
// whether raster tiles render where vector does not.
//
// Pure decision tests (no native map view — it cannot render in
// flutter test) plus widget tests for what the tab shows on its
// first build: no failure banner, and OSM + CARTO attribution
// from the start.
import 'dart:convert';

import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/osm_routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpMap(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => faresMapJump.value = null);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: MapTab())),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('raster diagnostic flag', () {
    test('the flag is ON while the diagnostic is live', () {
      expect(kMapStartsOnRaster, isTrue);
    });
  });

  group('mapStartStyle', () {
    test('starts on the CartoDB raster style in dark theme', () {
      final style = mapStartStyle(dark: true);
      expect(style, cartoFallbackStyleJson(dark: true));
      expect(style, contains('basemaps.cartocdn.com/dark_all'));
      expect(style, isNot(contains('fbcdn')));
    });

    test('starts on the CartoDB raster style in light theme', () {
      final style = mapStartStyle(dark: false);
      expect(style, cartoFallbackStyleJson(dark: false));
      expect(style, contains('basemaps.cartocdn.com/light_all'));
      expect(style, isNot(contains('fbcdn')));
    });

    test('a theme change stays on raster in both themes', () {
      // A theme switch must swap the raster variant only, never
      // jump back to Meta, or the test would silently re-test
      // the vector style and confuse the result.
      for (final dark in [true, false]) {
        final style = mapStartStyle(dark: dark);
        expect(style, contains('basemaps.cartocdn.com'));
        expect(style, isNot(contains('fbcdn')));
      }
    });

    test('with the flag off, the start style is Meta again', () {
      expect(
        mapStartStyle(dark: true, startsOnRaster: false),
        metaDarkMapStyleUrl,
      );
      expect(
        mapStartStyle(dark: false, startsOnRaster: false),
        metaLightMapStyleUrl,
      );
    });

    test('the raster style fetches the tiles the probe checks', () {
      // The banner's failure path is the Carto tile probe, so the
      // style under test must fetch its tiles from the same
      // endpoint the probe fetches — otherwise a failed probe
      // would not prove the style's tiles failed.
      final decoded =
          jsonDecode(mapStartStyle(dark: true)) as Map<String, dynamic>;
      final sources = decoded['sources'] as Map<String, dynamic>;
      final darkSource = sources['carto-dark'] as Map<String, dynamic>;
      final tiles = darkSource['tiles'] as List<dynamic>;
      expect(tiles, [cartoDarkRasterTileUrl]);
      expect(
        cartoTileUrl(dark: true, z: 8, x: 200, y: 120),
        'https://basemaps.cartocdn.com/dark_all/8/200/120.png',
      );
    });
  });

  group('mapRetryTarget', () {
    test('Retry re-attempts the raster style while the flag is on',
        () {
      final darkRetry = mapRetryTarget(dark: true);
      expect(darkRetry.isRaster, isTrue);
      expect(darkRetry.style, cartoFallbackStyleJson(dark: true));

      final lightRetry = mapRetryTarget(dark: false);
      expect(lightRetry.isRaster, isTrue);
      expect(lightRetry.style, cartoFallbackStyleJson(dark: false));
    });

    test('Retry goes back to Meta with the flag off', () {
      final retry = mapRetryTarget(dark: true, startsOnRaster: false);
      expect(retry.isRaster, isFalse);
      expect(retry.style, metaDarkMapStyleUrl);
    });
  });

  group('MapTab widget (raster start)', () {
    testWidgets('no "couldn\'t load" banner at startup', (tester) async {
      await _pumpMap(tester);
      expect(find.text("Couldn't load the map"), findsNothing);
    });

    testWidgets('attribution is OSM + CARTO from the first build',
        (tester) async {
      await _pumpMap(tester);
      // The attribution chip only shows while the sheet is hidden;
      // the logo toggle hides it without losing any state.
      await tester.tap(find.byTooltip('Hide bottom panel'));
      await tester.pumpAndSettle();
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.text('© Meta'), findsNothing);
    });
  });
}
