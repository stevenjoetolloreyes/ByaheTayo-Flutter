// Tests for Queue #2 (Points, Credits, AI Scanner & Ads):
// minor-unit conversion, redeem-all (atomic, idempotent,
// zero-points), free/paid scan gating, admin settings, and the
// Rewards Center UI (hub card + full screen, honest empty states,
// ads-blocked notice). The Firestore implementation is covered
// through an in-memory fake with identical semantics (same
// deterministic redemption id, same ledger-derived balances, same
// counter steps); on-device Firestore behavior is verified by the
// user on a cloud build after the rules are published.
//
// Spec test map (A–S): A = sign-in table unchanged; B = redeem
// 350 -> 3.50; C = zero points; D = duplicate redemption once;
// E = failed redemption changes nothing; F = free scans free;
// G = paid scan -1; H = failed scan no charge; I = insufficient
// blocked; J/K/L/M/N = ads — BLOCKED on missing AdMob SDK + SSV
// server (asserted via the blocked notice + no granting path,
// never via a simulated ad); O/P/Q = login popup — no popup
// exists, so the +10 path is untouched by construction; R =
// balances match history; S = existing suites + 6 tabs (run
// separately, see the Stage 2 report).
import 'package:estudyantego/features/credits_repository.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/points_wallet_repository.dart';
import 'package:estudyantego/features/rewards_center.dart';
import 'package:estudyantego/features/rewards_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [CreditsRepository] with the same semantics as the
/// Firestore implementation: deterministic daily redemption id,
/// points balance read from a simulated points-wallet cache,
/// ledger-derived credits balances, +1-only counter steps, and
/// idempotent scan charges by reference. Ad rewards are always
/// empty: this fake has NO ad-credit method, mirroring the real
/// rule that verified ad credits are server-only.
class FakeCreditsRepository implements CreditsRepository {
  /// Simulated points-wallet cache (what redeemAll reads).
  final Map<String, int> pointsBalances = {};

  /// Points debit entries written by redeemAll (auditable).
  final List<PointsTransaction> pointsDebits = [];

  final Map<String, CreditsTransaction> _creditsTxns = {};
  final Map<String, CreditRedemption> _redemptions = {};
  final Map<String, ScanCounter> _counters = {};
  AdminSettings adminSettings = AdminSettings.defaults();

  @override
  Future<CreditsWallet> fetchWallet(String uid) async {
    final entries = await fetchTransactions(uid);
    var earned = 0;
    var spent = 0;
    for (final e in entries) {
      if (e.units >= 0) {
        earned += e.units;
      } else {
        spent += -e.units;
      }
    }
    return CreditsWallet(
      balanceUnits: earned - spent,
      totalEarnedUnits: earned,
      totalSpentUnits: spent,
    );
  }

  @override
  Future<List<CreditsTransaction>> fetchTransactions(String uid) async {
    final entries =
        _creditsTxns.values.where((e) => e.userId == uid).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Future<RedeemOutcome> redeemAll({
    required String uid,
    required String manilaDate,
  }) async {
    final ref = redemptionReferenceId(uid, manilaDate);
    if (_redemptions.containsKey(ref)) {
      return const RedeemOutcome(RedeemStatus.alreadyRedeemed);
    }
    final points = pointsBalances[uid] ?? 0;
    if (points <= 0) {
      return const RedeemOutcome(RedeemStatus.zeroPoints);
    }
    final units = pointsToMinorUnits(points);
    pointsDebits.add(
      PointsTransaction(
        id: ref,
        userId: uid,
        type: 'redemption',
        points: -points,
        description: 'Redeem points — all $points points',
        source: 'redemption',
        referenceId: ref,
        date: manilaDate,
        dayIndex: 0,
        status: 'completed',
      ),
    );
    _creditsTxns[ref] = CreditsTransaction(
      id: ref,
      userId: uid,
      type: 'redemption',
      units: units,
      description:
          'Redeemed $points points → ${formatMinorUnits(units)} credits',
      source: 'redemption',
      referenceId: ref,
      date: manilaDate,
      status: 'completed',
    );
    _redemptions[ref] = CreditRedemption(
      id: ref,
      userId: uid,
      pointsRedeemed: points,
      unitsCredited: units,
      date: manilaDate,
      status: 'completed',
    );
    pointsBalances[uid] = 0;
    return RedeemOutcome(
      RedeemStatus.redeemed,
      pointsRedeemed: points,
      unitsCredited: units,
    );
  }

  @override
  Future<ScanCounter> fetchScanCounter({
    required String uid,
    required String manilaDate,
  }) async {
    return _counters[scanCounterId(uid, manilaDate)] ??
        const ScanCounter(freeUsed: 0, paidUsed: 0);
  }

  @override
  Future<FreeScanOutcome> useFreeScan({
    required String uid,
    required String manilaDate,
  }) async {
    final id = scanCounterId(uid, manilaDate);
    final current = _counters[id] ?? const ScanCounter(freeUsed: 0, paidUsed: 0);
    if (current.freeUsed >= freeScansPerDay) {
      return const FreeScanOutcome(FreeScanStatus.noneLeft);
    }
    final next = ScanCounter(
      freeUsed: current.freeUsed + 1,
      paidUsed: current.paidUsed,
    );
    _counters[id] = next;
    return FreeScanOutcome(
      FreeScanStatus.granted,
      freeRemaining: next.freeRemaining,
    );
  }

  @override
  Future<ScanChargeOutcome> chargePaidScan({
    required String uid,
    required String manilaDate,
    required String scanReferenceId,
  }) async {
    if (_creditsTxns.containsKey(scanReferenceId)) {
      return const ScanChargeOutcome(ScanChargeStatus.alreadyCharged);
    }
    final wallet = await fetchWallet(uid);
    if (wallet.balanceUnits < paidScanCostUnits) {
      return const ScanChargeOutcome(ScanChargeStatus.insufficient);
    }
    _creditsTxns[scanReferenceId] = CreditsTransaction(
      id: scanReferenceId,
      userId: uid,
      type: 'scan_charge',
      units: -paidScanCostUnits,
      description: 'AI Scanner — paid scan (1 credit)',
      source: 'scan',
      referenceId: scanReferenceId,
      date: manilaDate,
      status: 'completed',
    );
    final id = scanCounterId(uid, manilaDate);
    final current = _counters[id] ?? const ScanCounter(freeUsed: 0, paidUsed: 0);
    _counters[id] = ScanCounter(
      freeUsed: current.freeUsed,
      paidUsed: current.paidUsed + 1,
    );
    return const ScanChargeOutcome(ScanChargeStatus.charged);
  }

  @override
  Future<List<CreditsTransaction>> fetchAdRewards(String uid) async {
    // Server-written only: always empty without an SSV server.
    return const [];
  }

  @override
  Future<AdminSettings> fetchAdminSettings() async => adminSettings;
}

/// A repository that always throws, for the atomic-rollback test:
/// a failed redemption must change nothing.
class ThrowingCreditsRepository extends FakeCreditsRepository {
  @override
  Future<RedeemOutcome> redeemAll({
    required String uid,
    required String manilaDate,
  }) async {
    throw Exception('backend down');
  }
}

/// Fixed Manila clock: 2026-11-02 18:00 Manila (10:00 UTC).
DateTime fixedClock() => DateTime.utc(2026, 11, 2, 10);

void main() {
  // --- Spec A: the sign-in reward table is untouched. ---
  test('A: Daily Login stays Days 1-6 = 10, Day 7 = 50 (spec +5 overridden)',
      () {
    for (var day = 1; day <= 6; day++) {
      expect(pointsForDay(day), 10);
    }
    expect(pointsForDay(7), 50);
  });

  // --- Conversion: integer minor units only, no floats. ---
  test('conversion: 100 points = 1.00 credit, exact integers', () {
    expect(pointsToMinorUnits(10), 10);
    expect(pointsToMinorUnits(50), 50);
    expect(pointsToMinorUnits(100), 100);
    expect(pointsToMinorUnits(350), 350);
    expect(pointsToMinorUnits(1000), 1000);
    expect(minorUnitsPerCredit, 100);
  });

  test('formatMinorUnits renders display strings only', () {
    expect(formatMinorUnits(0), '0.00');
    expect(formatMinorUnits(10), '0.10');
    expect(formatMinorUnits(50), '0.50');
    expect(formatMinorUnits(100), '1.00');
    expect(formatMinorUnits(350), '3.50');
    expect(formatMinorUnits(1000), '10.00');
    expect(formatMinorUnits(-100), '-1.00');
  });

  test('redemption id is one deterministic id per user per day', () {
    expect(
      redemptionReferenceId('u1', '2026-11-02'),
      'redeem_u1_2026-11-02',
    );
    expect(
      redemptionReferenceId('u1', '2026-11-03'),
      isNot(redemptionReferenceId('u1', '2026-11-02')),
    );
  });

  test('scan counter remaining counts 3 down to 0', () {
    expect(const ScanCounter(freeUsed: 0, paidUsed: 0).freeRemaining, 3);
    expect(const ScanCounter(freeUsed: 2, paidUsed: 0).freeRemaining, 1);
    expect(const ScanCounter(freeUsed: 3, paidUsed: 0).freeRemaining, 0);
    expect(freeScansPerDay, 3);
    expect(paidScanCostUnits, 100);
    expect(rewardedAdCreditUnits, 50);
  });

  test('remainingAdsToday clamps at the admin daily limit', () {
    expect(remainingAdsToday(0, 5), 5);
    expect(remainingAdsToday(3, 5), 2);
    expect(remainingAdsToday(5, 5), 0);
    expect(remainingAdsToday(9, 5), 0);
  });

  test('admin settings defaults are ads-off with fixed 0.50 amount', () {
    final defaults = AdminSettings.defaults();
    expect(defaults.rewardedAdsEnabled, isFalse);
    expect(defaults.popupAdsEnabled, isFalse);
    expect(defaults.rewardedAmountUnits, 50);
    expect(defaults.dailyAdLimit, 5);
  });

  // --- Spec B/C/D: redeem-all through the controller. ---
  test('B: redemption converts ALL points 350 -> 3.50 credits', () async {
    final repo = FakeCreditsRepository()..pointsBalances['u1'] = 350;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    final outcome = await controller.redeemAll();
    expect(outcome.status, RedeemStatus.redeemed);
    expect(outcome.pointsRedeemed, 350);
    expect(outcome.unitsCredited, 350);
    expect(controller.balanceUnits, 350);
    expect(formatMinorUnits(controller.balanceUnits), '3.50');
    expect(repo.pointsBalances['u1'], 0);
    expect(repo.pointsDebits.single.points, -350);
    expect(repo.pointsDebits.single.type, 'redemption');
  });

  test('C: zero points redeems nothing and writes nothing', () async {
    final repo = FakeCreditsRepository()..pointsBalances['u1'] = 0;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    final outcome = await controller.redeemAll();
    expect(outcome.status, RedeemStatus.zeroPoints);
    expect(controller.balanceUnits, 0);
    expect(controller.entries, isEmpty);
    expect(repo.pointsDebits, isEmpty);
  });

  test('D: duplicate redemption the same day credits only once', () async {
    final repo = FakeCreditsRepository()..pointsBalances['u1'] = 350;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    final first = await controller.redeemAll();
    expect(first.status, RedeemStatus.redeemed);
    repo.pointsBalances['u1'] = 100;
    final second = await controller.redeemAll();
    expect(second.status, RedeemStatus.alreadyRedeemed);
    expect(controller.balanceUnits, 350);
    expect(controller.entries.length, 1);
  });

  test('E: failed redemption changes nothing (atomic rollback)', () async {
    final repo = ThrowingCreditsRepository()..pointsBalances['u1'] = 350;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    final outcome = await controller.redeemAll();
    expect(outcome.status, RedeemStatus.failed);
    expect(controller.balanceUnits, 0);
    expect(controller.entries, isEmpty);
    expect(repo.pointsBalances['u1'], 350);
    expect(repo.pointsDebits, isEmpty);
  });

  // --- Spec F/G/H/I: scanner gating. ---
  test('F: free scans deduct nothing, 3 per day then none left', () async {
    final repo = FakeCreditsRepository();
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    for (var i = 3; i >= 1; i--) {
      final outcome = await controller.useFreeScan();
      expect(outcome.status, FreeScanStatus.granted);
      expect(outcome.freeRemaining, i - 1);
    }
    final exhausted = await controller.useFreeScan();
    expect(exhausted.status, FreeScanStatus.noneLeft);
    expect(controller.balanceUnits, 0);
    expect(controller.entries, isEmpty);
  });

  test('G: paid scan after success deducts exactly 1 credit', () async {
    final repo = FakeCreditsRepository()..pointsBalances['u1'] = 350;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    await controller.redeemAll();
    expect(controller.balanceUnits, 350);
    final charged = await controller.chargePaidScan('scan_u1_2026-11-02_1');
    expect(charged.status, ScanChargeStatus.charged);
    expect(controller.balanceUnits, 250);
    expect(controller.totalSpentUnits, 100);
    // Same reference again: no double charge.
    final duplicate =
        await controller.chargePaidScan('scan_u1_2026-11-02_1');
    expect(duplicate.status, ScanChargeStatus.alreadyCharged);
    expect(controller.balanceUnits, 250);
  });

  test('H: failed or cancelled scan never reaches the charge call', () async {
    final repo = FakeCreditsRepository()..pointsBalances['u1'] = 350;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    await controller.redeemAll();
    // The failed-scan path is an explicit no-op: nothing is charged,
    // nothing is counted.
    expect(controller.noteFailedScan(), isTrue);
    expect(controller.balanceUnits, 350);
    expect(controller.entries.length, 1);
    expect(controller.scanCounter.paidUsed, 0);
  });

  test('I: insufficient credits blocks a paid scan', () async {
    final repo = FakeCreditsRepository();
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    final outcome =
        await controller.chargePaidScan('scan_u1_2026-11-02_1');
    expect(outcome.status, ScanChargeStatus.insufficient);
    expect(controller.balanceUnits, 0);
    expect(controller.entries, isEmpty);
  });

  // --- Spec R: balances match history. ---
  test('R: wallet balances equal the ledger sums after activity', () async {
    final repo = FakeCreditsRepository()..pointsBalances['u1'] = 350;
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    await controller.redeemAll();
    await controller.chargePaidScan('scan_u1_2026-11-02_1');
    var earned = 0;
    var spent = 0;
    for (final e in controller.entries) {
      if (e.units >= 0) {
        earned += e.units;
      } else {
        spent += -e.units;
      }
    }
    expect(controller.totalEarnedUnits, earned);
    expect(controller.totalSpentUnits, spent);
    expect(controller.balanceUnits, earned - spent);
    expect(controller.balanceUnits, 250);
  });

  // --- Spec J/K/L/M: ads are structurally blocked, never faked. ---
  test('J/K/L/M: no ad-credit path exists; ad history stays empty', () async {
    final repo = FakeCreditsRepository();
    final controller =
        CreditsController(repository: repo, clock: fixedClock);
    await controller.loadForUser('u1');
    // The repository exposes no method that grants ad credits, and
    // the server-written ad history is empty without an SSV server.
    expect(await repo.fetchAdRewards('u1'), isEmpty);
    expect(controller.adRewards, isEmpty);
    expect(controller.balanceUnits, 0);
  });

  // --- Widget: hub card. ---
  testWidgets('Rewards Center card shows balances + ads-blocked notice',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RewardsCenterCard(
            pointsBalance: 350,
            creditsBalanceUnits: 0,
            scanFreeRemaining: 3,
            signedIn: true,
            onRedeem: null,
            onOpenFullCenter: () {},
          ),
        ),
      ),
    );
    expect(find.text('Rewards Center'), findsOneWidget);
    expect(find.text('350 points'), findsOneWidget);
    expect(find.text('0.00 credits'), findsOneWidget);
    expect(find.textContaining('3/3'), findsOneWidget);
    expect(find.text('Redeem all points'), findsOneWidget);
    expect(
      find.textContaining('not available yet'),
      findsWidgets,
    );
  });

  testWidgets('Redeem dialog converts all points on confirm',
      (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RewardsCenterCard(
            pointsBalance: 350,
            creditsBalanceUnits: 0,
            scanFreeRemaining: 3,
            signedIn: true,
            onRedeem: () async {
              called = true;
              return const RedeemOutcome(
                RedeemStatus.redeemed,
                pointsRedeemed: 350,
                unitsCredited: 350,
              );
            },
            onOpenFullCenter: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Redeem all points'));
    await tester.pumpAndSettle();
    expect(find.text('Redeem all points?'), findsOneWidget);
    expect(find.textContaining('3.50 credits'), findsWidgets);
    await tester.tap(find.text('Redeem all').last);
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(find.textContaining('Converted 350 points'), findsOneWidget);
  });

  testWidgets('Rewards Center card signed-out state never fakes values',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RewardsCenterCard(
            pointsBalance: 0,
            creditsBalanceUnits: 0,
            scanFreeRemaining: 3,
            signedIn: false,
            onRedeem: null,
            onOpenFullCenter: () {},
          ),
        ),
      ),
    );
    expect(find.text('Rewards Center'), findsOneWidget);
    expect(find.textContaining('Sign in to see'), findsOneWidget);
    expect(find.text('0.00 credits'), findsNothing);
  });

  // --- Widget: full Rewards Center screen. ---
  testWidgets('Full Rewards Center shows histories + honest empty states',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RewardsScreen(
          pointsBalance: 0,
          onOpenStudentHub: () {},
          creditsBalanceUnits: 250,
          creditsTotalEarnedUnits: 350,
          creditsTotalSpentUnits: 100,
          creditsEntries: const [
            CreditsTransaction(
              id: 'redeem_u1_2026-11-02',
              userId: 'u1',
              type: 'redemption',
              units: 350,
              description: 'Redeemed 350 points → 3.50 credits',
              source: 'redemption',
              referenceId: 'redeem_u1_2026-11-02',
              date: '2026-11-02',
              status: 'completed',
            ),
            CreditsTransaction(
              id: 'scan_u1_2026-11-02_1',
              userId: 'u1',
              type: 'scan_charge',
              units: -100,
              description: 'AI Scanner — paid scan (1 credit)',
              source: 'scan',
              referenceId: 'scan_u1_2026-11-02_1',
              date: '2026-11-02',
              status: 'completed',
            ),
          ],
          scanFreeRemaining: 3,
          dailyAdLimit: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.50 credits'), findsOneWidget);
    expect(find.text('Redeem all points'), findsOneWidget);
    expect(find.text('Redemption History'), findsOneWidget);
    expect(
      find.text('Redeemed 350 points → 3.50 credits'),
      findsOneWidget,
    );
    expect(find.text('AI Scanner — paid scan (1 credit)'), findsOneWidget);
    expect(find.textContaining('Source: redemption'), findsOneWidget);
    expect(find.textContaining('Source: scan'), findsOneWidget);
    expect(find.text('Rewarded Ads History'), findsOneWidget);
    expect(find.textContaining('No verified ad rewards yet'), findsOneWidget);
    expect(find.text('Learning Activities'), findsOneWidget);
    expect(find.text('Achievements'), findsOneWidget);
    expect(find.text('Referral Rewards'), findsOneWidget);
    expect(find.text('Watch Ads & Earn Credits'), findsOneWidget);
    expect(find.textContaining('Not available yet'), findsWidgets);
    expect(find.textContaining('No achievements yet'), findsOneWidget);
    expect(find.textContaining('No referral rewards yet'), findsOneWidget);
  });

  // --- Widget: Rewards Center section renders inside the Hub. ---
  // The hub is a lazily-built ListView, so the card (5th section)
  // is scrolled into view before asserting.
  testWidgets('Student Hub renders the Rewards Center section',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StudentTab())),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Rewards Center'),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rewards-center')), findsOneWidget);
    expect(find.text('Rewards Center'), findsOneWidget);
  });

  testWidgets('Student Hub signed-in card shows live controller values',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pointsRepo = FakePointsWalletRepositoryForTest();
    final pointsController = PointsWalletController(
      repository: pointsRepo,
    );
    final creditsRepo = FakeCreditsRepository()
      ..pointsBalances['u1'] = 350;
    final creditsController = CreditsController(
      repository: creditsRepo,
      clock: fixedClock,
    );
    await creditsController.loadForUser('u1');
    await creditsController.redeemAll();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentTab(
            user: const AuthUser(uid: 'u1', email: 'u1@example.com'),
            walletController: pointsController,
            creditsController: creditsController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Rewards Center'),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('Rewards Center'), findsOneWidget);
    expect(find.text('3.50 credits'), findsOneWidget);
  });
}

/// Minimal points repository for the signed-in hub test: the points
/// balance itself is not under test here, only that the hub card
/// reads the controllers it is given.
class FakePointsWalletRepositoryForTest implements PointsWalletRepository {
  @override
  Future<PointsWallet> fetchWallet(String uid) async =>
      const PointsWallet(balance: 0, totalEarned: 0);

  @override
  Future<List<PointsTransaction>> fetchTransactions(String uid) async =>
      const [];

  @override
  Future<bool> claimSignin({
    required String uid,
    required String manilaDate,
    required int dayIndex,
    required int points,
  }) async =>
      false;

  @override
  Future<int> migrateSignin({
    required String uid,
    required List<CheckinRecord> records,
  }) async =>
      0;
}
