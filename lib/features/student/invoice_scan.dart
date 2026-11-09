// Invoice / receipt / statement parsing for the Allowance Files
// scan — pure Dart, no plugins, so it is unit-testable.
//
// The scan reads real text (ML Kit OCR for photos, pdfrx text layer
// for PDFs — see NoteExtractService) and pulls out what the review
// sheet needs: the merchant, the receipt date, the total, and one
// draft transaction per amount line. Nothing here invents a value:
// when a field cannot be found it stays null and the review sheet
// leaves it blank for the student to fill in.

/// One draft transaction pulled from a scanned file. [kind] is
/// 'expense' unless the line clearly reads as a credit.
class ScannedTxn {
  const ScannedTxn({
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    this.kind = 'expense',
  });

  final String title;
  final double amount;
  final DateTime date;
  final String category;
  final String kind;
}

/// What the parser found in one file's text.
class InvoiceParseResult {
  const InvoiceParseResult({
    required this.merchant,
    required this.date,
    required this.total,
    required this.items,
  });

  /// Merchant / biller name, or null when no header line qualifies.
  final String? merchant;

  /// Receipt / statement date, or null when no date pattern matches.
  final DateTime? date;

  /// The receipt total ("TOTAL", "Amount due", "Balance"), or null.
  final double? total;

  /// One draft per amount line (empty when nothing parseable).
  final List<ScannedTxn> items;
}

/// Guess a budget category from a merchant / item title.
String guessCategory(String title) {
  final t = title.toLowerCase();
  if (t.contains('gcash') ||
      t.contains('load') ||
      t.contains('top up') ||
      t.contains('top-up')) {
    return 'Load';
  }
  if (t.contains('jollibee') ||
      t.contains('grabfood') ||
      t.contains('grab food') ||
      t.contains('food') ||
      t.contains('burger') ||
      t.contains('restaurant') ||
      t.contains('mcdonald') ||
      t.contains('chicken') ||
      t.contains('pizza') ||
      t.contains('spaghetti') ||
      t.contains('pasta') ||
      t.contains('fries') ||
      t.contains('meal') ||
      t.contains('rice') ||
      t.contains('noodle')) {
    return 'Food';
  }
  if (t.contains('fare') ||
      t.contains('bus') ||
      t.contains('jeep') ||
      t.contains('tricycle') ||
      t.contains('transport')) {
    return 'Transport';
  }
  if (t.contains('tuition') ||
      t.contains('school') ||
      t.contains('book') ||
      t.contains('enrollment')) {
    return 'School';
  }
  if (t.contains('movie') ||
      t.contains('cinema') ||
      t.contains('netflix') ||
      t.contains('spotify')) {
    return 'Entertainment';
  }
  if (t.contains('pharmacy') ||
      t.contains('clinic') ||
      t.contains('hospital') ||
      t.contains('medicine')) {
    return 'Health';
  }
  if (t.contains('allowance')) return 'Allowance';
  return 'Other';
}

// An amount must carry a currency mark or a decimal point — a bare
// integer could be a quantity, a year, or an OR number, never money.
final _amountRe =
    RegExp(r'(?:₱|P|PHP)\s?(\d[\d,]*(?:\.\d{1,2})?)|(\d[\d,]*\.\d{1,2})');

double? _parseAmount(String s) {
  final m = _amountRe.firstMatch(s);
  if (m == null) return null;
  final raw = (m.group(1) ?? m.group(2) ?? '').replaceAll(',', '');
  final value = double.tryParse(raw);
  if (value == null || value <= 0) return null;
  return value;
}

/// The amount at the END of a line ("GCash - Buy Load 100.00"),
/// or null when the line does not end in money.
double? _trailingAmount(String line) {
  final m = RegExp(
          r'(?:₱|P|PHP)?\s?(\d[\d,]*(?:\.\d{1,2})?)\s*$')
      .firstMatch(line);
  if (m == null) return null;
  final raw = m.group(1)!.replaceAll(',', '');
  final value = double.tryParse(raw);
  if (value == null || value <= 0) return null;
  // A trailing 4-digit year (2026) or a bare count is not money.
  if (!line.contains(RegExp(r'₱|P|\.')) && raw.length == 4) return null;
  return value;
}

const _monthNames = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

/// "Nov 9, 2026", "9 Nov 2026", "11/09/2026" (PH receipts read
/// month first), "2026-11-09". Returns null when nothing matches.
DateTime? parseReceiptDate(String text) {
  final named = RegExp(
          r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b')
      .firstMatch(text);
  if (named != null) {
    final month = _monthNames[named.group(1)!.toLowerCase()];
    if (month != null) {
      final day = int.tryParse(named.group(2)!);
      final year = int.tryParse(named.group(3)!);
      if (day != null && year != null) {
        return DateTime(year, month, day);
      }
    }
  }
  final dayFirst = RegExp(
          r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b')
      .firstMatch(text);
  if (dayFirst != null) {
    final month = _monthNames[dayFirst.group(2)!.toLowerCase()];
    if (month != null) {
      final day = int.tryParse(dayFirst.group(1)!);
      final year = int.tryParse(dayFirst.group(3)!);
      if (day != null && year != null) {
        return DateTime(year, month, day);
      }
    }
  }
  final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
  if (iso != null) {
    final year = int.tryParse(iso.group(1)!);
    final month = int.tryParse(iso.group(2)!);
    final day = int.tryParse(iso.group(3)!);
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day);
    }
  }
  final numeric =
      RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b').firstMatch(text);
  if (numeric != null) {
    var month = int.tryParse(numeric.group(1)!);
    var day = int.tryParse(numeric.group(2)!);
    var year = int.tryParse(numeric.group(3)!);
    if (month != null && day != null && year != null) {
      if (year < 100) year += 2000;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }
  }
  return null;
}

bool _isTotalLine(String lower) =>
    lower.contains('total') ||
    lower.contains('amount due') ||
    lower.contains('balance due') ||
    lower.contains('grand total');

bool _isMetaLine(String lower) =>
    lower.contains('subtotal') ||
    lower.contains('sub total') ||
    lower.contains('vat') ||
    lower.contains('tax') ||
    lower.contains('change') ||
    lower.contains('cash tendered') ||
    lower.contains('amount tendered') ||
    lower.startsWith('cash ') ||
    lower == 'cash' ||
    lower.contains('or no') ||
    lower.contains('invoice no') ||
    lower.contains('receipt no') ||
    lower.contains('terminal') ||
    lower.contains('cashier') ||
    lower.contains('official receipt') ||
    lower.contains('sales invoice') ||
    lower.contains('bir ') ||
    lower.contains('tin:') ||
    lower.contains('thank you') ||
    lower.contains('this serves as');

bool _isHeaderLine(String lower) =>
    lower.contains('receipt') ||
    lower.contains('invoice') ||
    lower.contains('statement') ||
    lower.contains('official') ||
    lower.contains('sales') ||
    lower.contains('bpi') && lower.contains('bank');

/// Pull merchant, date, total, and one draft per amount line out of
/// OCR / PDF text. A statement with several debit lines yields one
/// draft per line; a simple receipt with only a total yields one
/// draft for the total.
InvoiceParseResult parseInvoiceText(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  String? merchant;
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (_trailingAmount(line) != null) continue;
    if (_isHeaderLine(lower) || _isMetaLine(lower)) continue;
    if (line.length < 2 || line.length > 60) continue;
    merchant = line;
    break;
  }

  final date = parseReceiptDate(text);

  double? total;
  for (final line in lines) {
    if (!_isTotalLine(line.toLowerCase())) continue;
    final amount = _parseAmount(line);
    if (amount != null) total = amount;
  }

  final items = <ScannedTxn>[];
  final fallbackDate = date ?? DateTime.now();
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (_isTotalLine(lower) || _isMetaLine(lower)) continue;
    final amount = _trailingAmount(line);
    if (amount == null) continue;
    var title = line
        .replaceFirst(
            RegExp(r'(?:₱|P|PHP)?\s?\d[\d,]*(?:\.\d{1,2})?\s*$'), '')
        .trim();
    title = title.replaceAll(RegExp(r'^[-–—\s]+'), '').trim();
    if (title.isEmpty) title = merchant ?? 'Scanned item';
    items.add(ScannedTxn(
      title: title,
      amount: amount,
      date: fallbackDate,
      category: guessCategory(title),
    ));
  }

  // One amount only, and it was the total: the receipt itself is
  // the transaction.
  if (items.isEmpty && total != null) {
    items.add(ScannedTxn(
      title: merchant ?? 'Scanned receipt',
      amount: total,
      date: fallbackDate,
      category: guessCategory(merchant ?? ''),
    ));
  }

  return InvoiceParseResult(
    merchant: merchant,
    date: date,
    total: total,
    items: items,
  );
}
