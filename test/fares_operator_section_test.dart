// Tests for the Fares tab "Posted operator fares" reference section:
// grouping of the verified operator_fares dataset by operator, the
// per-operator source notes, and the section rendering in the tab.
// Dataset counts themselves are covered by operator_fares_test.dart;
// these tests cover only the new wiring (grouping + notes + UI).
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/operator_fares.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupOperatorFares', () {
    test('full dataset groups in order with exact counts, lossless', () {
      final groups = groupOperatorFares();
      expect(
        groups.map((g) => g.company).toList(),
        ['Partas', 'Victory Liner', 'JAC Liner', 'ALPS The Bus', 'Bicol Isarog'],
      );
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
      final partas =
          groupOperatorFares().firstWhere((g) => g.company == 'Partas');
      final viganDeluxe = partas.fares.firstWhere(
        (f) =>
            f.origin == 'Cubao' &&
            f.destination == 'Vigan City / Bangued, Abra' &&
            f.fareClass == 'Deluxe',
      );
      expect(viganDeluxe.fare, 1066);
      final victory =
          groupOperatorFares().firstWhere((g) => g.company == 'Victory Liner');
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
      expect(
        groups.last.sourceNote,
        'Officially posted by the operator.',
      );
    });

    test('empty input groups to nothing', () {
      expect(groupOperatorFares([]), isEmpty);
    });
  });

  group('operatorFareSourceNote', () {
    test('Partas note carries the drop-off caveat', () {
      expect(
        operatorFareSourceNote('Partas'),
        contains('Oct 9, 2026'),
      );
      expect(
        operatorFareSourceNote('Partas'),
        contains('drop-off point'),
      );
    });

    test('Bicol Isarog note keeps the comment-reply caveat', () {
      expect(
        operatorFareSourceNote('Bicol Isarog'),
        contains('comment replies'),
      );
      expect(
        operatorFareSourceNote('Bicol Isarog'),
        contains('Aug 26, 2026'),
      );
    });

    test('every grouped operator has a non-empty note with a date', () {
      for (final group in groupOperatorFares()) {
        expect(group.sourceNote, isNotEmpty);
        expect(group.sourceNote, contains('2026'));
      }
    });
  });

  testWidgets('Fares tab shows the posted-fares section and expands Partas',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FaresTab())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Posted operator fares'), findsOneWidget);
    expect(find.text('Partas · 46 fares'), findsOneWidget);
    expect(find.text('Victory Liner · 6 fares'), findsOneWidget);
    expect(find.text('Bicol Isarog · 2 fares'), findsOneWidget);
    // Rows stay hidden until their group is expanded.
    expect(find.text('Cubao → Vigan City / Bangued, Abra'), findsNothing);
    await tester.ensureVisible(find.text('Partas · 46 fares'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partas · 46 fares'));
    await tester.pumpAndSettle();
    expect(
      find.text('Cubao → Vigan City / Bangued, Abra'),
      findsWidgets,
    );
    expect(find.text('₱1,066'), findsOneWidget);
    expect(find.text('Deluxe'), findsWidgets);
  });
}
