// Daily Quotes home screen widgets — Dart side (Android only).
//
// DESIGN (why this shape): like the Bible Verse widget
// (bible_widget_service.dart), the Dart side pushes the FULL
// bundled quote list once as JSON and the Kotlin providers pick
// today's quote by day-of-year themselves on every update
// (updatePeriodMillis 30 min). The single source of truth stays
// the bundled list in student_data.dart — nothing here re-lists
// the quotes, so a future quote edit flows to the widget with the
// next Quotes screen open. The rotation is the app's own
// quoteOfDay (day-of-year over bundledQuotes), so the widget and
// the Quotes screen can never disagree about today's quote.
//
// QUOTE ONLY, VERSE-STYLE: the approved preview v2 (Nov 11,
// 2026) shows the quote large over a Minecraft block background
// (sky / grass / dirt blocks, NO photo) with a small green
// "Daily Quote" pill — the same pill shape as the Verse widget's
// "Psalm 37:4" pill. There is no photo on any size, and no
// attribution is ever invented: the author comes from the
// bundled quote itself.
//
// THREE SIZES, ONE PAYLOAD: the 4x2, 3x3, and 4x3 providers all
// read the same `daily_quotes_widget_data` JSON, so they can
// never disagree. The Kotlin providers render different layouts
// from the same list.
//
// TAP: tapping any size opens the app's Daily Quotes screen. The
// Kotlin providers launch the app with the
// `homewidget://quotes` URI (HomeWidgetLaunchIntent) and the app
// root listens for it (see _EstudyanteGOAppState in main.dart) —
// only when the dashboard is showing (signed in, profile done);
// on the sign-in or setup screens the tap just opens the app.
//
// The push is best-effort and never throws: widget tests run
// without the plugin, and the Quotes screen must never break
// because the widget plugin is unavailable. The provider shows a
// placeholder ("Open EstudyanteGO to load today's quote") when no
// quote data has been pushed yet.
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'student_data.dart';

/// One quote as the widget understands it: id + text + author +
/// category, straight from the bundled list.
class DailyQuotesWidgetQuote {
  const DailyQuotesWidgetQuote({
    required this.id,
    required this.text,
    required this.author,
    required this.category,
  });

  factory DailyQuotesWidgetQuote.fromBundled(BundledQuote q) =>
      DailyQuotesWidgetQuote(
        id: q.id,
        text: q.text,
        author: q.author,
        category: q.category,
      );

  factory DailyQuotesWidgetQuote.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final text = json['text'];
    final author = json['author'];
    final category = json['category'];
    if (id is! String ||
        text is! String ||
        author is! String ||
        category is! String) {
      throw const FormatException('Daily Quotes widget quote is malformed');
    }
    return DailyQuotesWidgetQuote(
      id: id,
      text: text,
      author: author,
      category: category,
    );
  }

  final String id;
  final String text;
  final String author;
  final String category;

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'author': author, 'category': category};

  @override
  bool operator ==(Object other) =>
      other is DailyQuotesWidgetQuote &&
      other.id == id &&
      other.text == text &&
      other.author == author &&
      other.category == category;

  @override
  int get hashCode => Object.hash(id, text, author, category);
}

class DailyQuotesWidgetService {
  DailyQuotesWidgetService._();

  /// SharedPreferences key (inside the home_widget store) holding
  /// the full quote list JSON.
  static const String quotesKey = 'daily_quotes_widget_quotes';

  /// Small 4x2 provider.
  static const String providerName = 'DailyQuotesWidgetProvider';
  static const String providerQualifiedName =
      'com.estudyantego.app.DailyQuotesWidgetProvider';

  /// Square 3x3 provider.
  static const String squareProviderName = 'DailyQuotesSquareWidgetProvider';
  static const String squareProviderQualifiedName =
      'com.estudyantego.app.DailyQuotesSquareWidgetProvider';

  /// Big 4x3 provider.
  static const String largeProviderName = 'DailyQuotesLargeWidgetProvider';
  static const String largeProviderQualifiedName =
      'com.estudyantego.app.DailyQuotesLargeWidgetProvider';

  /// URI the providers launch with on tap. The app root listens
  /// for it (HomeWidget.widgetClicked /
  /// initiallyLaunchedFromHomeWidget) and opens the Daily Quotes
  /// screen when the dashboard is showing.
  static const String quotesUri = 'homewidget://quotes';

  /// Shown by the providers when no quote data has been pushed
  /// yet. (The Kotlin side carries the same wording; keep them in
  /// sync.)
  static const String placeholderText =
      "Open EstudyanteGO to load today's quote";

  /// The green pill label on every size, as in the approved
  /// preview. (The Kotlin side carries the same wording.)
  static const String pillLabel = 'Daily Quote';

  /// Pure: index into a [count]-long day-of-year rotation for
  /// [date]. Mirrors [quoteOfDay] in student_data.dart — Jan 1 is
  /// index 0 and the rotation wraps. Returns 0 when [count] is
  /// not positive.
  static int quoteIndexForDate(DateTime date, int count) {
    if (count <= 0) return 0;
    return (dayOfYear(date) - 1) % count;
  }

  /// Pure: today's quote from an already-decoded list, or null
  /// when the list is empty (the widget shows the placeholder
  /// then).
  static DailyQuotesWidgetQuote? quoteForDate(
    List<DailyQuotesWidgetQuote> quotes,
    DateTime date,
  ) {
    if (quotes.isEmpty) return null;
    return quotes[quoteIndexForDate(date, quotes.length)];
  }

  /// Encodes the full bundled list (or [quotes] when given) as the
  /// JSON the providers read.
  static String encodeQuotes(
      [List<BundledQuote> quotes = bundledQuotes]) {
    return jsonEncode(
      quotes.map((q) => DailyQuotesWidgetQuote.fromBundled(q).toJson()).toList(),
    );
  }

  /// Decodes a pushed quote list. Returns [] for null, empty,
  /// non-list, or malformed JSON — the provider treats that as
  /// "no data yet" and shows the placeholder, never a crash.
  static List<DailyQuotesWidgetQuote> decodeQuotes(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => DailyQuotesWidgetQuote.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Pushes the full bundled quote list to the widget store, then
  /// asks all THREE providers to refresh. Best-effort: never
  /// throws, so callers (Quotes screen initState, app start) can
  /// fire-and-forget it.
  static Future<void> syncQuotes() async {
    try {
      await HomeWidget.saveWidgetData<String>(quotesKey, encodeQuotes());
      await HomeWidget.updateWidget(
        androidName: providerName,
        qualifiedAndroidName: providerQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: squareProviderName,
        qualifiedAndroidName: squareProviderQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: largeProviderName,
        qualifiedAndroidName: largeProviderQualifiedName,
      );
    } catch (_) {
      // No widget plugin (tests, iOS) or a platform failure: the
      // in-app Quotes screen must keep working either way.
    }
  }
}
