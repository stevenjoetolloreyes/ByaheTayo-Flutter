// Widget tests for the APPROVED 7-Day Sign-in redesign (Nov 2
// previews): the Student Hub card and the full Details Page.
// Every asserted value comes from seeded records or a fake ledger
// — nothing here hardcodes the UI's numbers; different seeds must
// (and do) render different values. Dates are relative to today so
// the streak math holds on any run day. Records carry Manila dates
// only (no time-of-day is stored), so history rows show dates.
import 'dart:convert';

import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/points_wallet_repository.dart';
import 'package:estudyantego/features/student/signin_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Existing repo image used as a stand-in profile photo (tests must
/// never create files — async file creation hangs the tester in
/// this sandbox).
const _photoA = 'assets/images/estudyantego_logo.png';

DateTime _daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: n));
}

/// Seeds the legacy local check-in log: [days] are dayIndexes for
/// consecutive days ending [endOffset] days ago (0 = today).
Future<void> _seedLocal(List<int> days, {int endOffset = 0}) async {
  final records = <Map<String, dynamic>>[];
  for (var i = 0; i < days.length; i++) {
    final date = _daysAgo(endOffset + days.length - 1 - i);
    records.add(CheckinRecord(
      id: 'seed-$i',
      date: date,
      dayIndex: days[i],
      points: pointsForDay(days[i]),
    ).toJson());
  }
  SharedPreferences.setMockInitialValues({
    StudentStorage.checkinsKey: jsonEncode(records),
  });
}

/// Tall viewport so a full StudentTab / SigninScreen list builds.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Minimal in-memory ledger fake (mirrors the production reward
/// table: Day 1-6 = 10, Day 7 = 50, one credit per Manila date).
class _FakeLedger implements PointsWalletRepository {
  final Map<String, PointsTransaction> _txns = {};

  @override
  Future<PointsWallet> fetchWallet(String uid) async {
    final entries = await fetchTransactions(uid);
    var sum = 0;
    for (final e in entries) {
      sum += e.points;
    }
    return PointsWallet(balance: sum, totalEarned: sum);
  }

  @override
  Future<List<PointsTransaction>> fetchTransactions(String uid) async {
    final entries = _txns.values.where((e) => e.userId == uid).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Future<bool> claimSignin({
    required String uid,
    required String manilaDate,
    required int dayIndex,
    required int points,
  }) async {
    if (dayIndex < 1 ||
        dayIndex > 7 ||
        points != pointsForDay(dayIndex)) {
      throw ArgumentError('Invalid sign-in reward');
    }
    final ref = signinReferenceId(uid, manilaDate);
    if (_txns.containsKey(ref)) return false;
    _txns[ref] = PointsTransaction(
      id: ref,
      userId: uid,
      type: 'signin',
      points: points,
      description: signinDescription(dayIndex),
      source: 'signin',
      referenceId: ref,
      date: manilaDate,
      dayIndex: dayIndex,
      status: 'completed',
    );
    return true;
  }

  @override
  Future<int> migrateSignin({
    required String uid,
    required List<CheckinRecord> records,
  }) async =>
      0;

  void seed(String uid, String manilaDate, int dayIndex) {
    final ref = signinReferenceId(uid, manilaDate);
    _txns[ref] = PointsTransaction(
      id: ref,
      userId: uid,
      type: 'signin',
      points: pointsForDay(dayIndex),
      description: signinDescription(dayIndex),
      source: 'signin',
      referenceId: ref,
      date: manilaDate,
      dayIndex: dayIndex,
      status: 'completed',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Hub card renders real 3-day state from records',
      (tester) async {
    _tallScreen(tester);
    await _seedLocal([1, 2, 3]);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StudentTab())));
    await tester.pumpAndSettle();
    expect(find.text('7-Day Sign-in'), findsOneWidget);
    expect(find.text('Build your study habit and earn rewards!'),
        findsOneWidget);
    expect(find.text('Day 3 of 7'), findsOneWidget);
    expect(find.text('3 / 7 Days'), findsOneWidget);
    expect(find.text('Total Points'), findsOneWidget);
    expect(find.text('Current Streak'), findsOneWidget);
    expect(find.text('Next Reward'), findsOneWidget);
    // Stat values are scoped to the card: other Hub sections
    // render bare numbers too (e.g. verse references, counts).
    final card = find.byKey(const ValueKey('signin-hub-card'));
    expect(find.descendant(of: card, matching: find.text('30')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('3 days')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('50 Points')),
        findsOneWidget);
  });

  testWidgets('Hub card empty state shows Day 1, zero progress',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StudentTab())));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 7'), findsOneWidget);
    expect(find.text('0 / 7 Days'), findsOneWidget);
    final card = find.byKey(const ValueKey('signin-hub-card'));
    expect(find.descendant(of: card, matching: find.text('0')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('0 days')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('50 Points')),
        findsOneWidget);
  });

  testWidgets('Hub card Next Reward opens the reward schedule',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StudentTab())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next Reward'));
    await tester.pumpAndSettle();
    expect(find.text('Reward schedule'), findsOneWidget);
    expect(find.text('Day 1 – 6: 10 points each'), findsOneWidget);
    expect(
        find.text('Day 7: 50 points (completion reward)'),
        findsOneWidget);
    expect(find.text('Full cycle: 110 points'), findsOneWidget);
  });

  testWidgets('Details page shows hero, cycle, rewards, history',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SigninScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Study Rewards'), findsOneWidget);
    expect(find.text('This Cycle'), findsOneWidget);
    expect(find.text('Resets in 7 days'), findsOneWidget);
    expect(find.text('Check in today · Day 1'), findsOneWidget);
    expect(find.text('Daily Rewards'), findsOneWidget);
    expect(find.text('Check-in History'), findsOneWidget);
    expect(find.text('No check-in history yet.'), findsOneWidget);
    expect(find.text('Total Points'), findsOneWidget);
    expect(find.text('0 pts'), findsOneWidget);
    expect(
      find.text('Dates follow this phone\'s calendar (Asia/Manila). '
          'Points are saved on this device only and are separate '
          'from the Account Points Wallet.'),
      findsOneWidget,
    );
  });

  testWidgets('Details page claim locks the button, no double claim',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SigninScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check in today · Day 1'));
    await tester.pumpAndSettle();
    expect(find.text('Already checked in today'), findsOneWidget);
    expect(find.text('Check in today · Day 1'), findsNothing);
    expect(find.text('1 / 7 Days'), findsOneWidget);
    expect(find.text(formatDate(DateTime.now())), findsOneWidget);
    // Pills are scoped to the history card: the day tiles also
    // show "+10 pts" labels, so a global count would mix them.
    final history = find.byKey(const ValueKey('signin-history'));
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsOneWidget,
    );
    // Tapping the locked pill must not create a second record.
    await tester.tap(find.text('Already checked in today'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsOneWidget,
    );
    expect(find.text('1 / 7 Days'), findsOneWidget);
  });

  testWidgets('Details page Day 7 claim completes the cycle',
      (tester) async {
    _tallScreen(tester);
    // Six consecutive days ending yesterday: next claim is Day 7.
    await _seedLocal([1, 2, 3, 4, 5, 6], endOffset: 1);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SigninScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Check in today · Day 7'), findsOneWidget);
    expect(find.text('6 / 7 Days'), findsOneWidget);
    expect(find.text('Resets in 1 day'), findsOneWidget);
    await tester.tap(find.text('Check in today · Day 7'));
    await tester.pumpAndSettle();
    expect(find.text('Already checked in today'), findsOneWidget);
    expect(find.text('7 / 7 Days'), findsOneWidget);
    expect(find.text('Cycle complete!'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('signin-history')),
        matching: find.text('+50 pts'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Details page history View All expands the full log',
      (tester) async {
    _tallScreen(tester);
    await _seedLocal([1, 2, 3, 4, 5, 6, 7]);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SigninScreen())));
    await tester.pumpAndSettle();
    expect(find.text('View All'), findsOneWidget);
    // Newest 5 rows: Day 7 (+50) + Days 6-3 (+10 x4).
    final history = find.byKey(const ValueKey('signin-history'));
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsNWidgets(4),
    );
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(
      find.descendant(of: history, matching: find.text('+10 pts')),
      findsNWidgets(6),
    );
  });

  testWidgets(
      'Details page in remote mode shows the live wallet balance',
      (tester) async {
    _tallScreen(tester);
    final repo = _FakeLedger();
    repo.seed('uid-1', '2026-10-30', 1);
    repo.seed('uid-1', '2026-10-31', 2);
    final controller = PointsWalletController(
      repository: repo,
      clock: () => DateTime.utc(2026, 11, 1, 2),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SigninScreen(
          userId: 'uid-1',
          walletController: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('20 pts'), findsOneWidget);
    expect(find.text('2 / 7 Days'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('Check in today · Day 3'), findsOneWidget);
    expect(find.text('Resets in 5 days'), findsOneWidget);
    expect(
      find.text('Dates follow Asia/Manila time. Points are saved to '
          'your account and show in your Account Points Wallet.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Welcome-card avatar work still passes through StudentTab',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentTab(
          profile: const UserProfile(
            displayName: 'Steven',
            email: 'steven@example.com',
            photoPath: _photoA,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Student Hub'), findsOneWidget);
    final avatar = tester.widgetList<CircleAvatar>(
      find.byWidgetPredicate((w) =>
          w is CircleAvatar && w.backgroundImage is FileImage),
    );
    expect(avatar, isNotEmpty);
  });
}
