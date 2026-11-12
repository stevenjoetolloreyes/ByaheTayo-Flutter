// Allowance / Money home screen widgets — Dart side (Android only).
//
// DESIGN (why this shape): like the Schedule widget
// (schedule_widget_service.dart), the Dart side pushes the FULL
// allowance picture as ONE JSON blob and the Kotlin providers
// render from it on every update (updatePeriodMillis 30 min). The
// single source of truth stays the app's stored allowance lists —
// the SAME SharedPreferences lists the Allowance screen reads
// (StudentStorage.txnsKey / goalsKey / budgetsKey). Nothing here
// re-lists transactions, so a Manual add, an invoice scan, a new
// savings goal, or a budget limit flows to the widget with the
// next sync call.
//
// REAL BALANCE, NOT THE PREVIEW SAMPLE: the approved preview v1
// (Nov 11, 2026) showed a ₱10,000 SAMPLE balance. The widget
// shows the REAL balance — income minus expenses from the
// student's stored transactions (currently ₱0.00 when there are
// none) — never the sample. Likewise the preview's sample budgets
// and savings goals are NOT carried over: when the student has
// set none, the widget says so plainly ("No budget limits set.",
// "No savings goals yet.") instead of inventing any.
//
// MONTH TOTALS GO STALE ACROSS A MONTH BOUNDARY: the payload
// carries its month key ("2026-11"); the providers render the
// "This month" row only when the payload's month is the current
// month, and show "Open EstudyanteGO to refresh this month."
// otherwise. The balance is month-independent, so it always
// renders. The sync runs at app start and on every Allowance
// save, so the payload is fresh whenever the app runs.
//
// TAP: tapping either widget opens the app's Allowance screen.
// The Kotlin providers launch the app with the
// `homewidget://allowance` URI (HomeWidgetLaunchIntent) and the
// app root listens for it (see _EstudyanteGOAppState in main.dart)
// — only when the dashboard is showing (signed in, profile done);
// on the sign-in or setup screens the tap just opens the app.
//
// The push is best-effort and never throws: widget tests run
// without the plugin, and the Allowance screen must never break
// because the widget plugin is unavailable. The provider shows an
// honest empty state ("No transactions yet.") when no allowance
// data has been pushed yet.
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'student_data.dart';

/// One budget as the widget understands it: category + monthly
/// limit + what was spent in the payload's month.
class AllowanceWidgetBudget {
  const AllowanceWidgetBudget({
    required this.category,
    required this.limit,
    required this.spent,
  });

  factory AllowanceWidgetBudget.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final limit = json['limit'];
    final spent = json['spent'];
    if (category is! String || limit is! num || spent is! num) {
      throw const FormatException('Allowance widget budget is malformed');
    }
    return AllowanceWidgetBudget(
      category: category,
      limit: limit.toDouble(),
      spent: spent.toDouble(),
    );
  }

  final String category;
  final double limit;
  final double spent;

  /// 0.0–1.0 share of the limit spent this month. Over budget
  /// clamps to 1.0 for the bar; the numbers still show the real
  /// overspend.
  double get utilization =>
      limit <= 0 ? 0 : (spent / limit).clamp(0.0, 1.0).toDouble();

  bool get overBudget => limit > 0 && spent > limit;

  Map<String, dynamic> toJson() =>
      {'category': category, 'limit': limit, 'spent': spent};

  @override
  bool operator ==(Object other) =>
      other is AllowanceWidgetBudget &&
      other.category == category &&
      other.limit == limit &&
      other.spent == spent;

  @override
  int get hashCode => Object.hash(category, limit, spent);
}

/// One savings goal as the widget understands it: name + saved +
/// target.
class AllowanceWidgetGoal {
  const AllowanceWidgetGoal({
    required this.name,
    required this.saved,
    required this.target,
  });

  factory AllowanceWidgetGoal.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final saved = json['saved'];
    final target = json['target'];
    if (name is! String || saved is! num || target is! num) {
      throw const FormatException('Allowance widget goal is malformed');
    }
    return AllowanceWidgetGoal(
      name: name,
      saved: saved.toDouble(),
      target: target.toDouble(),
    );
  }

  final String name;
  final double saved;
  final double target;

  /// 0.0–1.0 share of the target saved.
  double get progress =>
      target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> toJson() =>
      {'name': name, 'saved': saved, 'target': target};

  @override
  bool operator ==(Object other) =>
      other is AllowanceWidgetGoal &&
      other.name == name &&
      other.saved == saved &&
      other.target == target;

  @override
  int get hashCode => Object.hash(name, saved, target);
}

/// One recent transaction as the widget understands it: kind +
/// amount + category + note + date (ISO day, for the row label).
class AllowanceWidgetTxn {
  const AllowanceWidgetTxn({
    required this.kind,
    required this.amount,
    required this.category,
    required this.note,
    required this.date,
  });

  factory AllowanceWidgetTxn.fromTxn(AllowanceTxn t) => AllowanceWidgetTxn(
        kind: t.kind,
        amount: t.amount,
        category: t.category,
        note: t.note,
        date: DateTime(t.date.year, t.date.month, t.date.day),
      );

  factory AllowanceWidgetTxn.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final amount = json['amount'];
    final category = json['category'];
    final note = json['note'];
    final date = json['date'];
    if (kind is! String ||
        amount is! num ||
        category is! String ||
        note is! String ||
        date is! String) {
      throw const FormatException(
          'Allowance widget transaction is malformed');
    }
    return AllowanceWidgetTxn(
      kind: kind,
      amount: amount.toDouble(),
      category: category,
      note: note,
      date: DateTime.parse(date),
    );
  }

  final String kind; // 'income' | 'expense'
  final double amount;
  final String category;
  final String note;
  final DateTime date;

  /// What the row shows: the note when there is one, else the
  /// category (same rule as the Allowance screen's rows).
  String get title => note.isEmpty ? category : note;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'amount': amount,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is AllowanceWidgetTxn &&
      other.kind == kind &&
      other.amount == amount &&
      other.category == category &&
      other.note == note &&
      other.date == date;

  @override
  int get hashCode => Object.hash(kind, amount, category, note, date);
}

/// One month of expenses for the spending chart: label + amount.
/// Oldest first, exactly like lastMonthsExpense in student_data.
class AllowanceWidgetMonth {
  const AllowanceWidgetMonth({required this.label, required this.amount});

  factory AllowanceWidgetMonth.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final amount = json['amount'];
    if (label is! String || amount is! num) {
      throw const FormatException('Allowance widget month is malformed');
    }
    return AllowanceWidgetMonth(label: label, amount: amount.toDouble());
  }

  final String label;
  final double amount;

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};

  @override
  bool operator ==(Object other) =>
      other is AllowanceWidgetMonth &&
      other.label == label &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(label, amount);
}

/// The whole allowance payload the providers read.
class AllowanceWidgetData {
  const AllowanceWidgetData({
    required this.balance,
    required this.monthKey,
    required this.monthIncome,
    required this.monthExpense,
    this.months = const [],
    this.budgets = const [],
    this.goals = const [],
    this.recent = const [],
  });

  factory AllowanceWidgetData.fromJson(Map<String, dynamic> json) {
    final balance = json['balance'];
    final monthKey = json['monthKey'];
    final monthIncome = json['monthIncome'];
    final monthExpense = json['monthExpense'];
    final months = json['months'];
    final budgets = json['budgets'];
    final goals = json['goals'];
    final recent = json['recent'];
    if (balance is! num ||
        monthKey is! String ||
        monthIncome is! num ||
        monthExpense is! num ||
        months is! List ||
        budgets is! List ||
        goals is! List ||
        recent is! List) {
      throw const FormatException('Allowance widget data is malformed');
    }
    return AllowanceWidgetData(
      balance: balance.toDouble(),
      monthKey: monthKey,
      monthIncome: monthIncome.toDouble(),
      monthExpense: monthExpense.toDouble(),
      months: months
          .map((e) => AllowanceWidgetMonth.fromJson(e as Map<String, dynamic>))
          .toList(),
      budgets: budgets
          .map((e) =>
              AllowanceWidgetBudget.fromJson(e as Map<String, dynamic>))
          .toList(),
      goals: goals
          .map((e) => AllowanceWidgetGoal.fromJson(e as Map<String, dynamic>))
          .toList(),
      recent: recent
          .map((e) => AllowanceWidgetTxn.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final double balance;

  /// "2026-11" — the month [monthIncome]/[monthExpense] and the
  /// budget `spent` figures belong to.
  final String monthKey;
  final double monthIncome;
  final double monthExpense;
  final List<AllowanceWidgetMonth> months;
  final List<AllowanceWidgetBudget> budgets;
  final List<AllowanceWidgetGoal> goals;
  final List<AllowanceWidgetTxn> recent;

  /// True when there are no stored transactions at all — the
  /// provider shows the honest "No transactions yet." state (the
  /// balance is still the real ₱0.00, not a placeholder).
  bool get hasNoTransactions => recent.isEmpty && balance == 0;

  Map<String, dynamic> toJson() => {
        'balance': balance,
        'monthKey': monthKey,
        'monthIncome': monthIncome,
        'monthExpense': monthExpense,
        'months': months.map((m) => m.toJson()).toList(),
        'budgets': budgets.map((b) => b.toJson()).toList(),
        'goals': goals.map((g) => g.toJson()).toList(),
        'recent': recent.map((t) => t.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is AllowanceWidgetData &&
      other.balance == balance &&
      other.monthKey == monthKey &&
      other.monthIncome == monthIncome &&
      other.monthExpense == monthExpense &&
      _monthsEqual(other.months, months) &&
      _budgetsEqual(other.budgets, budgets) &&
      _goalsEqual(other.goals, goals) &&
      _txnsEqual(other.recent, recent);

  @override
  int get hashCode => Object.hash(
        balance,
        monthKey,
        monthIncome,
        monthExpense,
        Object.hashAll(months),
        Object.hashAll(budgets),
        Object.hashAll(goals),
        Object.hashAll(recent),
      );
}

bool _monthsEqual(List<AllowanceWidgetMonth> a, List<AllowanceWidgetMonth> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _budgetsEqual(
    List<AllowanceWidgetBudget> a, List<AllowanceWidgetBudget> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _goalsEqual(List<AllowanceWidgetGoal> a, List<AllowanceWidgetGoal> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _txnsEqual(List<AllowanceWidgetTxn> a, List<AllowanceWidgetTxn> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class AllowanceWidgetService {
  AllowanceWidgetService._();

  /// SharedPreferences key (inside the home_widget store) holding
  /// the allowance JSON both providers read.
  static const String dataKey = 'allowance_widget_data';

  /// Small 4x2 "Allowance" provider.
  static const String providerName = 'AllowanceWidgetProvider';
  static const String providerQualifiedName =
      'com.estudyantego.app.AllowanceWidgetProvider';

  /// Big 4x3 "Money" provider.
  static const String moneyProviderName = 'AllowanceMoneyWidgetProvider';
  static const String moneyProviderQualifiedName =
      'com.estudyantego.app.AllowanceMoneyWidgetProvider';

  /// URI the providers launch with on tap. The app root listens
  /// for it (HomeWidget.widgetClicked /
  /// initiallyLaunchedFromHomeWidget) and opens the Allowance
  /// screen when the dashboard is showing.
  static const String allowanceUri = 'homewidget://allowance';

  /// Shown by the providers when no allowance data has been pushed
  /// yet. (The Kotlin side carries the same wording; keep them in
  /// sync.)
  static const String emptyTitle = 'No transactions yet.';
  static const String emptySubtitle =
      'Add a transaction to track your allowance.';

  /// Shown by the big widget when the student has set no budget
  /// limits. (The Kotlin side carries the same wording.)
  static const String noBudgets = 'No budget limits set.';

  /// Shown by the big widget when the student has set no savings
  /// goals. (The Kotlin side carries the same wording.)
  static const String noGoals = 'No savings goals yet.';

  /// How many months the spending chart carries (same 6 as the
  /// Allowance screen's chart).
  static const int chartMonths = 6;

  /// How many budgets / goals / recent transactions the big widget
  /// lists at most; more than that renders as "+N more".
  static const int maxBudgets = 3;
  static const int maxGoals = 2;
  static const int maxRecent = 4;

  /// Pure: "2026-11" for [now] — the month key the payload and
  /// the providers agree on.
  static String monthKeyFor(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}';

  /// Encodes the widget payload from the app's stored lists, for
  /// [now]. Balance, month totals, and the 6-month chart come
  /// from the same pure helpers the Allowance screen uses
  /// (allowanceBalance / monthTotals / lastMonthsExpense), so the
  /// widget and the screen can never disagree. Budget `spent` is
  /// this month's spend in that category. Recent transactions are
  /// newest first.
  static String encodeData(
    List<AllowanceTxn> txns,
    List<SavingsGoal> goals,
    List<BudgetLimit> budgets,
    DateTime now,
  ) {
    final sorted = List.of(txns)
      ..sort((a, b) => b.date.compareTo(a.date));
    final month = monthTotals(txns, now.year, now.month);
    final bars = lastMonthsExpense(txns, now, chartMonths);
    final budgetRows = budgets.map((b) {
      final spent = txns
          .where((t) =>
              t.kind == 'expense' &&
              t.category == b.category &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold<double>(0, (s, t) => s + t.amount);
      return AllowanceWidgetBudget(
          category: b.category, limit: b.limit, spent: spent);
    }).toList();
    return jsonEncode(AllowanceWidgetData(
      balance: allowanceBalance(txns),
      monthKey: monthKeyFor(now),
      monthIncome: month.income,
      monthExpense: month.expense,
      months: bars
          .map((b) => AllowanceWidgetMonth(label: b.label, amount: b.amount))
          .toList(),
      budgets: budgetRows,
      goals: goals
          .map((g) => AllowanceWidgetGoal(
              name: g.name, saved: g.saved, target: g.target))
          .toList(),
      recent: sorted
          .take(maxRecent)
          .map(AllowanceWidgetTxn.fromTxn)
          .toList(),
    ).toJson());
  }

  /// Decodes a pushed payload. Returns null for null, empty,
  /// non-map, or malformed JSON — the provider treats that as "no
  /// data yet" and shows the empty state, never a crash.
  static AllowanceWidgetData? decodeData(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AllowanceWidgetData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Pushes the student's current allowance to the widget store,
  /// then asks BOTH providers to refresh. The payload is written
  /// in ONE saveWidgetData call, so a refresh can never leave one
  /// widget showing a new balance with old budgets. Best-effort:
  /// never throws, so callers (Allowance screen saves, app start)
  /// can fire-and-forget it.
  static Future<void> sync() async {
    try {
      final now = DateTime.now();
      final txns = (await StudentStorage.loadList(StudentStorage.txnsKey))
          .map(AllowanceTxn.fromJson)
          .toList();
      final goals = (await StudentStorage.loadList(StudentStorage.goalsKey))
          .map(SavingsGoal.fromJson)
          .toList();
      final budgets =
          (await StudentStorage.loadList(StudentStorage.budgetsKey))
              .map(BudgetLimit.fromJson)
              .toList();
      await HomeWidget.saveWidgetData<String>(
          dataKey, encodeData(txns, goals, budgets, now));
      await HomeWidget.updateWidget(
        androidName: providerName,
        qualifiedAndroidName: providerQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: moneyProviderName,
        qualifiedAndroidName: moneyProviderQualifiedName,
      );
    } catch (_) {
      // No widget plugin (tests, iOS) or a platform failure: the
      // Allowance screen and app start must keep working either way.
    }
  }
}
