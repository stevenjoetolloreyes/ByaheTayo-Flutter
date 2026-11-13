import 'dart:io';

import 'package:estudyantego/features/student/google_events.dart';
import 'package:estudyantego/features/student/schedule_widget_service.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

// Schedule home screen widgets (Nov 11, 2026): small 4x2 "Next
// Class" + big 4x3 "This Week", approved preview v2. The times
// below are TEST FIXTURES only — Steven's real UNP DCT-1 schedule
// (CT101 / CT102 / CSS101) — the widget itself reads the
// student's stored schedule and never hardcodes these. Wednesday
// Nov 11, 2026 is the preview's free day (no classes); Thursday
// Nov 12 is the next class day.
//
// The stored model is SIX entries, not three: a Subject holds one
// time slot, so each course is two entries — a Monday slot and a
// Tue/Thu slot (same as the Files scan produces, see
// schedule_scan_certificate_test.dart).
List<Subject> fixtureSubjects() => [
      Subject(
        id: 'ct101-mon',
        name: 'Introduction to Computing',
        code: 'CT101',
        teacher: 'A. Supnet',
        room: 'CC105',
        days: const [1],
        startMin: 7 * 60 + 30,
        endMin: 9 * 60 + 30,
        color: 0xFF58CC02,
      ),
      Subject(
        id: 'ct101-tth',
        name: 'Introduction to Computing',
        code: 'CT101',
        teacher: 'A. Supnet',
        room: 'CC104',
        days: const [2, 4],
        startMin: 14 * 60,
        endMin: 15 * 60 + 30,
        color: 0xFF58CC02,
      ),
      Subject(
        id: 'ct102-mon',
        name: 'Computer Programming 1',
        code: 'CT102',
        teacher: 'W.E. Que',
        room: 'CC105',
        days: const [1],
        startMin: 10 * 60,
        endMin: 12 * 60,
        color: 0xFF1CB0F6,
      ),
      Subject(
        id: 'ct102-tth',
        name: 'Computer Programming 1',
        code: 'CT102',
        teacher: 'W.E. Que',
        room: 'CC104',
        days: const [2, 4],
        startMin: 10 * 60 + 30,
        endMin: 12 * 60,
        color: 0xFF1CB0F6,
      ),
      Subject(
        id: 'css101-mon',
        name: 'Installing and Configuring Computer Systems',
        code: 'CSS101',
        teacher: 'L. Baja',
        room: 'CC105',
        days: const [1],
        startMin: 13 * 60,
        endMin: 15 * 60,
        color: 0xFFFFC800,
      ),
      Subject(
        id: 'css101-tth',
        name: 'Installing and Configuring Computer Systems',
        code: 'CSS101',
        teacher: 'L. Baja',
        room: 'CC203',
        days: const [2, 4],
        startMin: 9 * 60,
        endMin: 10 * 60 + 30,
        color: 0xFFFFC800,
      ),
    ];

// The four Google Calendar events currently in the app (the sample
// set seeded by loadGoogleEvents; the first real sync replaces
// them). Fixtures only — the widget reads the stored set.
List<GoogleCalendarEvent> fixtureGoogleEvents() => [
      GoogleCalendarEvent(
        id: 'g-nstp',
        title: 'NSTP 1',
        weekday: 6,
        startMin: 8 * 60,
        endMin: 11 * 60,
        place: 'Covered Court',
        color: 0xFF4285F4,
      ),
      GoogleCalendarEvent(
        id: 'g-rizal',
        title: 'Life and Works of Rizal',
        weekday: 5,
        startMin: 10 * 60,
        endMin: 11 * 60 + 30,
        place: 'Rm 112',
        teacher: "Ma'am Santos",
        color: 0xFF4285F4,
      ),
      GoogleCalendarEvent(
        id: 'g-discrete',
        title: 'Discrete Mathematics',
        weekday: 4,
        startMin: 15 * 60,
        endMin: 16 * 60 + 30,
        place: 'Rm 204',
        teacher: 'Sir Dela Cruz',
        color: 0xFF4285F4,
      ),
      GoogleCalendarEvent(
        id: 'g-vigan',
        title: 'Vigan',
        weekday: 7,
        startMin: 16 * 60 + 47,
        endMin: 17 * 60 + 47,
        place: 'Vigan',
        color: 0xFF4285F4,
        single: true,
      ),
    ];

void main() {
  group('nextClass', () {
    test('Wednesday Nov 11 (no classes) -> next is Thu CSS101 9:00 AM',
        () {
      final next = nextClass(fixtureSubjects(), DateTime(2026, 11, 11, 12));
      expect(next, isNotNull);
      expect(next!.subject.code, 'CSS101');
      expect(next.date, DateTime(2026, 11, 12));
    });

    test('Monday 7:00 AM -> CT101 at 7:30 AM', () {
      final next = nextClass(fixtureSubjects(), DateTime(2026, 11, 9, 7));
      expect(next, isNotNull);
      expect(next!.subject.code, 'CT101');
      expect(next.date, DateTime(2026, 11, 9));
    });

    test('Monday 8:00 AM (during CT101) -> next is CT102 at 10:00 AM',
        () {
      final next =
          nextClass(fixtureSubjects(), DateTime(2026, 11, 9, 8));
      expect(next, isNotNull);
      expect(next!.subject.code, 'CT102');
    });

    test('Monday after all classes -> Tue CSS101 9:00 AM', () {
      final next =
          nextClass(fixtureSubjects(), DateTime(2026, 11, 9, 15));
      expect(next, isNotNull);
      expect(next!.subject.code, 'CSS101');
      expect(next.date, DateTime(2026, 11, 10));
    });

    test('empty schedule -> null', () {
      expect(nextClass([], DateTime(2026, 11, 11, 12)), isNull);
    });

    test('subject with no meeting days -> null', () {
      final subjects = [
        Subject(
          id: 'x',
          name: 'No Days',
          code: 'X',
          teacher: '',
          room: '',
          days: const [],
          startMin: 540,
          endMin: 600,
          color: 0xFF58CC02,
        ),
      ];
      expect(nextClass(subjects, DateTime(2026, 11, 11, 12)), isNull);
    });
  });

  group('classesOnDay', () {
    test('Monday has 3 classes, time-sorted', () {
      final monday = classesOnDay(fixtureSubjects(), 1);
      expect(monday.map((s) => s.code).toList(),
          ['CT101', 'CT102', 'CSS101']);
    });

    test('Wednesday has no classes (the preview free day)', () {
      expect(classesOnDay(fixtureSubjects(), 3), isEmpty);
    });

    test('Thursday has 3 classes', () {
      expect(classesOnDay(fixtureSubjects(), 4).length, 3);
    });
  });

  group('labels', () {
    test('nextClassDateLine: Thu, Nov 12', () {
      expect(ScheduleWidgetService.nextClassDateLine(DateTime(2026, 11, 12)),
          'Thu, Nov 12');
    });

    test('comingUpLabel: Today / Tomorrow / weekday', () {
      expect(
          ScheduleWidgetService.comingUpLabel(
              DateTime(2026, 11, 11), DateTime(2026, 11, 11, 12), 540),
          'Today at 9:00 AM');
      expect(
          ScheduleWidgetService.comingUpLabel(
              DateTime(2026, 11, 12), DateTime(2026, 11, 11, 12), 540),
          'Tomorrow at 9:00 AM');
      expect(
          ScheduleWidgetService.comingUpLabel(
              DateTime(2026, 11, 16), DateTime(2026, 11, 11, 12), 540),
          'Mon at 9:00 AM');
    });

    test('nextUpLine: Next up: Thu · CSS101 · 9:00 AM · CC203', () {
      expect(
          ScheduleWidgetService.nextUpLine(
              fixtureSubjects(), DateTime(2026, 11, 11, 20)),
          'Next up: Thu · CSS101 · 9:00 AM · CC203');
    });

    test('nextUpLine is null when there is no upcoming class', () {
      expect(ScheduleWidgetService.nextUpLine([], DateTime(2026, 11, 11)),
          isNull);
    });

    test('timeRange is built from stored minutes', () {
      final subject = ScheduleWidgetSubject.fromSubject(fixtureSubjects()
          .firstWhere((s) => s.id == 'css101-tth'));
      expect(subject.timeRange, '9:00–10:30 AM');
    });

    test('timeRange shows the suffix once, or twice across noon', () {
      Subject at(int startMin, int endMin) => Subject(
            id: 't',
            name: 'T',
            code: 'T',
            teacher: '',
            room: '',
            days: const [1],
            startMin: startMin,
            endMin: endMin,
            color: 0xFF58CC02,
          );
      expect(ScheduleWidgetSubject.fromSubject(at(14 * 60, 15 * 60 + 30))
          .timeRange, '2:00–3:30 PM');
      expect(ScheduleWidgetSubject.fromSubject(at(11 * 60, 12 * 60 + 30))
          .timeRange, '11:00 AM–12:30 PM');
    });
  });

  group('JSON round-trip', () {
    test('encode/decode preserves subjects and Google events', () {
      final subjects = fixtureSubjects();
      final google = fixtureGoogleEvents();
      final raw = ScheduleWidgetService.encodeData(subjects, google);
      final decoded = ScheduleWidgetService.decodeData(raw);
      expect(decoded.subjects.length, 6);
      expect(decoded.subjects.map((s) => s.code).toList(), [
        'CT101',
        'CT101',
        'CT102',
        'CT102',
        'CSS101',
        'CSS101',
      ]);
      expect(decoded.googleEvents.map((e) => e.title).toList(), [
        'NSTP 1',
        'Life and Works of Rizal',
        'Discrete Mathematics',
        'Vigan',
      ]);
      // Round-trip is stable: encoding the decoded data again
      // gives the same JSON.
      expect(ScheduleWidgetService.encodeData(
              decoded.subjects
                  .map((s) => Subject(
                        id: s.id,
                        name: s.name,
                        code: s.code,
                        teacher: '',
                        room: s.room,
                        days: s.days,
                        startMin: s.startMin,
                        endMin: s.endMin,
                        color: s.color,
                      ))
                  .toList(),
              google),
          raw);
    });

    test('decodeData is empty for null, empty, non-map, malformed', () {
      expect(ScheduleWidgetService.decodeData(null).subjects, isEmpty);
      expect(ScheduleWidgetService.decodeData('').subjects, isEmpty);
      expect(ScheduleWidgetService.decodeData('not json').subjects, isEmpty);
      expect(ScheduleWidgetService.decodeData('[1, 2]').subjects, isEmpty);
      expect(ScheduleWidgetService.decodeData('{"subjects": "x"}').subjects,
          isEmpty);
    });
  });

  group('no instructor names in the widget payload', () {
    test('encoded JSON never contains a teacher name', () {
      final raw = ScheduleWidgetService.encodeData(
          fixtureSubjects(), fixtureGoogleEvents());
      expect(raw.contains('Supnet'), isFalse);
      expect(raw.contains('Que'), isFalse);
      expect(raw.contains('Baja'), isFalse);
      expect(raw.contains('Santos'), isFalse);
      expect(raw.contains('Dela Cruz'), isFalse);
      expect(raw.contains('teacher'), isFalse);
    });

    test('a subject with a teacher still encodes without it', () {
      final subject = Subject(
        id: 't',
        name: 'With Teacher',
        code: 'WT',
        teacher: 'A. Supnet',
        room: 'CC105',
        days: const [1],
        startMin: 450,
        endMin: 570,
        color: 0xFF58CC02,
      );
      final raw =
          ScheduleWidgetService.encodeData([subject], const []);
      expect(raw.contains('Supnet'), isFalse);
      final decoded = ScheduleWidgetService.decodeData(raw);
      expect(decoded.subjects.single.name, 'With Teacher');
    });
  });

  group('sync', () {
    test('sync() never throws without the widget plugin', () async {
      // In flutter_test there is no home_widget platform channel;
      // sync() must swallow that and return normally, so the
      // Classes screen and app start can fire-and-forget it.
      await ScheduleWidgetService.sync();
    });
  });

  group('widget layouts follow the RemoteViews rules', () {
    // Same failure mode as the Bible widget (Nov 8-11, 2026):
    // plain View, clipToOutline, or a full-size photo src makes
    // the launcher show "An error occurred when loading widget".
    const liveLayouts = [
      'android/app/src/main/res/layout/schedule_widget.xml',
      'android/app/src/main/res/layout/schedule_widget_week.xml',
      'android/app/src/main/res/layout-night/schedule_widget.xml',
      'android/app/src/main/res/layout-night/schedule_widget_week.xml',
    ];
    const previewLayouts = [
      'android/app/src/main/res/layout/schedule_widget_preview.xml',
      'android/app/src/main/res/layout/schedule_widget_week_preview.xml',
    ];

    String readLayout(String path) => File(path).readAsStringSync();

    test('no plain View element in any schedule layout', () {
      for (final path in [...liveLayouts, ...previewLayouts]) {
        final xml = readLayout(path);
        expect(xml.contains('<View'), isFalse,
            reason:
                '$path uses a plain View, which RemoteViews does not allow');
      }
    });

    test('no clipToOutline / outlineProvider in any schedule layout', () {
      for (final path in [...liveLayouts, ...previewLayouts]) {
        final xml = readLayout(path);
        expect(xml.contains('clipToOutline'), isFalse, reason: path);
        expect(xml.contains('outlineProvider'), isFalse, reason: path);
      }
    });

    test('the only src is the E logo', () {
      for (final path in [...liveLayouts, ...previewLayouts]) {
        final xml = readLayout(path);
        for (final match in RegExp(r'android:src="([^"]+)"')
            .allMatches(xml)) {
          expect(match.group(1), '@drawable/launch_image', reason: path);
        }
      }
    });

    test('4x2 layout has the ids the provider fills', () {
      final xml = readLayout(
          'android/app/src/main/res/layout/schedule_widget.xml');
      for (final id in [
        'widget_root',
        'widget_today_title',
        'widget_today_sub',
        'widget_next_card',
        'widget_next_label',
        'widget_next_name',
        'widget_next_date',
        'widget_next_time',
        'widget_next_when',
        'widget_empty',
        'widget_google_section',
        'widget_google_more',
      ]) {
        expect(xml.contains('@+id/$id'), isTrue, reason: id);
      }
      for (var i = 0; i < 4; i++) {
        expect(xml.contains('@+id/widget_google_$i'), isTrue,
            reason: 'widget_google_$i');
        expect(xml.contains('@+id/widget_google_title_$i'), isTrue,
            reason: 'widget_google_title_$i');
      }
    });

    test('4x3 layout has one row per day and the footer', () {
      final xml = readLayout(
          'android/app/src/main/res/layout/schedule_widget_week.xml');
      expect(xml.contains('@+id/widget_next_up'), isTrue);
      expect(xml.contains('@+id/widget_google_section'), isTrue);
      for (var d = 1; d <= 7; d++) {
        expect(xml.contains('@+id/widget_day_$d'), isTrue,
            reason: 'widget_day_$d');
        expect(xml.contains('@+id/widget_day_${d}_badge'), isTrue,
            reason: 'widget_day_${d}_badge');
        expect(xml.contains('@+id/widget_day_${d}_empty'), isTrue,
            reason: 'widget_day_${d}_empty');
        for (var i = 0; i < 3; i++) {
          expect(xml.contains('@+id/widget_day_${d}_class_$i'), isTrue,
              reason: 'widget_day_${d}_class_$i');
          expect(
              xml.contains('@+id/widget_day_${d}_class_${i}_code'), isTrue,
              reason: 'widget_day_${d}_class_${i}_code');
        }
      }
    });

    test('preview layouts show the approved sample content', () {
      final small = readLayout(
          'android/app/src/main/res/layout/schedule_widget_preview.xml');
      // Nov 13 picker picture: a school day (Monday, 3 classes,
      // 1 done) so the picker shows the progress bar + next class.
      expect(small.contains('Classes today'), isTrue);
      expect(small.contains('1 of 3 done'), isTrue);
      expect(small.contains('CT102'), isTrue);
      expect(small.contains('10:00 AM–12:00 PM'), isTrue);
      expect(small.contains('CC105'), isTrue);
      expect(small.contains('NSTP 1'), isTrue);
      expect(small.contains('Vigan'), isTrue);
      final week = readLayout(
          'android/app/src/main/res/layout/schedule_widget_week_preview.xml');
      expect(week.contains('CT101'), isTrue);
      expect(week.contains('Next up: Mon · CT102 · 10:00 AM · CC105'),
          isTrue);
    });

    test('info XMLs point at the live + preview layouts', () {
      final small = File(
              'android/app/src/main/res/xml/schedule_widget_info.xml')
          .readAsStringSync();
      expect(small.contains('@layout/schedule_widget'), isTrue);
      expect(small.contains('@layout/schedule_widget_preview'), isTrue);
      expect(small.contains('targetCellWidth="4"'), isTrue);
      expect(small.contains('targetCellHeight="2"'), isTrue);
      final week = File(
              'android/app/src/main/res/xml/schedule_widget_week_info.xml')
          .readAsStringSync();
      expect(week.contains('@layout/schedule_widget_week'), isTrue);
      expect(week.contains('@layout/schedule_widget_week_preview'), isTrue);
      expect(week.contains('targetCellHeight="3"'), isTrue);
    });

    test('drawables the layouts reference exist', () {
      for (final name in [
        'schedule_widget_card',
        'schedule_widget_card_night',
        'schedule_widget_next_card',
        'schedule_widget_next_card_night',
        'schedule_widget_g_badge',
        'schedule_widget_size_chip',
        'schedule_widget_day_badge',
      ]) {
        expect(
            File('android/app/src/main/res/drawable/$name.xml').existsSync(),
            isTrue,
            reason: name);
      }
    });

    test('manifest registers both schedule providers', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest.contains('.ScheduleWidgetProvider'), isTrue);
      expect(manifest.contains('.ScheduleWeekWidgetProvider'), isTrue);
      expect(manifest.contains('@xml/schedule_widget_info'), isTrue);
      expect(manifest.contains('@xml/schedule_widget_week_info'), isTrue);
    });
  });
}
