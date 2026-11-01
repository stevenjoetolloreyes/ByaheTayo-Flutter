// Tests for the Fares tab: formula, distance, peso format, and the
// tab rendering + computing from a typed distance.
import 'package:estudyantego/features/fares_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FareRate rate(String id) => fareRates.firstWhere((r) => r.id == id);

void main() {
  group('computeFare', () {
    test('traditional jeepney: base covers the first 4 km', () {
      expect(computeFare(rate('trad-jeep'), 4.0, false).collected, 14);
      expect(computeFare(rate('trad-jeep'), 3.0, false).collected, 14);
    });
    test('traditional jeepney: 5 km and 10 km', () {
      expect(computeFare(rate('trad-jeep'), 5.0, false).collected, 16);
      expect(computeFare(rate('trad-jeep'), 10.0, false).collected, 26);
    });
    test('discounted fare rounds to the nearest ₱0.25', () {
      // 26 * 0.8 = 20.80 -> nearest ₱0.25 = 20.75.
      expect(computeFare(rate('trad-jeep'), 10.0, true).collected, 20.75);
      expect(computeFare(rate('trad-jeep'), 10.0, true).regular, 26);
    });
    test('provincial bus minimum beats the formula', () {
      expect(computeFare(rate('prov-ordinary'), 5.0, false).collected, 100);
    });
    test('city bus minimum beats the formula', () {
      expect(computeFare(rate('city-ordinary'), 5.0, false).collected, 20);
    });
    test('Dagupan shared tricycle', () {
      expect(computeFare(rate('dagupan-shared'), 2.0, false).collected, 20);
      expect(computeFare(rate('dagupan-shared'), 3.0, false).collected, 30);
    });
  });

  group('haversineKm', () {
    test('same point is zero', () {
      expect(haversineKm(17.56, 120.38, 17.56, 120.38), 0);
    });
    test('Vigan to Cabugao is a plausible short hop', () {
      final d = haversineKm(17.56138, 120.38564, 17.78916, 120.45838);
      expect(d, greaterThan(20));
      expect(d, lessThan(35));
    });
  });

  group('peso', () {
    test('no decimals for whole amounts, separators for thousands', () {
      expect(peso(26), '₱26');
      expect(peso(1250), '₱1,250');
    });
    test('two decimals only when fractional', () {
      expect(peso(20.75), '₱20.75');
    });
  });

  testWidgets('Fares tab auto-computes hub-to-hub distance', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FaresTab())),
    );
    expect(find.text('Traditional jeepney'), findsOneWidget);
    // No distance yet: the guidance state shows.
    expect(find.textContaining('Starting location needed'),
        findsOneWidget);
    // Switch to hub origin: Cabugao -> Vigan City auto-computes
    // (no manual distance field anymore).
    await tester.tap(find.text('Choose a hub'));
    await tester.pump();
    expect(find.text('32.3 km'), findsOneWidget);
    expect(find.textContaining('₱72'), findsWidgets);
  });
}
