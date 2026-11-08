// Bible Verse home screen widget — Dart side (Android only).
//
// DESIGN (why this shape): the widget must show TODAY's verse even
// on days the app was never opened, so the Dart side pushes the
// FULL bundled verse list once as JSON and the Kotlin
// AppWidgetProvider picks today's verse by day-of-year itself on
// every update (updatePeriodMillis 30 min). The single source of
// truth stays the bundled list in student_data.dart — nothing here
// re-lists the verses, so a future verse edit flows to the widget
// with the next Bible screen open.
//
// The background photo follows the CATHOLIC LITURGICAL SEASON /
// feast (Steven, Nov 8), NOT only the verse: fixed feasts first
// (Nov 1 All Saints, Nov 2 All Souls, Dec 8 Immaculate
// Conception, Epiphany), then the season window (Advent,
// Christmas, Lent; Ordinary Time has its own photo), and only
// in a season with no photo yet (Easter Time, the Triduum)
// does it fall back to the verse's nature photo. Every verse
// is therefore still tagged here with a scene name (see
// verseScenes) — that tag is the fallback background, and it
// travels in the pushed JSON. The sample's sunset/cross photo
// is Philippians 4:13's scene.
//
// VERSE + PHOTO SYNC (Steven, Nov 8: "Dapat nag Sync yung
// verse, photo ah"): the app writes today's verse AND its
// background as ONE pair — a single JSON object under
// `bible_widget_today` (see todayPair), written in one
// saveWidgetData call — and the provider applies both in a
// single RemoteViews update, so the widget never shows a new
// verse with an old photo (or vice versa). The season lookup
// therefore lives on BOTH sides: here (to pick the pair's
// background at refresh time) and in the provider (to derive
// both from today when the pair is stale — the app wasn't
// opened across a season boundary). The two tables MUST stay
// in sync (same dates, same scenes) — see seasonSceneForDate
// here and in BibleVerseWidgetProvider.
//
// The photos are BINARY — they cannot be pushed via the
// GitHub App and are web-uploaded into res/drawable (like the
// fonts and launch_image). To add a theme later:
// generate/upload a photo as res/drawable/verse_bg_<name>.webp,
// add the name here (nature) or to BOTH season tables, and
// add one line to the Kotlin sceneDrawable(). The provider
// references each scene by NAME, never by file, so swapping a
// photo is a file replacement, not a code change.
//
// The push is best-effort and never throws: widget tests run
// without the plugin, and the Bible screen must never break
// because the widget plugin is unavailable. The provider shows a
// placeholder ("Open EstudyanteGO to load today's verse") when no
// verse data has been pushed yet.
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'student_data.dart';

/// One verse as the widget understands it: id + precomputed
/// reference + text + the scene (background photo) for the verse.
/// The reference is precomputed here so the Kotlin side never has
/// to rebuild "Book chapter:verse"; the scene is picked here too,
/// so the Kotlin side just renders the scene name it is given.
class BibleWidgetVerse {
  const BibleWidgetVerse({
    required this.id,
    required this.ref,
    required this.text,
    this.scene = BibleWidgetService.defaultScene,
  });

  factory BibleWidgetVerse.fromBundled(BundledVerse v) => BibleWidgetVerse(
        id: v.id,
        ref: v.ref,
        text: v.text,
        scene: BibleWidgetService.sceneForVerse(v),
      );

  factory BibleWidgetVerse.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ref = json['ref'];
    final text = json['text'];
    if (id is! String || ref is! String || text is! String) {
      throw const FormatException('Bible widget verse entry is malformed');
    }
    final scene = json['scene'];
    return BibleWidgetVerse(
      id: id,
      ref: ref,
      text: text,
      scene: scene is String && BibleWidgetService.knownScenes.contains(scene)
          ? scene
          : BibleWidgetService.defaultScene,
    );
  }

  final String id;

  /// e.g. "Matthew 11:28" — the widget shows just the reference
  /// in its green pill (no " (KJV)" suffix, as in the sample).
  final String ref;
  final String text;

  /// Scene (background photo) name for this verse, e.g.
  /// 'sunset_cross'. The Kotlin provider maps it to the photo
  /// drawable of the same name (`verse_bg_<scene>`). Unknown names
  /// fall back to the default on both sides.
  final String scene;

  Map<String, dynamic> toJson() =>
      {'id': id, 'ref': ref, 'text': text, 'scene': scene};

  @override
  bool operator ==(Object other) =>
      other is BibleWidgetVerse &&
      other.id == id &&
      other.ref == ref &&
      other.text == text &&
      other.scene == scene;

  @override
  int get hashCode => Object.hash(id, ref, text, scene);
}

/// An inclusive liturgical season window mapped to a scene (or
/// null for a season with no photo yet — the caller falls back
/// to the verse's nature photo). Used by
/// [BibleWidgetService.seasonSceneForDate] and mirrored in the
/// Kotlin provider (same dates, same scenes) — see the table
/// there; the two must stay in sync.
class _SeasonWindow {
  _SeasonWindow(this.start, this.end, this.scene);
  final DateTime start;
  final DateTime end;
  final String? scene;
  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

class BibleWidgetService {
  BibleWidgetService._();

  /// SharedPreferences key (inside the home_widget store) holding
  /// the full verse list JSON.
  static const String versesKey = 'bible_widget_verses';

  /// Simple class name of the Kotlin provider.
  static const String providerName = 'BibleVerseWidgetProvider';

  /// Fully qualified class name of the Kotlin provider.
  static const String providerQualifiedName =
      'com.estudyantego.app.BibleVerseWidgetProvider';

  /// Shown by the provider when no verse data has been pushed yet.
  /// (The Kotlin side carries the same wording; keep them in sync.)
  static const String placeholderText =
      "Open EstudyanteGO to load today's verse";

  /// Default scene: the sample's sunset/cross photo (Philippians
  /// 4:13's background). Used when a verse has no mapping and for
  /// the empty state.
  static const String defaultScene = 'sunset_cross';

  /// The exact NATURE scene names this side can put in the pushed
  /// verse-list JSON (BibleVerseWidgetProvider.sceneDrawable maps
  /// these plus the season scenes — all_saints, all_souls,
  /// immaculate_conception, epiphany, advent, christmas, lent,
  /// ordinary_time — which never appear in the verse list but DO
  /// appear in the today-pair's `scene`, the resolved background).
  /// Keep this list in sync with the nature rows of
  /// sceneDrawable — a scene the provider does not know falls
  /// back to the default there too, but the mapping below must
  /// only ever produce names from this list. Each name is a
  /// photo: `res/drawable/verse_bg_<name>.webp`.
  static const List<String> knownScenes = [
    'sunset_cross',
    'mountain_sunrise',
    'calm_sea',
    'forest_light',
  ];

  /// Verse id -> nature scene. This is the FALLBACK background:
  /// the season/feast photo (fixed feast, Advent, Christmas,
  /// Lent, Ordinary Time) is shown first, and only in a season
  /// with no photo yet (Easter Time, the Easter Triduum) does
  /// the widget show the verse's photo from this mapping. Each
  /// verse gets the photo that fits its theme (Steven, Nov 8).
  /// The sample's sunset/cross is Philippians 4:13's scene (v03).
  /// The photos are AI-generated WebP (Steven's explicit ask, Nov 8),
  /// wide landscape, no text baked in:
  ///  - sunset_cross: sunset with a cross on a hill (the sample)
  ///  - mountain_sunrise: mountain peaks at sunrise, cross at right
  ///  - calm_sea: calm ocean at dawn
  ///  - forest_light: sun rays through a forest
  static const Map<String, String> verseScenes = {
    // Strength + the sample: the cross at sunset.
    'v03': 'sunset_cross', // Philippians 4:13 — the sample scene
    'v06': 'sunset_cross', // Isaiah 41:10
    'v08': 'sunset_cross', // Joshua 1:9
    'v10': 'sunset_cross', // Psalm 46:1 (refuge and strength)
    'v12': 'sunset_cross', // 1 Corinthians 13:4 (love, warm sunset)
    'v18': 'sunset_cross', // 2 Timothy 1:7
    // Faith, hope, dawn: mountains at sunrise (steadfast peaks,
    // new-morning light — "new every morning", "let your light
    // shine", "mount up with wings as eagles").
    'v01': 'mountain_sunrise', // John 3:16
    'v04': 'mountain_sunrise', // Jeremiah 29:11 (hope)
    'v07': 'mountain_sunrise', // Romans 8:28
    'v11': 'mountain_sunrise', // Matthew 5:16 (let your light shine)
    'v13': 'mountain_sunrise', // Romans 12:12 (rejoicing in hope)
    'v16': 'mountain_sunrise', // Matthew 6:33
    'v17': 'mountain_sunrise', // Isaiah 40:31 (eagles mount up)
    'v20': 'mountain_sunrise', // Proverbs 16:3
    'v21': 'mountain_sunrise', // Lamentations 3:22-23 (new every morning)
    'v24': 'mountain_sunrise', // Colossians 3:23
    'v26': 'mountain_sunrise', // Matthew 7:7
    'v27': 'mountain_sunrise', // Hebrews 11:1 (faith)
    'v29': 'mountain_sunrise', // Romans 15:13 (God of hope)
    // Peace / rest: still waters at dawn.
    'v09': 'calm_sea', // Matthew 11:28 (rest)
    'v14': 'calm_sea', // Philippians 4:6 (peace)
    'v30': 'calm_sea', // 1 Peter 5:7 (casting cares)
    // Guidance / light, gratitude / creation: light breaking
    // through the trees (a lamp, a light on the path, thanks).
    'v02': 'forest_light', // Psalm 23:1 (the shepherd's pasture)
    'v05': 'forest_light', // Proverbs 3:5-6 (direct thy paths)
    'v15': 'forest_light', // Psalm 37:4 (delight)
    'v19': 'forest_light', // Psalm 119:105 (lamp unto my feet)
    'v22': 'forest_light', // 1 Thessalonians 5:18 (give thanks)
    'v23': 'forest_light', // Psalm 100:4 (thanksgiving)
    'v25': 'forest_light', // James 1:5 (wisdom)
    'v28': 'forest_light', // Psalm 27:1 (my light)
  };

  /// Pure: the scene for a bundled verse, or the default when the
  /// verse has no mapping (defensive — every bundled id is mapped,
  /// so this only fires for a verse added later without a scene).
  static String sceneForVerse(BundledVerse v) =>
      verseScenes[v.id] ?? defaultScene;

  /// The SEASON / feast scene names (fixed feasts + liturgical
  /// seasons). These never appear in the pushed verse-list JSON
  /// (that only carries a nature scene) — they appear in the
  /// today-pair's `scene`, the resolved background. Keep this
  /// list in sync with the season rows of
  /// BibleVerseWidgetProvider.sceneDrawable. Each name is a
  /// photo: `res/drawable/verse_bg_<name>.webp`.
  static const List<String> seasonScenes = [
    'all_saints',
    'all_souls',
    'immaculate_conception',
    'epiphany',
    'advent',
    'christmas',
    'lent',
    'ordinary_time',
  ];

  /// Liturgical season windows (inclusive). Movable seasons start
  /// on different dates each year — add the new year's window
  /// when the year turns. Dates verified Nov 8, 2026 against the
  /// USCCB Liturgical Calendar 2027 (see the full table in
  /// BibleVerseWidgetProvider); the Kotlin provider carries the
  /// SAME windows, and the two must stay in sync. A `null` scene
  /// is a season with no photo yet (Easter Time, the Triduum) —
  /// the caller then falls back to the verse's nature photo.
  static final List<_SeasonWindow> _seasonWindows = [
    // Epiphany — the Sunday between Jan 2 and Jan 8 (explicit dates).
    _SeasonWindow(DateTime(2027, 1, 3), DateTime(2027, 1, 3), 'epiphany'),
    _SeasonWindow(DateTime(2028, 1, 2), DateTime(2028, 1, 2), 'epiphany'),
    // Advent 2026: First Sunday of Advent Nov 29 – Dec 24.
    _SeasonWindow(DateTime(2026, 11, 29), DateTime(2026, 12, 24), 'advent'),
    // Christmas 2026–27: Dec 25 – Baptism of the Lord, Jan 10.
    _SeasonWindow(DateTime(2026, 12, 25), DateTime(2027, 1, 10), 'christmas'),
    // Lent 2027: Ash Wednesday Feb 10 – Holy Thursday Mar 25.
    _SeasonWindow(DateTime(2027, 2, 10), DateTime(2027, 3, 25), 'lent'),
    // Easter Triduum 2027: Mar 26–27 (no photo yet).
    _SeasonWindow(DateTime(2027, 3, 26), DateTime(2027, 3, 27), null),
    // Easter Time 2027: Mar 28 – Pentecost, May 16 (no photo yet).
    _SeasonWindow(DateTime(2027, 3, 28), DateTime(2027, 5, 16), null),
    // Advent 2027: First Sunday of Advent Nov 28 – Dec 24.
    _SeasonWindow(DateTime(2027, 11, 28), DateTime(2027, 12, 24), 'advent'),
    // Christmas 2027–28: Dec 25 – Baptism of the Lord, Jan 9.
    _SeasonWindow(DateTime(2027, 12, 25), DateTime(2028, 1, 9), 'christmas'),
    // Lent 2028: Ash Wednesday Mar 1 – Holy Thursday Apr 13.
    _SeasonWindow(DateTime(2028, 3, 1), DateTime(2028, 4, 13), 'lent'),
    // Easter Triduum 2028: Apr 14–15 (no photo yet).
    _SeasonWindow(DateTime(2028, 4, 14), DateTime(2028, 4, 15), null),
    // Easter Time 2028: Apr 16 – Pentecost, Jun 4 (no photo yet).
    _SeasonWindow(DateTime(2028, 4, 16), DateTime(2028, 6, 4), null),
  ];

  /// Pure: the liturgical season/feast scene for [date], or null
  /// when the date is in a season that has no photo yet (the
  /// Easter Triduum / Easter Time — the caller then falls back
  /// to the verse's nature photo). Fixed feasts are checked FIRST
  /// so they override the season they fall in (Dec 8 is inside
  /// Advent; Epiphany is inside Christmas). Ordinary Time — any
  /// date in no feast and no window — returns 'ordinary_time'
  /// (the dedicated Ordinary Time photo). Mirrors
  /// BibleVerseWidgetProvider.seasonSceneForDate (Kotlin): the
  /// same date must return the same scene on both sides.
  static String? seasonSceneForDate(DateTime date) {
    // Fixed feasts — the same date every year.
    if (date.month == 11 && date.day == 1) return 'all_saints';
    if (date.month == 11 && date.day == 2) return 'all_souls';
    if (date.month == 12 && date.day == 8) return 'immaculate_conception';
    for (final w in _seasonWindows) {
      if (w.contains(date)) return w.scene;
    }
    return 'ordinary_time';
  }

  /// Pure: the RESOLVED background for [date] and [verse] — the
  /// season/feast photo when the date has one, else the verse's
  /// nature photo. This is the background the today-pair carries.
  static String sceneForDate(DateTime date, BundledVerse verse) =>
      seasonSceneForDate(date) ?? sceneForVerse(verse);

  /// Pure: index into a [count]-long day-of-year rotation for [date].
  /// Mirrors [verseOfDay] in student_data.dart — Jan 1 is index 0 and
  /// the rotation wraps, so Dec 31 of a leap year (day 366) and of a
  /// common year (day 365) land on different verses. Returns 0 when
  /// [count] is not positive.
  static int verseIndexForDate(DateTime date, int count) {
    if (count <= 0) return 0;
    return (dayOfYear(date) - 1) % count;
  }

  /// Pure: today's verse from an already-decoded list, or null when
  /// the list is empty (the widget shows the placeholder then).
  static BibleWidgetVerse? verseForDate(
    List<BibleWidgetVerse> verses,
    DateTime date,
  ) {
    if (verses.isEmpty) return null;
    return verses[verseIndexForDate(date, verses.length)];
  }

  /// Encodes the full bundled list (or [verses] when given) as the
  /// JSON the provider reads.
  static String encodeVerses([List<BundledVerse> verses = bundledVerses]) {
    return jsonEncode(
      verses.map((v) => BibleWidgetVerse.fromBundled(v).toJson()).toList(),
    );
  }

  /// Decodes a pushed verse list. Returns [] for null, empty,
  /// non-list, or malformed JSON — the provider treats that as
  /// "no data yet" and shows the placeholder, never a crash.
  static List<BibleWidgetVerse> decodeVerses(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => BibleWidgetVerse.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// SharedPreferences key holding today's verse + background as
  /// ONE pair (a single JSON object). See [todayPair].
  static const String todayKey = 'bible_widget_today';

  /// Pure: today's verse + background as ONE pair — a single
  /// JSON object {'date', 'id', 'ref', 'text', 'scene'} where
  /// 'scene' is the RESOLVED background from [sceneForDate]
  /// (season/feast or the verse's nature photo). The app writes
  /// this pair in one [HomeWidget.saveWidgetData] call and the
  /// provider applies both in a single RemoteViews update, so
  /// the verse and the photo can never drift apart (Steven,
  /// Nov 8: "Dapat nag Sync yung verse, photo ah"). The 'date'
  /// is the day the pair was picked for, so the provider can
  /// tell a stale pair (the app wasn't opened across a season
  /// boundary) from a fresh one and fall back to deriving both
  /// from today instead of showing yesterday's verse.
  static Map<String, dynamic> todayPair(DateTime date) {
    final verse = verseOfDay(date);
    return {
      'date': _dateKey(date),
      'id': verse.id,
      'ref': verse.ref,
      'text': verse.text,
      'scene': sceneForDate(date, verse),
    };
  }

  /// Encodes today's pair as the single JSON string the provider reads.
  static String encodeTodayPair(DateTime date) => jsonEncode(todayPair(date));

  /// Decodes a today-pair, or null when it is missing, malformed,
  /// or for a different date than [date] (stale — the provider
  /// then derives both from the list + its own season table).
  /// (The provider does the real parsing in Kotlin; this is the
  /// testable mirror of that check.)
  static Map<String, dynamic>? decodeTodayPair(String? raw, DateTime date) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final d = decoded['date'];
      final id = decoded['id'];
      final ref = decoded['ref'];
      final text = decoded['text'];
      final scene = decoded['scene'];
      if (d != _dateKey(date)) return null;
      if (id is! String || ref is! String || text is! String) return null;
      if (scene is! String) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Pushes the full bundled verse list AND today's verse +
  /// background pair to the widget store, then asks the provider
  /// to refresh. The pair is written in ONE saveWidgetData call
  /// (verse + background together — never in separate steps),
  /// so a refresh can never leave the widget showing a new verse
  /// with an old photo. The full list is the provider's fallback
  /// (it derives today's verse + background from it when the
  /// pair is stale). Best-effort: never throws, so callers
  /// (Bible screen initState) can fire-and-forget it.
  static Future<void> syncVerses() async {
    try {
      final now = DateTime.now();
      await HomeWidget.saveWidgetData<String>(versesKey, encodeVerses());
      await HomeWidget.saveWidgetData<String>(todayKey, encodeTodayPair(now));
      await HomeWidget.updateWidget(
        androidName: providerName,
        qualifiedAndroidName: providerQualifiedName,
      );
    } catch (_) {
      // No widget plugin (tests, iOS) or a platform failure: the
      // in-app Bible screen must keep working either way.
    }
  }
}
