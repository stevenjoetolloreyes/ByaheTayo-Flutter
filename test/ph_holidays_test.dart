// Tests for the Philippine holiday list + school-day kinds
// (Proclamation No. 1006 for 2026, plus the Eid proclamations).
import 'package:estudyantego/features/ph_holidays.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('philippineHolidayName (2026)', () {
    test('regular holidays', () {
      expect(philippineHolidayName(DateTime(2026, 1, 1)), "New Year's Day");
      expect(philippineHolidayName(DateTime(2026, 4, 2)), 'Maundy Thursday');
      expect(philippineHolidayName(DateTime(2026, 4, 3)), 'Good Friday');
      expect(
        philippineHolidayName(DateTime(2026, 11, 30)),
        'Bonifacio Day',
      );
      expect(philippineHolidayName(DateTime(2026, 12, 25)), 'Christmas Day');
    });

    test('special non-working days', () {
      expect(
        philippineHolidayName(DateTime(2026, 11, 1)),
        "All Saints' Day",
      );
      expect(
        philippineHolidayName(DateTime(2026, 11, 2)),
        "All Souls' Day",
      );
      expect(
        philippineHolidayName(DateTime(2026, 2, 17)),
        'Chinese New Year',
      );
      expect(philippineHolidayName(DateTime(2026, 12, 24)), 'Christmas Eve');
    });

    test("Eid holidays from the later proclamations", () {
      expect(philippineHolidayName(DateTime(2026, 3, 20)), "Eid'l Fitr");
      expect(philippineHolidayName(DateTime(2026, 5, 27)), "Eid'l Adha");
    });

    test('ordinary days are not holidays', () {
      expect(philippineHolidayName(DateTime(2026, 11, 3)), isNull);
      expect(philippineHolidayName(DateTime(2026, 11, 5)), isNull);
    });

    test('special working day is NOT a holiday', () {
      expect(philippineHolidayName(DateTime(2026, 2, 25)), isNull);
    });

    test('NCR-only days are NOT nationwide holidays', () {
      expect(philippineHolidayName(DateTime(2026, 11, 16)), isNull);
      expect(philippineHolidayName(DateTime(2026, 11, 17)), isNull);
      expect(philippineHolidayName(DateTime(2026, 11, 18)), isNull);
    });

    test('other years have no data yet (never guessed)', () {
      expect(philippineHolidayName(DateTime(2025, 11, 1)), isNull);
      expect(philippineHolidayName(DateTime(2027, 11, 1)), isNull);
    });
  });

  group('schoolDayKind', () {
    test('holiday beats weekend (Nov 1 2026 is a Sunday holiday)', () {
      expect(schoolDayKind(DateTime(2026, 11, 1)), SchoolDayKind.holiday);
    });

    test('weekday holiday is a holiday, not a school day', () {
      expect(schoolDayKind(DateTime(2026, 11, 2)), SchoolDayKind.holiday);
    });

    test('ordinary weekday is a school day', () {
      expect(schoolDayKind(DateTime(2026, 11, 3)), SchoolDayKind.schoolDay);
    });

    test('Saturday is a weekend', () {
      expect(schoolDayKind(DateTime(2026, 11, 7)), SchoolDayKind.weekend);
    });

    test('EDSA working day counts as a school day', () {
      expect(schoolDayKind(DateTime(2026, 2, 25)), SchoolDayKind.schoolDay);
    });
  });

  group('philippineHolidaysInMonth', () {
    test('November 2026 has three holidays in order', () {
      final list = philippineHolidaysInMonth(2026, 11);
      expect(list.map((e) => e.day).toList(), [1, 2, 30]);
      expect(
        list.map((e) => e.name).toList(),
        ["All Saints' Day", "All Souls' Day", 'Bonifacio Day'],
      );
    });

    test('a month without holidays is empty', () {
      expect(philippineHolidaysInMonth(2026, 10), isEmpty);
    });
  });
}
