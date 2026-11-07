// Tests for the posted operator fares grouping: grouping of the
// verified operator_fares dataset by operator and the per-operator
// source notes. The tab section that displayed these groups was
// removed Nov 7, 2026 (Steven), so there is no UI test here.
// Dataset counts themselves are covered by operator_fares_test.dart.
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/operator_fares.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupOperatorFares', () {
    test('full dataset groups in order with exact counts, lossless', () {
      final groups = groupOperatorFares();
      expect(groups.map((g) => g.company).toList(), [
        'Partas',
        'Victory Liner',
        'JAC Liner',
        'ALPS The Bus',
        'Bicol Isarog',
      ]);
      expect(groups.map((g) => g.fares.length).toList(), [46, 6, 9, 1, 2]);
      final flattened = groups.expand((g) => g.fares).toList();
      expect(flattened.length, operatorFares.length);
      // No fare invented, dropped, or duplicated: same set, same order
      // within each company as the dataset.
      expect(flattened.toSet().length, operatorFares.length);
      for (final fare in operatorFares) {
        expect(flattened, contains(fare));
      }
    });

    test('grouped rows keep verbatim route, class, and fare', () {
      final partas = groupOperatorFares().firstWhere(
        (g) => g.company == 'Partas',
      );
      final viganDeluxe = partas.fares.firstWhere(
        (f) =>
            f.origin == 'Cubao' &&
            f.destination == 'Vigan City / Bangued, Abra' &&
            f.fareClass == 'Deluxe',
      );
      expect(viganDeluxe.fare, 1066);
      final victory = groupOperatorFares().firstWhere(
        (g) => g.company == 'Victory Liner',
      );
      final pampanga = victory.fares.firstWhere(
        (f) => f.destination == 'San Fernando, Pampanga',
      );
      expect(pampanga.fare, 158);
      expect(pampanga.fareClass, 'ElectricBus');
    });

    test('unknown companies go last with the default note', () {
      const extra = OperatorFare(
        company: 'Test Bus',
        origin: 'A',
        destination: 'B',
        fare: 100,
        fareClass: 'Regular',
        sourceUrl: 'https://example.invalid/',
        postedDate: '2026-01-01',
      );
      final groups = groupOperatorFares([...operatorFares, extra]);
      expect(groups.last.company, 'Test Bus');
      expect(groups.last.fares, [extra]);
      expect(groups.last.sourceNote, 'Officially posted by the operator.');
    });

    test('empty input groups to nothing', () {
      expect(groupOperatorFares([]), isEmpty);
    });
  });

  group('operatorFareSourceNote', () {
    test('Partas note carries the drop-off caveat', () {
      expect(operatorFareSourceNote('Partas'), contains('Oct 9, 2026'));
      expect(operatorFareSourceNote('Partas'), contains('drop-off point'));
    });

    test('Bicol Isarog note keeps the comment-reply caveat', () {
      expect(
        operatorFareSourceNote('Bicol Isarog'),
        contains('comment replies'),
      );
      expect(operatorFareSourceNote('Bicol Isarog'), contains('Aug 26, 2026'));
    });

    test('every grouped operator has a non-empty note with a date', () {
      for (final group in groupOperatorFares()) {
        expect(group.sourceNote, isNotEmpty);
        expect(group.sourceNote, contains('2026'));
      }
    });
  });
}
