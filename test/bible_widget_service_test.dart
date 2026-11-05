import 'package:estudyantego/features/student/bible_widget_service.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verseIndexForDate', () {
    test('Jan 1 is index 0 and the rotation wraps after the list', () {
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 1, 1), 30),
          0);
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 1, 30), 30),
          29);
      // Jan 31 is day 31 -> (31 - 1) % 30 == 0, back to the first verse.
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 1, 31), 30),
          0);
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 2, 1), 30),
          1);
    });

    test('Dec 31 differs between leap and common years', () {
      // 2026 is a common year: Dec 31 is day 365 -> (365 - 1) % 30 == 4.
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 12, 31), 30),
          4);
      // 2024 is a leap year: Dec 31 is day 366 -> (366 - 1) % 30 == 5.
      expect(BibleWidgetService.verseIndexForDate(DateTime(2024, 12, 31), 30),
          5);
    });

    test('Feb 29 exists only in leap years and shifts March', () {
      // Leap year: Feb 29 is day 60 -> (60 - 1) % 30 == 29.
      expect(BibleWidgetService.verseIndexForDate(DateTime(2024, 2, 29), 30),
          29);
      // Leap year: Mar 1 is day 61 -> (61 - 1) % 30 == 0.
      expect(BibleWidgetService.verseIndexForDate(DateTime(2024, 3, 1), 30),
          0);
      // Common year: Mar 1 is day 60 -> (60 - 1) % 30 == 29.
      expect(BibleWidgetService.verseIndexForDate(DateTime(2025, 3, 1), 30),
          29);
    });

    test('degenerate counts return 0 instead of dividing by zero', () {
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 6, 15), 0),
          0);
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 6, 15), -3),
          0);
      expect(BibleWidgetService.verseIndexForDate(DateTime(2026, 6, 15), 1),
          0);
    });
  });

  group('verse selection matches verseOfDay', () {
    test('decoded list picks the same verse as the in-app Verse of the Day',
        () {
      final verses =
          BibleWidgetService.decodeVerses(BibleWidgetService.encodeVerses());
      expect(verses.length, bundledVerses.length);
      for (final date in [
        DateTime(2026, 1, 1),
        DateTime(2026, 11, 5),
        DateTime(2024, 2, 29),
        DateTime(2024, 12, 31),
        DateTime(2026, 12, 31),
      ]) {
        final expected = verseOfDay(date);
        final picked = BibleWidgetService.verseForDate(verses, date);
        expect(picked, isNotNull);
        expect(picked!.id, expected.id);
        expect(picked.ref, expected.ref);
        expect(picked.text, expected.text);
      }
    });
  });

  group('JSON round-trip', () {
    test('encode then decode preserves every bundled verse', () {
      final decoded =
          BibleWidgetService.decodeVerses(BibleWidgetService.encodeVerses());
      expect(decoded.length, bundledVerses.length);
      expect(decoded.first.id, 'v01');
      expect(decoded.first.ref, 'John 3:16');
      expect(decoded.last.id, 'v30');
      expect(decoded.last.ref, '1 Peter 5:7');
      for (var i = 0; i < bundledVerses.length; i++) {
        expect(decoded[i].id, bundledVerses[i].id);
        expect(decoded[i].ref, bundledVerses[i].ref);
        expect(decoded[i].text, bundledVerses[i].text);
      }
    });

    test('a single verse round-trips through its JSON map', () {
      const verse =
          BibleWidgetVerse(id: 'v09', ref: 'Matthew 11:28', text: 'Come.');
      final back = BibleWidgetVerse.fromJson(verse.toJson());
      expect(back, verse);
    });
  });

  group('placeholder when no data', () {
    test('decodeVerses returns empty for null, blank, or bad input', () {
      expect(BibleWidgetService.decodeVerses(null), isEmpty);
      expect(BibleWidgetService.decodeVerses(''), isEmpty);
      expect(BibleWidgetService.decodeVerses('not json'), isEmpty);
      expect(BibleWidgetService.decodeVerses('{}'), isEmpty);
      expect(BibleWidgetService.decodeVerses('[]'), isEmpty);
      // One malformed entry poisons the whole payload: the widget
      // treats it as "no data yet" instead of showing a half verse.
      expect(BibleWidgetService.decodeVerses('[{"id": 1}]'), isEmpty);
    });

    test('verseForDate returns null for an empty list', () {
      expect(
        BibleWidgetService.verseForDate([], DateTime(2026, 11, 5)),
        isNull,
      );
    });

    test('the placeholder text is the agreed wording', () {
      expect(BibleWidgetService.placeholderText,
          "Open EstudyanteGO to load today's verse");
    });
  });

  group('syncVerses', () {
    test('completes without throwing when the plugin is unavailable', () async {
      // No platform channel is registered in tests, so the
      // home_widget calls throw MissingPluginException — the
      // service must swallow that so the Bible screen never breaks.
      await BibleWidgetService.syncVerses();
    });
  });
}
