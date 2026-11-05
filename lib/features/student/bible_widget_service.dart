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
// The push is best-effort and never throws: widget tests run
// without the plugin, and the Bible screen must never break
// because the widget plugin is unavailable. The provider shows a
// placeholder ("Open EstudyanteGO to load today's verse") when no
// verse data has been pushed yet.
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'student_data.dart';

/// One verse as the widget understands it: id + precomputed
/// reference + text. The reference is precomputed here so the
/// Kotlin side never has to rebuild "Book chapter:verse".
class BibleWidgetVerse {
  const BibleWidgetVerse({
    required this.id,
    required this.ref,
    required this.text,
  });

  factory BibleWidgetVerse.fromBundled(BundledVerse v) =>
      BibleWidgetVerse(id: v.id, ref: v.ref, text: v.text);

  factory BibleWidgetVerse.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ref = json['ref'];
    final text = json['text'];
    if (id is! String || ref is! String || text is! String) {
      throw const FormatException('Bible widget verse entry is malformed');
    }
    return BibleWidgetVerse(id: id, ref: ref, text: text);
  }

  final String id;

  /// e.g. "Matthew 11:28" — the widget appends " (KJV)".
  final String ref;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'ref': ref, 'text': text};

  @override
  bool operator ==(Object other) =>
      other is BibleWidgetVerse &&
      other.id == id &&
      other.ref == ref &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, ref, text);
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

  /// Pushes the full bundled verse list to the widget store and asks
  /// the provider to refresh. Best-effort: never throws, so callers
  /// (Bible screen initState) can fire-and-forget it.
  static Future<void> syncVerses() async {
    try {
      await HomeWidget.saveWidgetData<String>(versesKey, encodeVerses());
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
