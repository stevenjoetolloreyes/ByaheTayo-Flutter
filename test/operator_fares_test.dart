import 'package:estudyantego/features/operator_fares.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dataset holds 46 Partas + 6 Victory + 9 JAC + 1 ALPS + 2 Isarog',
      () {
    expect(operatorFares.length, 64);
    expect(operatorFaresFor('Partas').length, 46);
    expect(operatorFaresFor('Victory Liner').length, 6);
    expect(operatorFaresFor('JAC Liner').length, 9);
    expect(operatorFaresFor('ALPS The Bus').length, 1);
    expect(operatorFaresFor('Bicol Isarog').length, 2);
    expect(operatorFaresFor('GV Florida Transport'), isEmpty);
    // Cagsawa's range-only fare is verified research, not a seed.
    expect(operatorFaresFor('Cagsawa Travel and Tours'), isEmpty);
    // Every entry carries its official source and post date.
    for (final fare in operatorFares) {
      expect(fare.fare, greaterThan(0));
      expect(fare.sourceUrl, isNotEmpty);
      expect(fare.postedDate, isNotEmpty);
      expect(fare.company, isNotEmpty);
    }
  });

  test('Partas spot checks match the Oct 9, 2026 official post', () {
    expect(
      findOperatorFare('Partas', 'Cubao', 'Vigan City / Bangued, Abra',
          fareClass: 'Deluxe')
          ?.fare,
      1066,
    );
    expect(
      findOperatorFare('Partas', 'Cubao', 'Laoag City', fareClass: 'Deluxe')
          ?.fare,
      1274,
    );
    expect(
      findOperatorFare('Partas', 'Pasay', 'Vigan City / Bangued, Abra',
          fareClass: 'Super Deluxe')
          ?.fare,
      1148,
    );
    expect(
      findOperatorFare('Partas', 'Pasay', 'Pagudpud',
          fareClass: 'Super Deluxe')
          ?.fare,
      1553,
    );
    expect(
      findOperatorFare('Partas', 'PITX', 'Laoag City',
          fareClass: 'Super Deluxe')
          ?.fare,
      1377,
    );
  });

  test('unreadable Partas Pagudpud numbers are absent, never guessed', () {
    expect(
      findOperatorFare('Partas', 'Cubao', 'Pagudpud', fareClass: 'Luxury'),
      isNull,
    );
    expect(
      findOperatorFare('Partas', 'Pasay', 'Pagudpud', fareClass: 'Luxury'),
      isNull,
    );
    expect(
      findOperatorFare('Partas', 'PITX', 'Pagudpud',
          fareClass: 'Super Deluxe'),
      isNull,
    );
  });

  test('Victory Liner official fares resolve', () {
    expect(
      findOperatorFare('Victory Liner', 'Pasay', 'Baguio',
          fareClass: 'Royal Class')
          ?.fare,
      1546,
    );
    expect(
      findOperatorFare('Victory Liner', 'Cubao', 'Baguio',
          fareClass: 'Royal Class')
          ?.fare,
      1546,
    );
    // San Fernando here is PAMPANGA (ElectricBus), not La Union.
    expect(
      findOperatorFare('Victory Liner', 'Cubao', 'San Fernando, Pampanga',
          fareClass: 'ElectricBus')
          ?.fare,
      158,
    );
    expect(
      findOperatorFare('Victory Liner', 'San Fernando, Pampanga', 'Cubao',
          fareClass: 'ElectricBus')
          ?.fare,
      158,
    );
  });

  test('JAC, ALPS, and Bicol Isarog spot checks resolve', () {
    expect(
      findOperatorFare('JAC Liner', 'Kamias', 'Dalahican / Lucena Grand',
          fareClass: 'P2P')
          ?.fare,
      420,
    );
    expect(
      findOperatorFare('JAC Liner', 'Kamias', 'Dalahican / Lucena Grand',
          fareClass: 'Regular')
          ?.fare,
      356,
    );
    expect(
      findOperatorFare('JAC Liner', 'Kamias', 'Sariaya, Quezon',
          fareClass: 'Regular')
          ?.fare,
      324,
    );
    expect(
      findOperatorFare('ALPS The Bus', 'PITX', 'Sorsogon / Gubat',
          fareClass: 'Sleeper Bus Master Class')
          ?.fare,
      2300,
    );
    expect(
      findOperatorFare('Bicol Isarog', 'Cubao', 'Cumadcad, Sorsogon',
          fareClass: 'Ultimate Sleeper')
          ?.fare,
      2700,
    );
    expect(
      findOperatorFare('Bicol Isarog', 'EDSA', 'Masbate',
          fareClass: 'Regular Sleeper')
          ?.fare,
      2850,
    );
  });

  test('lookup misses and class mismatches return null', () {
    expect(findOperatorFare('Partas', 'Cubao', 'Tuguegarao'), isNull);
    expect(findOperatorFare('GV Florida Transport', 'Cubao', 'Laoag City'),
        isNull);
    expect(
      findOperatorFare('Partas', 'Cubao', 'Vigan City / Bangued, Abra',
          fareClass: 'Royal Class'),
      isNull,
    );
    // Case-insensitive matching still works.
    expect(
      findOperatorFare('partas', 'cubao', 'laoag city',
          fareClass: 'deluxe')
          ?.fare,
      1274,
    );
  });
}
