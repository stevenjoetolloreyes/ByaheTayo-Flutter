// Unit tests for the School Calendar data layer
// (lib/features/student/custom_school_days.dart): the scan parser,
// the effective-days resolution (holidays + overrides + custom
// days), and the draft -> persist translation the Edit page uses.
import 'package:estudyantego/features/student/custom_school_days.dart';
import 'package:estudyantego/features/student/student_data.dart'
    show dateKey;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSchoolDaysText', () {
    test('named dates with a year', () {
      final found = parseSchoolDaysText(
        'Christmas Break begins December 19, 2026\n'
        'Foundation Day November 20, 2026',
      );
      expect(found.map((d) => d.name), [
        'Foundation Day',
        'Christmas Break begins',
      ]);
      expect(found[0].date, DateTime(2026, 11, 20));
      expect(found[0].type, MarkedDayType.event);
      expect(found[1].date, DateTime(2026, 12, 19));
      expect(found[1].type, MarkedDayType.noClasses);
    });

    test('ISO, numeric, and day-first dates', () {
      final found = parseSchoolDaysText(
        '2026-12-08 Feast of the Immaculate Conception\n'
        '30/12/2026 Rizal Day\n'
        '1 January 2027 New Year\'s Day',
      );
      expect(found.map((d) => d.name), [
        'Feast of the Immaculate Conception',
        'Rizal Day',
        "New Year's Day",
      ]);
      expect(found[0].type, MarkedDayType.holiday);
      expect(found[1].date, DateTime(2026, 12, 30));
      expect(found[2].date, DateTime(2027, 1, 1));
    });

    test('holiday keywords win over event keywords', () {
      final found = parseSchoolDaysText(
        'December 25, 2026 Christmas Day celebration\n'
        'November 27, 2026 No classes — Faculty Day',
      );
      // Sorted by date: the November day comes first.
      expect(found[0].type, MarkedDayType.noClasses);
      expect(found[1].type, MarkedDayType.holiday);
    });

    test('header lines and dateless lines yield nothing', () {
      final found = parseSchoolDaysText(
        'MEMORANDUM\n'
        'To: All Students\n'
        'Subject: December schedule\n'
        'University of Northern Philippines\n'
        'Please be guided accordingly.',
      );
      expect(found, isEmpty);
    });

    test('a date mentioned twice keeps only the first line', () {
      final found = parseSchoolDaysText(
        'December 8, 2026 Feast of the Immaculate Conception\n'
        'December 8, 2026 is a holiday',
      );
      expect(found.length, 1);
      expect(found[0].name, 'Feast of the Immaculate Conception');
    });

    test('a bare month-day defaults to the current year', () {
      final year = DateTime.now().year;
      final found = parseSchoolDaysText('Foundation Day — Nov 20');
      expect(found.length, 1);
      expect(found[0].date, DateTime(year, 11, 20));
    });
  });

  group('effectiveMarkedDays', () {
    test('November 2026 shows the three PH holidays', () {
      final days = effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      );
      final nov = days.where((d) => d.date.month == 11).toList();
      expect(nov.map((d) => d.name), [
        "All Saints' Day",
        "All Souls' Day",
        'Bonifacio Day',
      ]);
      expect(nov.every((d) => d.type == MarkedDayType.holiday), isTrue);
      expect(nov.every((d) => d.source == MarkedDaySource.holiday), isTrue);
    });

    test('a hidden override removes the holiday', () {
      final days = effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [
          HolidayOverride(dateKey: '2026-11-30', hidden: true),
        ],
      );
      expect(
        days.where((d) => d.name == 'Bonifacio Day'),
        isEmpty,
      );
    });

    test('a rename override renames the holiday', () {
      final days = effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [
          HolidayOverride(dateKey: '2026-11-01', name: 'Undas'),
        ],
      );
      final nov1 = days.firstWhere((d) => d.date == DateTime(2026, 11, 1));
      expect(nov1.name, 'Undas');
      expect(nov1.source, MarkedDaySource.holiday);
    });

    test('a custom day joins the list in date order', () {
      final days = effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: [
          CustomSchoolDay(
            id: 'c1',
            name: 'Foundation Day',
            date: DateTime(2026, 11, 20),
            type: MarkedDayType.event,
          ),
        ],
        overrides: const [],
      );
      final nov = days.where((d) => d.date.month == 11).toList();
      expect(nov.map((d) => d.name), [
        "All Saints' Day",
        "All Souls' Day",
        'Foundation Day',
        'Bonifacio Day',
      ]);
    });
  });

  group('markedDayOn', () {
    test('a PH holiday resolves with its name and type', () {
      final entry = markedDayOn(
        DateTime(2026, 12, 25),
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      );
      expect(entry?.name, 'Christmas Day');
      expect(entry?.type, MarkedDayType.holiday);
    });

    test('a hidden holiday resolves to null', () {
      final entry = markedDayOn(
        DateTime(2026, 11, 2),
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [
          HolidayOverride(dateKey: '2026-11-02', hidden: true),
        ],
      );
      expect(entry, isNull);
    });

    test('a plain school day resolves to null', () {
      final entry = markedDayOn(
        DateTime(2026, 11, 9),
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      );
      expect(entry, isNull);
    });

    test('a built-in school event resolves with noClasses', () {
      final entry = markedDayOn(
        DateTime(2026, 10, 20),
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      );
      expect(entry?.name,
          'Intramural Games and Culture and Arts Festival');
      expect(entry?.type, MarkedDayType.noClasses);
    });
  });

  group('persistDraft', () {
    List<MarkedDayEntry> base({String? school}) => effectiveMarkedDays(
          school: school ?? 'University of Northern Philippines',
          custom: const [],
          overrides: const [],
        );

    test('an untouched draft persists nothing', () {
      final result = persistDraft(
        draft: base(),
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.custom, isEmpty);
      expect(result.overrides, isEmpty);
    });

    test('a renamed holiday becomes a name override', () {
      final draft = base()
          .map((e) => e.date == DateTime(2026, 11, 1)
              ? e.copyWith(name: 'Undas')
              : e)
          .toList();
      final result = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.custom, isEmpty);
      expect(result.overrides.length, 1);
      expect(result.overrides[0].dateKey, '2026-11-01');
      expect(result.overrides[0].name, 'Undas');
      expect(result.overrides[0].hidden, isFalse);
    });

    test('a removed holiday becomes a hidden override', () {
      final draft =
          base().where((e) => e.date != DateTime(2026, 11, 30)).toList();
      final result = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.custom, isEmpty);
      expect(result.overrides.length, 1);
      expect(result.overrides[0].dateKey, '2026-11-30');
      expect(result.overrides[0].hidden, isTrue);
    });

    test('an added day becomes a custom day', () {
      final draft = [
        ...base(),
        MarkedDayEntry(
          id: 'c-new',
          date: DateTime(2026, 11, 20),
          end: DateTime(2026, 11, 20),
          name: 'Foundation Day',
          type: MarkedDayType.event,
          source: MarkedDaySource.custom,
        ),
      ];
      final result = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.custom.length, 1);
      expect(result.custom[0].name, 'Foundation Day');
      expect(result.custom[0].date, DateTime(2026, 11, 20));
      expect(result.overrides, isEmpty);
    });

    test('a moved holiday hides the original and adds a custom day', () {
      final draft = base()
          .map((e) => e.date == DateTime(2026, 11, 30)
              ? e.copyWith(date: DateTime(2026, 12, 1))
              : e)
          .toList();
      final result = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.overrides.length, 1);
      expect(result.overrides[0].dateKey, '2026-11-30');
      expect(result.overrides[0].hidden, isTrue);
      expect(result.custom.length, 1);
      expect(result.custom[0].name, 'Bonifacio Day');
      expect(result.custom[0].date, DateTime(2026, 12, 1));
    });

    test('a round trip through persist keeps the draft visible', () {
      final draft = base()
          .map((e) => e.date == DateTime(2026, 11, 1)
              ? e.copyWith(name: 'Undas')
              : e)
          .where((e) => e.date != DateTime(2026, 11, 30))
          .toList()
        ..add(MarkedDayEntry(
          id: 'c-new',
          date: DateTime(2026, 11, 20),
          end: DateTime(2026, 11, 20),
          name: 'Foundation Day',
          type: MarkedDayType.event,
          source: MarkedDaySource.custom,
        ));
      final saved = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      final reloaded = effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: saved.custom,
        overrides: saved.overrides,
      );
      final nov = reloaded.where((d) => d.date.month == 11).toList();
      expect(nov.map((d) => d.name), [
        'Undas',
        "All Souls' Day",
        'Foundation Day',
      ]);
    });
  });

  group('groupMarkedDays / findDay / comingUpMarkedDays', () {
    test('a multi-day school event collapses to one row', () {
      final days = effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      );
      final grouped = groupMarkedDays(days);
      final intramurals = grouped.where(
          (d) => d.name.contains('Intramural Games')).toList();
      expect(intramurals.length, 1);
      expect(intramurals[0].date, DateTime(2026, 10, 19));
      expect(intramurals[0].end, DateTime(2026, 10, 25));
      expect(intramurals[0].source, MarkedDaySource.schoolEvent);
    });

    test('findDay is range-aware inside a multi-day event', () {
      final grouped = groupMarkedDays(effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      ));
      expect(findDay(grouped, DateTime(2026, 10, 21))?.name,
          'Intramural Games and Culture and Arts Festival');
      expect(findDay(grouped, DateTime(2026, 10, 26)), isNull);
      expect(findDay(grouped, DateTime(2026, 11, 1))?.name,
          "All Saints' Day");
    });

    test('coming up shows the event once, while it runs', () {
      final upcoming = comingUpMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
        from: DateTime(2026, 10, 20),
        limit: 5,
      );
      expect(upcoming[0].name,
          'Intramural Games and Culture and Arts Festival');
      expect(upcoming.where((d) => d.name.contains('Intramural')).length,
          1);
      expect(upcoming.map((d) => d.name), contains("All Saints' Day"));
    });

    test('an untouched multi-day event persists nothing', () {
      final draft = groupMarkedDays(effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      ));
      final result = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.custom, isEmpty);
      expect(result.overrides, isEmpty);
    });

    test('removing the grouped event hides it with one override', () {
      final draft = groupMarkedDays(effectiveMarkedDays(
        school: 'University of Northern Philippines',
        custom: const [],
        overrides: const [],
      ))
          .where((d) => !d.name.contains('Intramural Games'))
          .toList();
      final result = persistDraft(
        draft: draft,
        school: 'University of Northern Philippines',
        existingCustom: const [],
        existingOverrides: const [],
      );
      expect(result.custom, isEmpty);
      expect(result.overrides.length, 1);
      expect(result.overrides[0].dateKey, '2026-10-19');
      expect(result.overrides[0].hidden, isTrue);
    });
  });

  group('CustomSchoolDay / HolidayOverride JSON', () {
    test('a bad row is dropped instead of crashing the load', () {
      expect(CustomSchoolDay.fromJson({'id': 'x'}), isNull);
      expect(HolidayOverride.fromJson({'date': 'not-a-date'}), isNull);
      expect(
        CustomSchoolDay.fromJson({
          'id': 'c1',
          'name': 'Foundation Day',
          'date': '2026-11-20',
          'type': 'event',
        })?.name,
        'Foundation Day',
      );
    });

    test('dateKey round-trips', () {
      expect(parseDateKey(dateKey(DateTime(2026, 11, 1))),
          DateTime(2026, 11, 1));
      expect(parseDateKey('2026-13-01'), isNull);
      expect(parseDateKey('junk'), isNull);
    });
  });
}
