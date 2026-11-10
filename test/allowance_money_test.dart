// Tests for the Money redesign (Nov 9, 2026, approved preview):
// the invoice parser, the spending/grouping helpers, the redesigned
// hub card (tallest green month, "Most spent in …", Set limit /
// New goal buttons, date-grouped recent transactions, no floating
// + on the hub card), and the Allowance screen (floating + spring
// menu, Manual add flow, grouped list).
//
// The preview dataset drives the expectations throughout: Allowance
// +₱10,000, GCash Buy Load −₱100, GCash Sent to Carlo P. −₱150,
// GrabFood −₱770 → November ₱1,020, synced balance ₱8,980. Dates
// are seeded relative to today (clamped into this month) so the
// tests hold on any day.
import 'dart:convert';

import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/student/allowance_screen.dart';
import 'package:estudyantego/features/student/invoice_scan.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The preview dataset, dated in the current month (never future).
List<AllowanceTxn> _previewTxns() {
  final now = DateTime.now();
  int day(int d) => d.clamp(1, now.day);
  DateTime at(int d) => DateTime(now.year, now.month, day(d));
  return [
    AllowanceTxn(
        id: 'a1',
        kind: 'income',
        amount: 10000,
        category: 'Allowance',
        note: '',
        date: at(4)),
    AllowanceTxn(
        id: 'e1',
        kind: 'expense',
        amount: 100,
        category: 'Load',
        note: 'GCash — Buy Load',
        date: at(9)),
    AllowanceTxn(
        id: 'e2',
        kind: 'expense',
        amount: 150,
        category: 'Load',
        note: 'GCash — Sent to Carlo P.',
        date: at(9)),
    AllowanceTxn(
        id: 'e3',
        kind: 'expense',
        amount: 770,
        category: 'Food',
        note: 'GrabFood',
        date: at(6)),
  ];
}

void main() {
  group('invoice parser', () {
    test('Jollibee receipt: merchant, date, total, two items', () {
      const text = '''
JOLLIBEE
123 Main Street, Vigan City
OR No. 0045123
Date: Nov 9, 2026
Chickenjoy Solo  129.00
Jolly Spaghetti  89.00
TOTAL  ₱218.00
Cash  500.00
Change  282.00
Thank you!
''';
      final r = parseInvoiceText(text);
      expect(r.merchant, 'JOLLIBEE');
      expect(r.date, DateTime(2026, 11, 9));
      expect(r.total, 218);
      expect(r.items.length, 2);
      expect(r.items[0].title, 'Chickenjoy Solo');
      expect(r.items[0].amount, 129);
      expect(r.items[0].category, 'Food');
      expect(r.items[1].title, 'Jolly Spaghetti');
      expect(r.items[1].amount, 89);
      // Cash tendered / change / OR number are never items.
      expect(r.items.any((i) => i.title.contains('Cash')), isFalse);
      expect(r.items.any((i) => i.title.contains('Change')), isFalse);
    });

    test('BPI statement: three debit lines become three drafts', () {
      const text = '''
BPI
Bank of the Philippine Islands
Statement of Account
Nov 1 - Nov 9, 2026
GCash - Buy Load 100.00
GCash - Sent to Carlo P. 150.00
GrabFood 770.00
Total Debits 1,020.00
''';
      final r = parseInvoiceText(text);
      expect(r.merchant, 'BPI');
      expect(r.date, DateTime(2026, 11, 9));
      expect(r.total, 1020);
      expect(r.items.length, 3);
      expect(r.items[0].title, 'GCash - Buy Load');
      expect(r.items[0].amount, 100);
      expect(r.items[0].category, 'Load');
      expect(r.items[1].amount, 150);
      expect(r.items[2].title, 'GrabFood');
      expect(r.items[2].amount, 770);
      expect(r.items[2].category, 'Food');
    });

    test('receipt with only a total becomes one transaction', () {
      const text = '''
SARI-SARI STORE
Nov 8, 2026
TOTAL ₱350.00
''';
      final r = parseInvoiceText(text);
      expect(r.merchant, 'SARI-SARI STORE');
      expect(r.total, 350);
      expect(r.items.length, 1);
      expect(r.items[0].title, 'SARI-SARI STORE');
      expect(r.items[0].amount, 350);
    });

    test('empty text finds nothing and invents nothing', () {
      final r = parseInvoiceText('');
      expect(r.merchant, isNull);
      expect(r.date, isNull);
      expect(r.total, isNull);
      expect(r.items, isEmpty);
    });

    test('receipt dates: named, numeric, and ISO', () {
      expect(parseReceiptDate('Paid on Nov 9, 2026'), DateTime(2026, 11, 9));
      expect(parseReceiptDate('Date: 11/09/2026'), DateTime(2026, 11, 9));
      expect(parseReceiptDate('2026-11-09'), DateTime(2026, 11, 9));
      expect(parseReceiptDate('9 Nov 2026'), DateTime(2026, 11, 9));
      expect(parseReceiptDate('no date here'), isNull);
    });

    test('guessCategory maps merchants to budget categories', () {
      expect(guessCategory('GCash — Buy Load'), 'Load');
      expect(guessCategory('GrabFood delivery'), 'Food');
      expect(guessCategory('Partas bus fare'), 'Transport');
      expect(guessCategory('Unknown shop'), 'Other');
    });
  });

  group('money helpers', () {
    test('preview dataset: balance 8980, November 1020', () {
      final txns = _previewTxns();
      final now = DateTime.now();
      expect(allowanceBalance(txns), 8980);
      final bars = lastMonthsExpense(txns, now, 6);
      expect(bars.length, 6);
      expect(bars.last.amount, 1020);
      expect(bars.sublist(0, 5).every((b) => b.amount == 0), isTrue);
      expect(
          bars.fold<double>(0, (s, b) => s + b.amount), 1020);
    });

    test('spendingRangeLabel stays in-year and spans years', () {
      expect(spendingRangeLabel(DateTime(2026, 11, 9), 6), 'Jun – Nov 2026');
      expect(
          spendingRangeLabel(DateTime(2026, 4, 15), 6), 'Nov 2025 – Apr 2026');
    });

    test('groupTxnsByDay groups newest day first', () {
      final groups = groupTxnsByDay(_previewTxns());
      final now = DateTime.now();
      int day(int d) => d.clamp(1, now.day);
      final day9 = DateTime(now.year, now.month, day(9));
      final day6 = DateTime(now.year, now.month, day(6));
      if (day9 == day6) {
        expect(groups.length, 1);
        expect(groups.first.txns.length, 3);
      } else {
        // Nov 9 (two expenses), Nov 6 (one), Nov 4 (the income).
        expect(groups.length, 3);
        expect(groups.first.day, day9);
        expect(groups.first.txns.length, 2);
        expect(groups[1].day, day6);
        expect(groups[1].txns.length, 1);
        expect(groups.last.txns.length, 1);
      }
      expect(dayHeaderLabel(DateTime(2026, 11, 9)), 'Nov 9');
    });
  });

  group('money hub card', () {
    Future<void> pumpHub(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        StudentStorage.txnsKey:
            jsonEncode(_previewTxns().map((t) => t.toJson()).toList()),
        StudentStorage.goalsKey: jsonEncode([]),
        StudentStorage.budgetsKey: jsonEncode([]),
      });
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: StudentHubTheme(child: const StudentTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder inMoneyCard(String text) => find.descendant(
          of: find
              .ancestor(
                of: find.text('Allowance & Budgeting'),
                matching: find.byType(MinecraftCard),
              )
              .first,
          matching: find.text(text),
        );

    testWidgets('redesigned card: total, most-spent, buttons, groups',
        (tester) async {
      await pumpHub(tester);
      final now = DateTime.now();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      expect(inMoneyCard('₱1,020 Total spent'), findsOneWidget);
      expect(inMoneyCard('Most spent in ${months[now.month - 1]}'),
          findsOneWidget);
      expect(inMoneyCard('No budget limits set yet.'), findsOneWidget);
      expect(inMoneyCard('Set limit'), findsOneWidget);
      expect(inMoneyCard('No savings goals yet.'), findsOneWidget);
      expect(inMoneyCard('New goal'), findsOneWidget);
      // The three most recent transactions (same sort + take as the
      // card), whatever day of the month the test runs on.
      final sorted = List.of(_previewTxns())
        ..sort((a, b) => b.date.compareTo(a.date));
      for (final t in sorted.take(3)) {
        expect(
            inMoneyCard(t.note.isEmpty ? t.category : t.note), findsOneWidget);
      }
      expect(inMoneyCard('−₱100'), findsOneWidget);
      // Date-grouped recent transactions, newest day first.
      expect(
          inMoneyCard(dayHeaderLabel(_previewTxns()[1].date)), findsOneWidget);
      // No floating + on the hub card — it lives only inside the
      // Allowance screen (Steven corrected this twice).
      expect(find.byKey(const ValueKey('money-fab')), findsNothing);
    });
  });

  group('allowance screen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        StudentStorage.txnsKey:
            jsonEncode(_previewTxns().map((t) => t.toJson()).toList()),
        StudentStorage.goalsKey: jsonEncode([]),
        StudentStorage.budgetsKey: jsonEncode([]),
      });
      // Tall viewport so the whole ListView builds (goals, budgets,
      // and transactions all sit below the fold at phone height).
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const AllowanceScreen(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('chart, groups, and floating + menu', (tester) async {
      await pumpScreen(tester);
      expect(find.text('₱8,980'), findsOneWidget);
      expect(find.text('₱1,020 Total spent'), findsOneWidget);
      expect(find.text('New goal'), findsOneWidget);
      expect(find.text('Set limit'), findsOneWidget);
      expect(find.text('GCash — Buy Load'), findsOneWidget);
      expect(find.text('GrabFood'), findsOneWidget);

      // Floating + opens the spring menu with both options.
      expect(find.byKey(const ValueKey('money-fab')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('money-fab')));
      await tester.pumpAndSettle();
      expect(find.text('Add transaction Manual'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);

      // Manual opens the by-hand form and saving adds the row.
      await tester.tap(find.byKey(const ValueKey('money-fab-manual')));
      await tester.pumpAndSettle();
      expect(find.text('Add transaction'), findsOneWidget);
      Finder field(String label) => find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          );
      await tester.enterText(field('Amount (₱)'), '150');
      await tester.enterText(field('Note (optional)'), 'Test lunch');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Test lunch'), findsOneWidget);
      expect(find.text('₱8,830'), findsOneWidget);
    });
  });
}
