import 'package:estudyantego/features/student/daily_quotes_widget_service.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

// Daily Quotes home screen widgets (Nov 11, 2026): 4x2, 3x3, and
// 4x3, approved preview v2. The widget shows the quote ONLY —
// large over a Minecraft block background, with a small green
// "Daily Quote" pill — and picks today's quote by day-of-year
// from the app's bundled list, exactly like the Quotes screen's
// quoteOfDay. No attribution is ever invented: the author comes
// from the bundled quote itself.
void main() {
  test('today quote matches the Quotes screen quoteOfDay', () {
    final quotes = DailyQuotesWidgetService.decodeQuotes(
        DailyQuotesWidgetService.encodeQuotes());
    for (final date in [
      DateTime(2026, 1, 1),
      DateTime(2026, 11, 12),
      DateTime(2026, 12, 31),
      DateTime(2027, 1, 1),
    ]) {
      final widgetQuote =
          DailyQuotesWidgetService.quoteForDate(quotes, date);
      final screenQuote = quoteOfDay(date);
      expect(widgetQuote, isNotNull);
      expect(widgetQuote!.id, screenQuote.id);
      expect(widgetQuote.text, screenQuote.text);
      expect(widgetQuote.author, screenQuote.author);
    }
  });

  test('rotation wraps at the end of the list', () {
    final quotes = DailyQuotesWidgetService.decodeQuotes(
        DailyQuotesWidgetService.encodeQuotes());
    final count = quotes.length;
    expect(count, greaterThan(1));
    // Jan 1 is index 0; the day that wraps lands on the first quote.
    final wrapDate = DateTime(2026, 1, 1).add(Duration(days: count));
    expect(
        DailyQuotesWidgetService.quoteForDate(quotes, wrapDate)!.id,
        quotes.first.id);
  });

  test('quoteIndexForDate is 0 for an empty list', () {
    expect(DailyQuotesWidgetService.quoteIndexForDate(DateTime(2026, 11, 12), 0), 0);
    expect(DailyQuotesWidgetService.quoteForDate([], DateTime(2026, 11, 12)),
        isNull);
  });

  test('encode carries the full bundled list with real authors', () {
    final quotes = DailyQuotesWidgetService.decodeQuotes(
        DailyQuotesWidgetService.encodeQuotes());
    expect(quotes.length, bundledQuotes.length);
    expect(quotes.every((q) => q.author.isNotEmpty), isTrue);
    expect(quotes.every((q) => q.text.isNotEmpty), isTrue);
    expect(quotes.map((q) => q.id).toSet().length, quotes.length);
  });

  test('decodeQuotes returns [] for missing or malformed JSON', () {
    expect(DailyQuotesWidgetService.decodeQuotes(null), isEmpty);
    expect(DailyQuotesWidgetService.decodeQuotes(''), isEmpty);
    expect(DailyQuotesWidgetService.decodeQuotes('not json'), isEmpty);
    expect(DailyQuotesWidgetService.decodeQuotes('{"id": "q01"}'), isEmpty);
    expect(DailyQuotesWidgetService.decodeQuotes('[{"id": 1}]'), isEmpty);
  });

  test('encode/decode round-trips the payload', () {
    final raw = DailyQuotesWidgetService.encodeQuotes();
    final first = DailyQuotesWidgetService.decodeQuotes(raw);
    final second = DailyQuotesWidgetService.decodeQuotes(raw);
    expect(second, first);
    expect(first.length, bundledQuotes.length);
  });
}
