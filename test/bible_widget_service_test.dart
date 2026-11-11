import 'dart:io';

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

  group('verse scenes', () {
    test('every bundled verse maps to a known nature scene', () {
      expect(BibleWidgetService.verseScenes.length, bundledVerses.length);
      for (final v in bundledVerses) {
        final scene = BibleWidgetService.sceneForVerse(v);
        expect(BibleWidgetService.knownScenes, contains(scene),
            reason: '${v.id} (${v.ref}) maps to an unknown scene');
      }
    });

    test('Philippians 4:13 uses the sample sunset/cross scene', () {
      final verse = bundledVerses.firstWhere((v) => v.id == 'v03');
      expect(verse.ref, 'Philippians 4:13');
      expect(BibleWidgetService.sceneForVerse(verse), 'sunset_cross');
    });

    test('the known scenes are exactly the four nature scenes', () {
      // The verse-list JSON only ever carries a NATURE scene: the
      // season scenes are picked from the date (see
      // seasonSceneForDate) and appear only in the today-pair's
      // `scene` — so they must NOT be here.
      expect(BibleWidgetService.knownScenes, [
        'sunset_cross',
        'mountain_sunrise',
        'calm_sea',
        'forest_light',
      ]);
      for (final season in BibleWidgetService.seasonScenes) {
        expect(BibleWidgetService.knownScenes, isNot(contains(season)));
      }
    });

    test('a verse without a mapping falls back to the default scene', () {
      const unmapped = BundledVerse(
        id: 'v99',
        book: 'Test',
        chapter: 1,
        verse: '1',
        text: 'Test.',
        topics: ['Faith'],
      );
      expect(BibleWidgetService.sceneForVerse(unmapped),
          BibleWidgetService.defaultScene);
    });

    test('the scene round-trips through JSON', () {
      const verse = BibleWidgetVerse(
          id: 'v09', ref: 'Matthew 11:28', text: 'Come.', scene: 'calm_sea');
      final back = BibleWidgetVerse.fromJson(verse.toJson());
      expect(back, verse);
      expect(back.scene, 'calm_sea');
    });

    test('fromJson defaults the scene when it is missing or unknown', () {
      // A list pushed by an older app build has no scene field.
      final missing = BibleWidgetVerse.fromJson(
          {'id': 'v03', 'ref': 'Philippians 4:13', 'text': 'I can.'});
      expect(missing.scene, BibleWidgetService.defaultScene);
      final unknown = BibleWidgetVerse.fromJson({
        'id': 'v03',
        'ref': 'Philippians 4:13',
        'text': 'I can.',
        'scene': 'not_a_scene',
      });
      expect(unknown.scene, BibleWidgetService.defaultScene);
    });

    test('the pushed JSON carries a scene for every verse', () {
      final decoded =
          BibleWidgetService.decodeVerses(BibleWidgetService.encodeVerses());
      expect(decoded.length, bundledVerses.length);
      for (final v in decoded) {
        expect(BibleWidgetService.knownScenes, contains(v.scene));
      }
      final philippians = decoded.firstWhere((v) => v.id == 'v03');
      expect(philippians.scene, 'sunset_cross');
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

  group('season scenes', () {
    test('the season scenes are exactly the eight feast/season photos', () {
      expect(BibleWidgetService.seasonScenes, [
        'all_saints',
        'all_souls',
        'immaculate_conception',
        'epiphany',
        'advent',
        'christmas',
        'lent',
        'ordinary_time',
      ]);
      // A season scene is never a nature scene and vice versa.
      for (final s in BibleWidgetService.seasonScenes) {
        expect(BibleWidgetService.knownScenes, isNot(contains(s)));
      }
    });

    test('fixed feasts override the season they fall in', () {
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 11, 1)),
          'all_saints');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 11, 1)),
          'all_saints');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 11, 2)),
          'all_souls');
      // Dec 8 is inside Advent — the feast still wins.
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 12, 8)),
          'immaculate_conception');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 12, 8)),
          'immaculate_conception');
    });

    test('Epiphany is the Sunday observance, not the traditional Jan 6', () {
      // 2027: Sunday Jan 3; 2028: Sunday Jan 2.
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 1, 3)),
          'epiphany');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 1, 2)),
          'epiphany');
      // Jan 6 is an ordinary Christmas-season day, not Epiphany.
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 1, 6)),
          'christmas');
    });

    test('Advent and Christmas windows, 2026-27 and 2027-28', () {
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 11, 29)),
          'advent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 12, 24)),
          'advent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 12, 25)),
          'christmas');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 1, 10)),
          'christmas');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 11, 28)),
          'advent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 12, 24)),
          'advent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 12, 25)),
          'christmas');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 1, 9)),
          'christmas');
    });

    test('Lent windows, 2027 and 2028', () {
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 2, 10)),
          'lent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 3, 25)),
          'lent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 3, 1)),
          'lent');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 4, 13)),
          'lent');
    });

    test('Easter Time and the Triduum have no photo yet (null)', () {
      // 2027: Triduum Mar 26-27, Easter Mar 28 – May 16.
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 3, 26)),
          isNull);
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 3, 28)),
          isNull);
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 5, 16)),
          isNull);
      // 2028: Triduum Apr 14-15, Easter Apr 16 – Jun 4.
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 4, 14)),
          isNull);
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 4, 16)),
          isNull);
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2028, 6, 4)),
          isNull);
    });

    test('Ordinary Time is the default (its own photo)', () {
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 1, 11)),
          'ordinary_time');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 2, 9)),
          'ordinary_time');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 5, 17)),
          'ordinary_time');
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2026, 11, 3)),
          'ordinary_time');
      // Christ the King (Nov 21, 2027) is an Ordinary Time Sunday
      // until its photo arrives — it shows the Ordinary Time photo.
      expect(BibleWidgetService.seasonSceneForDate(DateTime(2027, 11, 21)),
          'ordinary_time');
    });

    test('seasonSceneForDate only ever returns a season scene or null', () {
      // Sweep a full year: every result must be a season scene
      // (or null for the photo-less seasons), never a nature scene.
      for (var day = 1; day <= 365; day++) {
        final date = DateTime(2027, 1, 1).add(Duration(days: day - 1));
        final scene = BibleWidgetService.seasonSceneForDate(date);
        if (scene != null) {
          expect(BibleWidgetService.seasonScenes, contains(scene),
              reason: '$date returned $scene');
        }
      }
    });

    test('sceneForDate resolves the background: season, then verse', () {
      final verse = bundledVerses.firstWhere((v) => v.id == 'v03');
      // Advent: the season photo, not the verse's sunset_cross.
      expect(BibleWidgetService.sceneForDate(DateTime(2026, 12, 1), verse),
          'advent');
      // Lent: the season photo.
      expect(BibleWidgetService.sceneForDate(DateTime(2027, 2, 20), verse),
          'lent');
      // Ordinary Time: the dedicated Ordinary Time photo, NOT the
      // verse's nature scene.
      expect(BibleWidgetService.sceneForDate(DateTime(2027, 1, 20), verse),
          'ordinary_time');
      // Easter (no photo yet): the verse's nature photo.
      expect(BibleWidgetService.sceneForDate(DateTime(2027, 4, 10), verse),
          'sunset_cross');
    });
  });

  group('today pair', () {
    test('todayPair carries the verse and its background together', () {
      final date = DateTime(2026, 12, 1); // Advent
      final pair = BibleWidgetService.todayPair(date);
      final verse = verseOfDay(date);
      expect(pair['date'], '2026-12-01');
      expect(pair['id'], verse.id);
      expect(pair['ref'], verse.ref);
      expect(pair['text'], verse.text);
      expect(pair['scene'], 'advent');
      expect(
          pair['scene'],
          BibleWidgetService.sceneForDate(date, verse));
    });

    test('the pair scene follows the season: Ordinary Time, Easter', () {
      expect(
          BibleWidgetService.todayPair(DateTime(2027, 1, 20))['scene'],
          'ordinary_time');
      // Easter: the verse's nature photo (no Easter photo yet).
      final easter = DateTime(2027, 4, 10);
      expect(
          BibleWidgetService.todayPair(easter)['scene'],
          BibleWidgetService.sceneForVerse(verseOfDay(easter)));
      // A fixed feast: All Saints Day.
      expect(
          BibleWidgetService.todayPair(DateTime(2026, 11, 1))['scene'],
          'all_saints');
    });

    test('the pair is one JSON object that round-trips for its date', () {
      final date = DateTime(2026, 11, 8);
      final encoded = BibleWidgetService.encodeTodayPair(date);
      expect(encoded.startsWith('{'), isTrue);
      final decoded = BibleWidgetService.decodeTodayPair(encoded, date);
      expect(decoded, isNotNull);
      expect(decoded, BibleWidgetService.todayPair(date));
      // A different date is stale: the provider must not use it.
      expect(BibleWidgetService.decodeTodayPair(
          encoded, DateTime(2026, 11, 9)), isNull);
      // Malformed input is not a pair.
      expect(BibleWidgetService.decodeTodayPair(null, date), isNull);
      expect(BibleWidgetService.decodeTodayPair('', date), isNull);
      expect(BibleWidgetService.decodeTodayPair('not json', date), isNull);
      expect(BibleWidgetService.decodeTodayPair('[]', date), isNull);
      expect(BibleWidgetService.decodeTodayPair('{}', date), isNull);
      // A pair missing its scene is not a pair.
      expect(
          BibleWidgetService.decodeTodayPair(
              '{"date":"2026-11-08","id":"v01","ref":"John 3:16","text":"x"}',
              date),
          isNull);
    });
  });

  group('widget layouts follow the RemoteViews rules', () {
    // The widget layouts are read from disk: these tests fail on
    // the old layouts (plain View, clipToOutline, full-size photo
    // src) that made the launcher show "An error occurred when
    // loading widget" on Steven's Huawei P30 Lite (Nov 8-11, 2026).
    const liveLayouts = [
      'android/app/src/main/res/layout/bible_verse_widget.xml',
      'android/app/src/main/res/layout-night/bible_verse_widget.xml',
    ];
    const previewLayout =
        'android/app/src/main/res/layout/bible_verse_widget_preview.xml';

    String readLayout(String path) => File(path).readAsStringSync();

    test('no plain View element in any widget layout', () {
      for (final path in [...liveLayouts, previewLayout]) {
        final xml = readLayout(path);
        expect(xml.contains('<View'), isFalse,
            reason:
                '$path uses a plain View, which RemoteViews does not allow');
      }
    });

    test('no clipToOutline / outlineProvider in any widget layout', () {
      for (final path in [...liveLayouts, previewLayout]) {
        final xml = readLayout(path);
        expect(xml.contains('clipToOutline'), isFalse, reason: path);
        expect(xml.contains('outlineProvider'), isFalse, reason: path);
      }
    });

    test('no full-size photo src in any widget layout', () {
      // The launcher must never decode the 2240px verse_bg_* file
      // during inflation; the provider sets a downsampled bitmap.
      for (final path in [...liveLayouts, previewLayout]) {
        final xml = readLayout(path);
        expect(xml.contains('android:src="@drawable/verse_bg_'), isFalse,
            reason: path);
      }
      // The logo is the only src left in the live layouts.
      for (final path in liveLayouts) {
        expect(
            readLayout(path)
                .contains('android:src="@drawable/launch_image"'),
            isTrue,
            reason: path);
      }
    });

    test('the provider-visible ids are still present', () {
      for (final path in liveLayouts) {
        final xml = readLayout(path);
        for (final id in [
          'widget_root',
          'widget_background',
          'widget_scrim',
          'widget_verse',
          'widget_divider',
          'widget_ref',
        ]) {
          expect(xml.contains('android:id="@+id/$id"'), isTrue,
              reason: '$path is missing $id');
        }
      }
    });

    test('the provider downsamples the photo instead of setImageViewResource',
        () {
      final provider = File(
        'android/app/src/main/kotlin/com/estudyantego/app/BibleVerseWidgetProvider.kt',
      ).readAsStringSync();
      expect(provider.contains('setImageViewResource('), isFalse);
      expect(provider.contains('setImageViewBitmap(R.id.widget_background'),
          isTrue);
      expect(provider.contains('inSampleSize'), isTrue);
      expect(provider.contains('Bitmap.Config.RGB_565'), isTrue);
      expect(provider.contains('decodeWidgetBackground'), isTrue);
    });
  });
}
