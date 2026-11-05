// Tests for the unified Account Points Wallet + 7-Day Sign-in
// backend: ledger schema, Manila-day rules, atomic/idempotent
// claims, migration dedupe, wallet repair, and the Account /
// Sign-in UI wiring. The Firestore implementation is covered
// through an in-memory fake with identical semantics (claim dedupe
// by reference, reward-table validation, ledger-sum repair);
// on-device Firestore behavior is verified by the user on a cloud
// build after the rules are published.
import 'dart:convert';

import 'package:estudyantego/features/account_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/points_wallet_repository.dart';
import 'package:estudyantego/features/student/signin_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

/// In-memory [PointsWalletRepository] with the same semantics as
/// the Firestore implementation: claim dedupe by reference ID,
/// reward-table validation, wallet cache repaired from the ledger
/// sum on every fetch.
class FakePointsWalletRepository implements PointsWalletRepository {
  final Map<String, PointsTransaction> _txns = {};
  final Map<String, int> _cachedBalance = {};

  /// Simulates a drifted wallet cache (e.g. a partial write).
  void tamperWallet(String uid, int balance) {
    _cachedBalance[uid] = balance;
  }

  @override
  Future<PointsWallet> fetchWallet(String uid) async {
    final entries = await fetchTransactions(uid);
    var sum = 0;
    for (final e in entries) {
      sum += e.points;
    }
    // Repair: the ledger sum wins over any cached value.
    _cachedBalance[uid] = sum;
    return PointsWallet(balance: sum, totalEarned: sum);
  }

  @override
  Future<List<PointsTransaction>> fetchTransactions(String uid) async {
    final entries =
        _txns.values.where((e) => e.userId == uid).toList()
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
    if (dayIndex < 1 || dayIndex > 7 || points != pointsForDay(dayIndex)) {
      throw ArgumentError(
          'Invalid sign-in reward: day $dayIndex = $points points');
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
    final current = _cachedBalance[uid] ?? 0;
    _cachedBalance[uid] = current + points;
    return true;
  }

  @override
  Future<int> migrateSignin({
    required String uid,
    required List<CheckinRecord> records,
  }) async {
    final sorted = records.toList()
      ..sort((a, b) => dateKey(a.date).compareTo(dateKey(b.date)));
    var migrated = 0;
    for (final record in sorted) {
      if (record.points != 10 && record.points != 50) continue;
      final ref = signinReferenceId(uid, dateKey(record.date));
      if (_txns.containsKey(ref)) continue;
      _txns[ref] = PointsTransaction(
        id: ref,
        userId: uid,
        type: 'signin',
        points: record.points,
        description: signinDescription(record.dayIndex),
        source: 'migration',
        referenceId: ref,
        date: dateKey(record.date),
        dayIndex: record.dayIndex,
        status: 'completed',
      );
      final current = _cachedBalance[uid] ?? 0;
      _cachedBalance[uid] = current + record.points;
      migrated++;
    }
    return migrated;
  }
}

const _uid = 'uid-1';
const _user = AuthUser(
  uid: _uid,
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

/// Manila 10:00 on 2026-11-01 (UTC 02:00).
DateTime _manilaNov1() => DateTime.utc(2026, 11, 1, 2);

/// Advances a Manila-morning clock by [days] days.
DateTime _manilaPlus(DateTime base, int days) =>
    base.add(Duration(days: days));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Manila dates', () {
    test('UTC+8 boundary: 15:59 UTC is still the same Manila date',
        () {
      expect(manilaDateKey(DateTime.utc(2026, 11, 1, 15, 59)),
          '2026-11-01');
    });

    test('UTC+8 boundary: 16:00 UTC is the next Manila date', () {
      expect(manilaDateKey(DateTime.utc(2026, 11, 1, 16, 0)),
          '2026-11-02');
    });

    test('Manila morning maps to the same calendar date', () {
      expect(manilaDateKey(_manilaNov1()), '2026-11-01');
      expect(manilaDateKey(DateTime.utc(2026, 10, 31, 20, 0)),
          '2026-11-01');
    });

    test('reference ID embeds uid and Manila date', () {
      expect(signinReferenceId('abc', '2026-11-01'),
          'signin_abc_2026-11-01');
    });

    test('ledger entry round-trips through its document map', () {
      final entry = PointsTransaction(
        id: 'signin_uid-1_2026-11-01',
        userId: 'uid-1',
        type: 'signin',
        points: 10,
        description: '7-Day Sign-in — Day 1',
        source: 'signin',
        referenceId: 'signin_uid-1_2026-11-01',
        date: '2026-11-01',
        dayIndex: 1,
        status: 'completed',
      );
      final restored =
          PointsTransaction.fromDoc(entry.id, entry.toDoc());
      expect(restored.userId, 'uid-1');
      expect(restored.points, 10);
      expect(restored.referenceId, entry.id);
      expect(restored.date, '2026-11-01');
      expect(restored.dayIndex, 1);
      expect(restored.toCheckinRecord().dayIndex, 1);
    });
  });

  group('controller claims (user cases)', () {
    testWidgets('Day 1 claim +10 then Day 2 claim +10 = 20',
        (tester) async {
      final repo = FakePointsWalletRepository();
      var clock = _manilaNov1();
      final controller = PointsWalletController(
        repository: repo,
        clock: () => clock,
      );
      await controller.loadForUser(_uid);
      var outcome = await controller.claimToday();
      expect(outcome.status, ClaimStatus.credited);
      expect(outcome.dayIndex, 1);
      expect(outcome.points, 10);
      expect(controller.balance, 10);

      // The user's case: claim Day 1 Nov 1, return Nov 2 → Day 2.
      clock = _manilaPlus(clock, 1);
      outcome = await controller.claimToday();
      expect(outcome.status, ClaimStatus.credited);
      expect(outcome.dayIndex, 2);
      expect(outcome.points, 10);
      expect(controller.balance, 20);
      expect(controller.totalEarned, 20);
      expect(controller.entries.length, 2);
    });

    testWidgets('duplicate same-day claim credits nothing',
        (tester) async {
      final repo = FakePointsWalletRepository();
      final controller = PointsWalletController(
        repository: repo,
        clock: _manilaNov1,
      );
      await controller.loadForUser(_uid);
      final first = await controller.claimToday();
      expect(first.status, ClaimStatus.credited);
      final second = await controller.claimToday();
      expect(second.status, ClaimStatus.alreadyClaimed);
      expect(controller.balance, 10);
      expect(controller.entries.length, 1);
    });

    testWidgets('Day 7 pays 50, cycle totals 110, then Day 1 again',
        (tester) async {
      final repo = FakePointsWalletRepository();
      var clock = _manilaNov1();
      final controller = PointsWalletController(
        repository: repo,
        clock: () => clock,
      );
      await controller.loadForUser(_uid);
      for (var day = 1; day <= 7; day++) {
        final outcome = await controller.claimToday();
        expect(outcome.status, ClaimStatus.credited);
        expect(outcome.dayIndex, day);
        expect(outcome.points, day == 7 ? 50 : 10);
        clock = _manilaPlus(clock, 1);
      }
      expect(controller.balance, 110);
      expect(controller.totalEarned, 110);
      expect(controller.entries.length, 7);
      // New cycle starts the next day.
      final next = await controller.claimToday();
      expect(next.status, ClaimStatus.credited);
      expect(next.dayIndex, 1);
      expect(next.points, 10);
      expect(controller.balance, 120);
    });

    testWidgets('missed day resets the streak, points total preserved',
        (tester) async {
      final repo = FakePointsWalletRepository();
      await repo.claimSignin(
        uid: _uid,
        manilaDate: '2026-11-01',
        dayIndex: 1,
        points: 10,
      );
      // Nov 2 is skipped entirely; the user returns Nov 3.
      var clock = DateTime.utc(2026, 11, 3, 2);
      final controller = PointsWalletController(
        repository: repo,
        clock: () => clock,
      );
      await controller.loadForUser(_uid);
      final outcome = await controller.claimToday();
      expect(outcome.status, ClaimStatus.credited);
      expect(outcome.dayIndex, 1);
      expect(controller.balance, 20);
      clock = _manilaPlus(clock, 1);
      final following = await controller.claimToday();
      expect(following.dayIndex, 2);
    });

    testWidgets('every credit appears in history, newest first',
        (tester) async {
      final repo = FakePointsWalletRepository();
      var clock = _manilaNov1();
      final controller = PointsWalletController(
        repository: repo,
        clock: () => clock,
      );
      await controller.loadForUser(_uid);
      await controller.claimToday();
      clock = _manilaPlus(clock, 1);
      await controller.claimToday();
      expect(controller.entries.length, 2);
      expect(controller.entries.first.date, '2026-11-02');
      expect(controller.entries.first.description,
          '7-Day Sign-in — Day 2');
      expect(controller.entries.last.date, '2026-11-01');
    });

    testWidgets('reinstall with the same UID restores the balance',
        (tester) async {
      final repo = FakePointsWalletRepository();
      var clock = _manilaNov1();
      final first = PointsWalletController(
        repository: repo,
        clock: () => clock,
      );
      await first.loadForUser(_uid);
      await first.claimToday();
      clock = _manilaPlus(clock, 1);
      await first.claimToday();
      expect(first.balance, 20);

      // Fresh install: empty local cache, same backend, same UID.
      SharedPreferences.setMockInitialValues({});
      final reinstalled = PointsWalletController(
        repository: repo,
        clock: () => clock,
      );
      await reinstalled.loadForUser(_uid);
      expect(reinstalled.balance, 20);
      expect(reinstalled.totalEarned, 20);
      expect(reinstalled.entries.length, 2);
    });

    testWidgets('migration uploads local records once, re-runs are no-ops',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'byahetayo_student_checkins': jsonEncode([
          {
            'id': 'local-1',
            'date': '2026-10-30',
            'dayIndex': 1,
            'points': 10,
          },
          {
            'id': 'local-2',
            'date': '2026-10-31',
            'dayIndex': 2,
            'points': 10,
          },
          // Corrupt record: never a reward-table value.
          {'id': 'local-bad', 'date': '2026-10-29', 'dayIndex': 3, 'points': 999},
        ]),
      });
      final repo = FakePointsWalletRepository();
      final controller = PointsWalletController(
        repository: repo,
        clock: _manilaNov1,
      );
      await controller.loadForUser(_uid);
      expect(controller.balance, 20);
      expect(controller.entries.length, 2);
      expect(
        controller.entries.every((e) => e.source == 'migration'),
        isTrue,
      );

      // Second load (and a fresh controller) must not duplicate.
      final again = PointsWalletController(
        repository: repo,
        clock: _manilaNov1,
      );
      await again.loadForUser(_uid);
      expect(again.balance, 20);
      expect(again.entries.length, 2);
    });

    testWidgets('wallet cache drift is repaired from the ledger',
        (tester) async {
      final repo = FakePointsWalletRepository();
      await repo.claimSignin(
        uid: _uid,
        manilaDate: '2026-11-01',
        dayIndex: 1,
        points: 10,
      );
      repo.tamperWallet(_uid, 999);
      final controller = PointsWalletController(
        repository: repo,
        clock: _manilaNov1,
      );
      await controller.loadForUser(_uid);
      expect(controller.balance, 10);
    });

    testWidgets('invalid reward values are rejected, never credited',
        (tester) async {
      final repo = FakePointsWalletRepository();
      await expectLater(
        repo.claimSignin(
          uid: _uid,
          manilaDate: '2026-11-01',
          dayIndex: 3,
          points: 50,
        ),
        throwsArgumentError,
      );
      expect((await repo.fetchTransactions(_uid)).length, 0);
    });
  });

  group('UI wiring', () {
    testWidgets('Sign-in screen claims remotely and updates immediately',
        (tester) async {
      final repo = FakePointsWalletRepository();
      final controller = PointsWalletController(
        repository: repo,
        clock: _manilaNov1,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SigninScreen(
            userId: _uid,
            walletController: controller,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Check in today · Day 1'), findsOneWidget);
      await tester.tap(find.text('Check in today · Day 1'));
      await tester.pumpAndSettle();
      expect(find.text('Already checked in today'), findsOneWidget);
      expect(find.text('Check in today · Day 1'), findsNothing);
      expect(find.text('10 pts'), findsOneWidget);
      expect(controller.balance, 10);
      // The redesigned page is taller, so the footer note sits
      // below the fold until scrolled into view.
      await tester.scrollUntilVisible(
        find.text('Dates follow Asia/Manila time. Points are saved to '
            'your account and show in your Account Points Wallet.'),
        200,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Dates follow Asia/Manila time. Points are saved to '
            'your account and show in your Account Points Wallet.'),
        findsOneWidget,
      );
    });

    testWidgets('Account tab shows live balance, earned, and history',
        (tester) async {
      final repo = FakePointsWalletRepository();
      await repo.claimSignin(
        uid: _uid,
        manilaDate: '2026-11-01',
        dayIndex: 1,
        points: 10,
      );
      await repo.claimSignin(
        uid: _uid,
        manilaDate: '2026-11-02',
        dayIndex: 2,
        points: 10,
      );
      final controller = PointsWalletController(
        repository: repo,
        clock: _manilaNov1,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccountTab(
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) {},
            authService: FakeAuthService(user: _user),
            user: _user,
            profile: const UserProfile(
              displayName: 'Steven Reyes',
              email: 'steven@example.com',
            ),
            permissionService: FakePermissionService(),
            walletController: controller,
            onSignedOut: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('points-balance')))
            .data,
        '20 points',
      );
      // Approved Account preview: Total Earned is a stats label with
      // the value below it, not one "Total earned: N points" line.
      expect(find.text('Total Earned'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      await tester.ensureVisible(find.text('Transactions'));
      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();
      expect(find.text('7-Day Sign-in — Day 1'), findsOneWidget);
      expect(find.text('7-Day Sign-in — Day 2'), findsOneWidget);
      expect(find.text('+10 pts'), findsWidgets);
    });

    testWidgets('Account tab without a backend keeps the legacy display',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccountTab(
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) {},
            authService: FakeAuthService(user: _user),
            user: _user,
            profile: const UserProfile(
              displayName: 'Steven Reyes',
              email: 'steven@example.com',
            ),
            permissionService: FakePermissionService(),
            onSignedOut: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('points-balance')))
            .data,
        '0 points',
      );
      expect(find.text('No transactions yet.'), findsWidgets);
    });
  });
}
