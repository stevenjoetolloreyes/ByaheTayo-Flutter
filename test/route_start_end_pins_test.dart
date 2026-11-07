// Start → End pins (Steven, Nov 7, 19:39: "dapat may pin ako
// Start to End"). His 19:36 screenshot showed only pins 2 and 4
// near Cabugao: the Start pin (1, Cabugao) was hidden UNDER
// Point 1 (a saved waypoint tapped almost exactly on the
// origin), and the End pin (5, Vigan Bus Terminal) was
// off-screen — the route fit used EdgeInsets.all(80) against
// the FULL viewport, so with the sheet at Half (0.55) the
// route's southern end landed behind the sheet.
//
// The pins themselves always rendered (routeStopPins covers
// every stop); the fix is visibility, not rendering:
// (1) orderStopPinsForMarkers paints Start + End LAST (on top),
// (2) routeFitPadding clears the sheet so the fit lands in the
// visible area above it. The camera fit itself cannot render
// in flutter test — these tests cover the pure helpers the fit
// and the marker paint order are built from.
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<MapStopPin> _pins(List<int> numbers) => [
  for (final n in numbers)
    MapStopPin(number: n, lat: 17.0 + n * 0.01, lng: 120.4, selected: false),
];

void main() {
  group('orderStopPinsForMarkers', () {
    test('Start and End paint last, intermediates keep order', () {
      final ordered = orderStopPinsForMarkers(_pins([1, 2, 3, 4, 5]));
      expect(
        ordered.map((p) => p.number),
        [2, 3, 4, 1, 5],
      );
    });

    test('two or fewer pins keep their order', () {
      expect(orderStopPinsForMarkers(_pins([1, 2])).map((p) => p.number), [
        1,
        2,
      ]);
      expect(orderStopPinsForMarkers(_pins([1])).map((p) => p.number), [1]);
      expect(orderStopPinsForMarkers(const []), isEmpty);
    });

    test('a waypoint on the origin no longer hides the Start pin', () {
      // Steven's Cabugao → Vigan stops: 1 Cabugao (Start),
      // 2 Point 1 (saved waypoint, ~on the origin), 3 Point 2,
      // 4 San Juan, 5 Vigan Terminal (End). Point 1 paints
      // BEFORE the Start pin, so the Start pin is on top.
      final ordered = orderStopPinsForMarkers(_pins([1, 2, 3, 4, 5]));
      final startIndex = ordered.indexWhere((p) => p.number == 1);
      final point1Index = ordered.indexWhere((p) => p.number == 2);
      expect(startIndex, greaterThan(point1Index));
      expect(ordered.last.number, 5); // End on the very top
    });
  });

  group('routeFitPadding', () {
    test('bottom inset clears the sheet; sides stay 80', () {
      const screenHeight = 1520.0; // Steven's phone, approx.
      final peek = routeFitPadding(
        screenHeight: screenHeight,
        sheetFraction: 0.20,
      );
      expect(peek.left, 80);
      expect(peek.top, 80);
      expect(peek.right, 80);
      expect(peek.bottom, 80 + screenHeight * 0.20);

      final half = routeFitPadding(
        screenHeight: screenHeight,
        sheetFraction: 0.55,
      );
      expect(half.bottom, 80 + screenHeight * 0.55);
      // Half covers far more of the screen than Peek.
      expect(half.bottom, greaterThan(peek.bottom));
    });

    test('no sheet means the old all-80 fit', () {
      final padding = routeFitPadding(
        screenHeight: 1520,
        sheetFraction: 0,
      );
      expect(padding, const EdgeInsets.all(80));
    });
  });

  group('Laoag Terminal to Vigan jump resolves', () {
    test('routesFrom generates Laoag Terminal to Vigan Bus Terminal', () {
      // Steven's 19:36 question ("bakit stay nalang sya sa
      // Cabugao to Vigan?") was NOT a routing failure: the
      // generated hub routes include this pair, so the Fares
      // "Find routes" jump resolves it — the Trip card
      // dropdowns alone never retarget the Map tab (the jump
      // only fires on Find routes / Show direction on Map).
      final routes = routesFrom(
        18.1958, // Laoag Terminal
        120.59062,
        'Laoag Terminal',
      );
      final match = routes.where(
        (r) => r.dest.name == 'Vigan Bus Terminal',
      );
      expect(match, isNotEmpty);
      expect(match.first.originName, 'Laoag Terminal');
      expect(match.first.dest.lat, 17.56641);
      expect(match.first.dest.lng, 120.38590);
    });
  });
}
