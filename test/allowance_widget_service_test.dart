import 'package:estudyantego/features/student/allowance_widget_service.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';

// Allowance / Money home screen widgets (Nov 11, 2026): small 4x2
// "Allowance" + big 4x3 "Money", approved preview v1. The figures
// below are TEST FIXTURES only — the widget itself reads the
// student's stored transactions, goals, and budgets and never
// hardcodes them. In particular the preview's ₱10,000 SAMPLE
// balance is NOT here: with no transactions the balance is the
// real ₱0.00, and with fixtures it is income minus expenses.
void main() {
  final now = DateTime(2026, 11, 12, 10, 0);

  List<AllowanceTxn> fixtureTxns() => [
        AllowanceTxn(
          id: 't1',
          kind: 'income',
          amount: 5000,
          category: 'Allowance',
          note: 'Weekly allowance',
          date: DateTime(2026, 11, 2),
        ),
        AllowanceTxn(
          id: 't2',
          kind: 'expense',
          amount: 60,
          category: 'Transport',
          note: 'Bus fare',
          date: DateTime(2026, 11, 11),
        ),
        AllowanceTxn(
          id: 't3',
          kind: 'expense',
          amount: 120,
          category: 'Food',
          note: 'Lunch',
          date: DateTime(2026, 11, 12),
        ),
        AllowanceTxn(
          id: 't4',
          kind: 'expense',
          amount: 400,
          category: 'Food',
          note: 'Groceries',
          date: DateTime(2026, 10, 20),
        ),
      ];

  List<SavingsGoal> fixtureGoals() => [
        SavingsGoal(id: 'g1', name: 'New shoes', target: 2000, saved: 500),
      ];

  List<BudgetLimit> fixtureBudgets() => [
        BudgetLimit(id: 'b1', category: 'Food', limit: 100),
        BudgetLimit(id: 'b2', category: 'Transport', limit: 500),
      ];

  AllowanceWidgetData decodeFixture() {
    final raw = AllowanceWidgetService.encodeData(
      fixtureTxns(),
      fixtureGoals(),
      fixtureBudgets(),
      now,
    );
    final data = AllowanceWidgetService.decodeData(raw);
    expect(data, isNotNull);
    return data!;
  }

  test('balance is income minus expenses from stored transactions', () {
    final data = decodeFixture();
    // 5000 − 60 − 120 − 400 = 4420. Never the preview's ₱10,000 sample.
    expect(data.balance, 4420);
  });

  test('month totals cover only the payload month', () {
    final data = decodeFixture();
    expect(data.monthKey, '2026-11');
    expect(data.monthIncome, 5000);
    // November expenses only: 60 + 120 (the October ₱400 is excluded).
    expect(data.monthExpense, 180);
  });

  test('spending chart is the last 6 months, oldest first', () {
    final data = decodeFixture();
    expect(data.months.length, 6);
    expect(data.months.map((m) => m.label).toList(),
        ['Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov']);
    expect(data.months[4].amount, 400); // Oct
    expect(data.months[5].amount, 180); // Nov
    expect(data.months.take(4).every((m) => m.amount == 0), isTrue);
  });

  test('budget utilization is this month spend over limit', () {
    final data = decodeFixture();
    final food = data.budgets.firstWhere((b) => b.category == 'Food');
    // November Food spend is ₱120 of a ₱100 limit: over budget.
    expect(food.spent, 120);
    expect(food.limit, 100);
    expect(food.overBudget, isTrue);
    expect(food.utilization, 1.0); // clamped for the bar
    final transport =
        data.budgets.firstWhere((b) => b.category == 'Transport');
    expect(transport.spent, 60);
    expect(transport.utilization, closeTo(0.12, 0.001));
  });

  test('savings progress is saved over target', () {
    final data = decodeFixture();
    expect(data.goals.length, 1);
    expect(data.goals.first.progress, 0.25);
  });

  test('recent transactions are newest first, at most 4', () {
    final data = decodeFixture();
    expect(data.recent.length, 4);
    expect(data.recent.first.title, 'Lunch');
    expect(data.recent.first.kind, 'expense');
    // A transaction with no note shows its category.
    final noNote = AllowanceWidgetTxn.fromTxn(AllowanceTxn(
      id: 't5',
      kind: 'expense',
      amount: 20,
      category: 'Load',
      note: '',
      date: DateTime(2026, 11, 12),
    ));
    expect(noNote.title, 'Load');
  });

  test('empty store: real zero balance, no invented figures', () {
    final raw = AllowanceWidgetService.encodeData([], [], [], now);
    final data = AllowanceWidgetService.decodeData(raw);
    expect(data, isNotNull);
    expect(data!.balance, 0);
    expect(data.monthIncome, 0);
    expect(data.monthExpense, 0);
    expect(data.months.every((m) => m.amount == 0), isTrue);
    expect(data.budgets, isEmpty);
    expect(data.goals, isEmpty);
    expect(data.recent, isEmpty);
    expect(data.hasNoTransactions, isTrue);
  });

  test('decodeData returns null for missing or malformed JSON', () {
    expect(AllowanceWidgetService.decodeData(null), isNull);
    expect(AllowanceWidgetService.decodeData(''), isNull);
    expect(AllowanceWidgetService.decodeData('not json'), isNull);
    expect(AllowanceWidgetService.decodeData('{"balance": "x"}'), isNull);
    expect(AllowanceWidgetService.decodeData('[]'), isNull);
  });

  test('monthKeyFor pads single-digit months', () {
    expect(AllowanceWidgetService.monthKeyFor(DateTime(2026, 1, 5)),
        '2026-01');
    expect(AllowanceWidgetService.monthKeyFor(DateTime(2026, 11, 12)),
        '2026-11');
  });

  test('encode/decode round-trips the payload', () {
    final data = decodeFixture();
    final again = AllowanceWidgetService.decodeData(
        AllowanceWidgetService.encodeData(
            fixtureTxns(), fixtureGoals(), fixtureBudgets(), now));
    expect(again, data);
  });
}
