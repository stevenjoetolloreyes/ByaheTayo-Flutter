// Credits Wallet + redemption + AI Scanner gating + ad-reward
// structures for Queue #2 (Points, Credits, AI Scanner & Ads).
//
// MONEY MODEL — integer minor units only, no floats anywhere:
//   1 credit = 100 minor units. Conversion is fixed at
//   100 points = 1.00 credit, so 1 point = 1 minor unit:
//   10 points -> 10 units = 0.10 credits, 350 points -> 350 units
//   = 3.50 credits. Display formatting (`formatMinorUnits`) is
//   string-only and is never used as a source of truth.
//
// WHAT EXISTS HERE vs WHAT DOES NOT (honest split, Stage 1 report):
//   Built here: the Credits Wallet (ledger-authoritative, same
//     pattern as the Points Wallet), one-button redeem-all, free/
//     paid AI Scanner gating primitives (counters + charge logic),
//     ad-reward / admin-settings collections + rules + history UI.
//   NOT built here, because it cannot honestly be built yet:
//     - The AI Scanner itself does not exist (no OCR, no camera
//       flow, no firebase_ai). The gating code below has no scan
//       flow to gate; a future scanner phase wires its success /
//       failure callbacks into [CreditsController] — a failed or
//       cancelled scan never reaches the charge call, so it can
//       never deduct.
//     - Rewarded ads do not exist (no google_mobile_ads SDK, no
//       AdMob IDs, no publisher account) and there is no server
//       for AdMob server-side verification (SSV). There is
//       deliberately NO client-side ad-credit API in this file: a
//       client callback claiming "ad completed" is forgeable, so
//       granting credits from one would be fake verification.
//       Rewarded crediting waits for Steven's AdMob setup + an SSV
//       server; until then the Rewards Center shows the blocked
//       notice and no ad is displayed or simulated.
//     - The daily-login popup ad is a DESIGN NOTE only (see the
//       block at the end of this file). No popup UI exists, no ad
//       is shown, and the +10 sign-in award never depends on any
//       ad: the sign-in claim path is untouched by this task.
//
// SECURITY HONESTY (binding, from the Stage 1 report): Firestore
// rules enforce the SHAPE of each write (owner-only, append-only
// history, field/type bounds, one-credit-per-ID), not the TRUTH of
// the event behind it. Rules cannot prove a redemption amount
// equals the real balance, cannot prove a scan happened, and
// cannot verify an ad completion. Nothing in this file may ever be
// described as "server-side security" — true verification needs a
// trusted backend (Cloud Functions or equivalent). The wallet docs
// are caches repaired from their ledgers on load, exactly like the
// Points Wallet; the ledgers are the auditable source.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'points_wallet_repository.dart';

/// Firestore collection for one credits-wallet cache per user.
const creditsWalletsCollection = 'credits_wallets';

/// Firestore collection for the append-only credits ledger.
const creditsTransactionsCollection = 'credits_transactions';

/// Firestore collection for one redemption record per user per day.
const creditRedemptionsCollection = 'credit_redemptions';

/// Firestore collection for per-user per-day scan counters.
const scanCountersCollection = 'scan_counters';

/// Firestore collection for ad-reward entries. Client writes are
/// DENIED by rules (see firestore.rules): only a future trusted
/// backend (Admin SDK, which bypasses rules) may create verified
/// entries. The app only ever READS this collection for history.
const adRewardsCollection = 'ad_rewards';

/// Firestore collection for admin-managed settings (one document,
/// id 'global'). Writes are admin-only via the existing isAdmin()
/// allowlist; the app only ever READS it.
const adminSettingsCollection = 'admin_settings';

/// The single admin-settings document id.
const adminSettingsDocId = 'global';

/// Minor units per whole credit. Never use doubles for money.
const minorUnitsPerCredit = 100;

/// Fixed conversion: 100 points = 1.00 credit, so 1 point =
/// 1 minor unit. Points are integers, so this is exact.
int pointsToMinorUnits(int points) => points;

/// Credits earned from one verified rewarded ad: 0.50 credits.
/// This is a fixed spec value, not admin-configurable; the daily
/// ad LIMIT is what admins configure (see [AdminSettings]).
const rewardedAdCreditUnits = 50;

/// Free AI Scanner scans per Manila day.
const freeScansPerDay = 3;

/// Cost of one paid AI Scanner scan, charged only AFTER a
/// successful scan: 1 credit.
const paidScanCostUnits = 100;

/// Display-only formatting for minor units ("3.50", "0.10").
/// Never parsed back into a balance.
String formatMinorUnits(int units) {
  final sign = units < 0 ? '-' : '';
  final abs = units.abs();
  final whole = abs ~/ minorUnitsPerCredit;
  final frac = abs % minorUnitsPerCredit;
  return '$sign$whole.${frac.toString().padLeft(2, '0')}';
}

/// Idempotency reference for a redemption: ONE deterministic ID per
/// user per Manila date (delegated decision 1). A UUID per
/// redemption would be idempotent per retry but unbounded against
/// a bypassing client; the daily cap is rules-enforceable.
String redemptionReferenceId(String uid, String manilaDate) =>
    'redeem_${uid}_$manilaDate';

/// Scan counter document id: one counter per user per Manila date.
String scanCounterId(String uid, String manilaDate) =>
    'scan_${uid}_$manilaDate';

/// One credits ledger entry. Field names mirror the points ledger
/// plus the spec's Source + ad fields (network, reward reference,
/// verification status, completion timestamp). Ad fields are null
/// for non-ad entries and are never a place for private
/// verification credentials (there are none client-side).
class CreditsTransaction {
  const CreditsTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.units,
    required this.description,
    required this.source,
    required this.referenceId,
    required this.date,
    required this.status,
    this.adNetwork,
    this.adRewardReference,
    this.adVerificationStatus,
    this.adCompletedAt,
  });

  final String id;
  final String userId;

  /// 'redemption' (points -> credits) or 'scan_charge' (paid scan).
  /// There is deliberately no 'ad_reward' client type: verified ad
  /// credits are server-written only (see the file header).
  final String type;

  /// Signed minor units: positive = credit, negative = debit.
  final int units;
  final String description;
  final String source; // 'redemption' or 'scan'.
  final String referenceId;
  final String date; // Manila 'YYYY-MM-DD'.
  final String status; // 'completed'.

  /// Ad fields (null unless this entry came from a verified ad).
  final String? adNetwork;
  final String? adRewardReference;
  final String? adVerificationStatus; // 'verified' (server-set only).
  final String? adCompletedAt;

  Map<String, dynamic> toDoc() {
    final doc = <String, dynamic>{
      'userId': userId,
      'type': type,
      'units': units,
      'description': description,
      'source': source,
      'referenceId': referenceId,
      'date': date,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (adNetwork != null) doc['adNetwork'] = adNetwork;
    if (adRewardReference != null) {
      doc['adRewardReference'] = adRewardReference;
    }
    if (adVerificationStatus != null) {
      doc['adVerificationStatus'] = adVerificationStatus;
    }
    if (adCompletedAt != null) doc['adCompletedAt'] = adCompletedAt;
    return doc;
  }

  static CreditsTransaction fromDoc(String id, Map<String, dynamic>? data) {
    final d = data ?? {};
    return CreditsTransaction(
      id: id,
      userId: d['userId'] as String? ?? '',
      type: d['type'] as String? ?? '',
      units: (d['units'] as num?)?.toInt() ?? 0,
      description: d['description'] as String? ?? '',
      source: d['source'] as String? ?? '',
      referenceId: d['referenceId'] as String? ?? id,
      date: d['date'] as String? ?? '',
      status: d['status'] as String? ?? '',
      adNetwork: d['adNetwork'] as String?,
      adRewardReference: d['adRewardReference'] as String?,
      adVerificationStatus: d['adVerificationStatus'] as String?,
      adCompletedAt: d['adCompletedAt'] as String?,
    );
  }
}

/// The credits wallet cache: repaired from the ledger sum on load.
/// Balance = earned - spent; both are derived from the ledger, so
/// a drifted cache self-heals the same way the Points Wallet does.
class CreditsWallet {
  const CreditsWallet({
    required this.balanceUnits,
    required this.totalEarnedUnits,
    required this.totalSpentUnits,
  });

  final int balanceUnits;
  final int totalEarnedUnits;
  final int totalSpentUnits;
}

/// One redemption record: the audit row for a redeem-all. The
/// document id IS the idempotency reference, so a second redemption
/// the same day is impossible by construction.
class CreditRedemption {
  const CreditRedemption({
    required this.id,
    required this.userId,
    required this.pointsRedeemed,
    required this.unitsCredited,
    required this.date,
    required this.status,
  });

  final String id;
  final String userId;
  final int pointsRedeemed;
  final int unitsCredited; // Always == pointsRedeemed (1 pt = 1 unit).
  final String date;
  final String status; // 'completed'.

  Map<String, dynamic> toDoc() {
    return {
      'userId': userId,
      'pointsRedeemed': pointsRedeemed,
      'unitsCredited': unitsCredited,
      'date': date,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static CreditRedemption fromDoc(String id, Map<String, dynamic>? data) {
    final d = data ?? {};
    return CreditRedemption(
      id: id,
      userId: d['userId'] as String? ?? '',
      pointsRedeemed: (d['pointsRedeemed'] as num?)?.toInt() ?? 0,
      unitsCredited: (d['unitsCredited'] as num?)?.toInt() ?? 0,
      date: d['date'] as String? ?? '',
      status: d['status'] as String? ?? '',
    );
  }
}

/// Per-day AI Scanner usage counters (free + paid).
class ScanCounter {
  const ScanCounter({
    required this.freeUsed,
    required this.paidUsed,
  });

  final int freeUsed;
  final int paidUsed;

  /// Free scans left today (3/3 -> 0/3 display).
  int get freeRemaining =>
      (freeScansPerDay - freeUsed).clamp(0, freeScansPerDay);
}

/// Admin-managed ad settings (single 'global' document). Read by
/// the app; written only by admins (rules-enforced). The daily ad
/// limit is admin-configurable; the 0.50 rewarded amount is fixed.
/// Enforcement of the limit against bypassing clients needs a
/// server — the app self-enforces it in normal use, honestly
/// labeled as such in the UI.
class AdminSettings {
  const AdminSettings({
    required this.dailyAdLimit,
    required this.rewardedAdsEnabled,
    required this.popupAdsEnabled,
    required this.rewardedAmountUnits,
  });

  /// Default when no settings document exists yet: ads off, a
  /// conservative daily limit, fixed 0.50 reward amount.
  factory AdminSettings.defaults() => const AdminSettings(
        dailyAdLimit: 5,
        rewardedAdsEnabled: false,
        popupAdsEnabled: false,
        rewardedAmountUnits: rewardedAdCreditUnits,
      );

  final int dailyAdLimit;
  final bool rewardedAdsEnabled;
  final bool popupAdsEnabled;
  final int rewardedAmountUnits;

  Map<String, dynamic> toDoc() {
    return {
      'dailyAdLimit': dailyAdLimit,
      'rewardedAdsEnabled': rewardedAdsEnabled,
      'popupAdsEnabled': popupAdsEnabled,
      'rewardedAmountUnits': rewardedAmountUnits,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static AdminSettings fromDoc(Map<String, dynamic>? data) {
    final d = data ?? {};
    return AdminSettings(
      dailyAdLimit: (d['dailyAdLimit'] as num?)?.toInt() ?? 5,
      rewardedAdsEnabled: d['rewardedAdsEnabled'] as bool? ?? false,
      popupAdsEnabled: d['popupAdsEnabled'] as bool? ?? false,
      rewardedAmountUnits:
          (d['rewardedAmountUnits'] as num?)?.toInt() ??
              rewardedAdCreditUnits,
    );
  }
}

/// Remaining rewarded ads today under the admin daily limit.
/// Pure helper, unit-tested. Server enforcement is still needed
/// for this to hold against bypassing clients (see file header).
int remainingAdsToday(int usedToday, int dailyLimit) =>
    (dailyLimit - usedToday).clamp(0, dailyLimit);

/// Outcome of a redeem-all attempt.
enum RedeemStatus {
  /// All points converted; balances updated atomically.
  redeemed,

  /// Today already redeemed (same deterministic id) — no second
  /// conversion, no double credit.
  alreadyRedeemed,

  /// Zero redeemable points — nothing written, UI shows the
  /// zero-points message.
  zeroPoints,

  /// Backend error — the transaction wrote nothing (atomic
  /// rollback); the user can retry.
  failed,

  /// No signed-in user or no repository — local-only mode.
  unavailable,
}

class RedeemOutcome {
  const RedeemOutcome(
    this.status, {
    this.pointsRedeemed = 0,
    this.unitsCredited = 0,
  });

  final RedeemStatus status;
  final int pointsRedeemed;
  final int unitsCredited;
}

/// Outcome of a free-scan use attempt.
enum FreeScanStatus {
  /// A free scan was consumed; [freeRemaining] is post-use.
  granted,

  /// No free scans left today — the user needs a paid scan.
  noneLeft,

  /// Backend error — nothing consumed.
  failed,

  /// No repository — local-only mode.
  unavailable,
}

class FreeScanOutcome {
  const FreeScanOutcome(this.status, {this.freeRemaining = 0});

  final FreeScanStatus status;
  final int freeRemaining;
}

/// Outcome of a paid-scan charge attempt. The charge runs ONLY
/// after a successful scan (the scanner calls this on success);
/// failed or cancelled scans never call it, so they never deduct.
enum ScanChargeStatus {
  /// 1 credit deducted; the scan may proceed.
  charged,

  /// This scan reference was already charged — no double charge.
  alreadyCharged,

  /// Fewer than 1 credit available — nothing deducted.
  insufficient,

  /// Backend error — nothing deducted.
  failed,

  /// No repository — local-only mode.
  unavailable,
}

class ScanChargeOutcome {
  const ScanChargeOutcome(this.status);

  final ScanChargeStatus status;
}

/// Credits backend. Tests use an in-memory fake with identical
/// semantics; production uses [FirestoreCreditsRepository].
/// NOTE: there is intentionally NO method that credits an ad
/// reward from the client — verified ad credits are server-only
/// (see the file header). Any future server path writes
/// ad_rewards + credits_transactions via the Admin SDK.
abstract class CreditsRepository {
  /// Loads the credits wallet for [uid], repairing the cache from
  /// the ledger sum when it drifted (or creating it on first load).
  Future<CreditsWallet> fetchWallet(String uid);

  /// All credits ledger entries for [uid], newest first.
  Future<List<CreditsTransaction>> fetchTransactions(String uid);

  /// Atomically converts ALL redeemable points to credits: writes
  /// the points debit (negative 'redemption' entry in the SAME
  /// points ledger — no duplicate wallet), the credits credit, the
  /// redemption record, and both wallet caches in ONE transaction.
  /// Returns [RedeemStatus.alreadyRedeemed] when today's
  /// deterministic redemption id already exists, and
  /// [RedeemStatus.zeroPoints] when the points balance is 0 (no
  /// writes at all). Throws on Firestore errors.
  Future<RedeemOutcome> redeemAll({
    required String uid,
    required String manilaDate,
  });

  /// Today's scan counters for [uid] (zeros when no counter exists).
  Future<ScanCounter> fetchScanCounter({
    required String uid,
    required String manilaDate,
  });

  /// Consumes one free scan for today (3/day). Returns
  /// [FreeScanStatus.noneLeft] when the free scans are exhausted
  /// (no write). Counter steps are +1 only (rules-enforced).
  Future<FreeScanOutcome> useFreeScan({
    required String uid,
    required String manilaDate,
  });

  /// Charges 1 credit for a successful paid scan, idempotent on
  /// [scanReferenceId] (a duplicate call with the same reference
  /// never double-charges). Returns
  /// [ScanChargeStatus.insufficient] when the balance is below 1
  /// credit (no write). Call ONLY after a successful scan.
  Future<ScanChargeOutcome> chargePaidScan({
    required String uid,
    required String manilaDate,
    required String scanReferenceId,
  });

  /// Verified ad-reward history for [uid] (server-written entries
  /// only). Empty until the SSV server exists — never faked.
  Future<List<CreditsTransaction>> fetchAdRewards(String uid);

  /// Admin settings (defaults when no document exists yet).
  Future<AdminSettings> fetchAdminSettings();
}

/// Firestore implementation of [CreditsRepository].
class FirestoreCreditsRepository implements CreditsRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _creditsWalletDoc(String uid) =>
      _db.collection(creditsWalletsCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _pointsWalletDoc(String uid) =>
      _db.collection(pointsWalletsCollection).doc(uid);

  CollectionReference<Map<String, dynamic>> get _creditsTxns =>
      _db.collection(creditsTransactionsCollection);

  DocumentReference<Map<String, dynamic>> _creditsTxnDoc(String id) =>
      _creditsTxns.doc(id);

  DocumentReference<Map<String, dynamic>> _pointsTxnDoc(String id) =>
      _db.collection(pointsTransactionsCollection).doc(id);

  DocumentReference<Map<String, dynamic>> _redemptionDoc(String id) =>
      _db.collection(creditRedemptionsCollection).doc(id);

  DocumentReference<Map<String, dynamic>> _scanCounterDoc(String id) =>
      _db.collection(scanCountersCollection).doc(id);

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
    final snap = await _creditsWalletDoc(uid).get();
    final cached = snap.data()?['balanceUnits'];
    if (!snap.exists || cached != earned - spent) {
      await _creditsWalletDoc(uid).set(
        {
          'balanceUnits': earned - spent,
          'totalEarnedUnits': earned,
          'totalSpentUnits': spent,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    return CreditsWallet(
      balanceUnits: earned - spent,
      totalEarnedUnits: earned,
      totalSpentUnits: spent,
    );
  }

  @override
  Future<List<CreditsTransaction>> fetchTransactions(String uid) async {
    // No orderBy on purpose (same reason as the points ledger: a
    // where(userId) + orderBy(date) query would need a composite
    // index; the per-user ledger is small, so client-side sorting
    // keeps this working with zero Console setup).
    final snap = await _creditsTxns.where('userId', isEqualTo: uid).get();
    final entries =
        snap.docs.map((d) => CreditsTransaction.fromDoc(d.id, d.data()));
    final sorted = entries.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  @override
  Future<RedeemOutcome> redeemAll({
    required String uid,
    required String manilaDate,
  }) async {
    final ref = redemptionReferenceId(uid, manilaDate);
    return _db.runTransaction<RedeemOutcome>((tx) async {
      // 1. Idempotency: one redemption per day, by construction.
      final redemptionRef = _redemptionDoc(ref);
      if ((await tx.get(redemptionRef)).exists) {
        return const RedeemOutcome(RedeemStatus.alreadyRedeemed);
      }
      // 2. Redeemable amount = the points wallet cache. The cache
      // is repaired from the points ledger on every load, and the
      // debit entry written below makes the conversion auditable
      // in that same ledger; the next ledger repair converges the
      // display. HONEST LIMIT: rules cannot prove this cache value
      // equals the ledger sum inside the transaction — a bypassing
      // client could redeem a drifted cache. True amount proof
      // needs a server-side redemption (see the file header).
      final pointsWalletRef = _pointsWalletDoc(uid);
      final pointsSnap = await tx.get(pointsWalletRef);
      final pointsData = pointsSnap.data();
      final pointsBalance =
          (pointsData?['account_points_balance'] as num?)?.toInt() ?? 0;
      if (pointsBalance <= 0) {
        return const RedeemOutcome(RedeemStatus.zeroPoints);
      }
      final units = pointsToMinorUnits(pointsBalance);
      // 3. Points debit in the SAME points ledger (negative
      // 'redemption' entry — no duplicate wallet, no second ledger).
      tx.set(
        _pointsTxnDoc(ref),
        PointsTransaction(
          id: ref,
          userId: uid,
          type: 'redemption',
          points: -pointsBalance,
          description: 'Redeem points — all $pointsBalance points',
          source: 'redemption',
          referenceId: ref,
          date: manilaDate,
          dayIndex: 0,
          status: 'completed',
        ).toDoc(),
      );
      // 4. Credits credit in the credits ledger.
      tx.set(
        _creditsTxnDoc(ref),
        CreditsTransaction(
          id: ref,
          userId: uid,
          type: 'redemption',
          units: units,
          description:
              'Redeemed $pointsBalance points → ${formatMinorUnits(units)} credits',
          source: 'redemption',
          referenceId: ref,
          date: manilaDate,
          status: 'completed',
        ).toDoc(),
      );
      // 5. Redemption audit record.
      tx.set(
        redemptionRef,
        CreditRedemption(
          id: ref,
          userId: uid,
          pointsRedeemed: pointsBalance,
          unitsCredited: units,
          date: manilaDate,
          status: 'completed',
        ).toDoc(),
      );
      // 6. Both wallet caches.
      final pointsEarned =
          (pointsData?['totalEarned'] as num?)?.toInt() ?? pointsBalance;
      tx.set(
        pointsWalletRef,
        {
          'account_points_balance': 0,
          'totalEarned': pointsEarned,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final creditsWalletRef = _creditsWalletDoc(uid);
      final creditsSnap = await tx.get(creditsWalletRef);
      final creditsData = creditsSnap.data();
      final creditsBalance =
          (creditsData?['balanceUnits'] as num?)?.toInt() ?? 0;
      final creditsEarned =
          (creditsData?['totalEarnedUnits'] as num?)?.toInt() ??
              creditsBalance;
      tx.set(
        creditsWalletRef,
        {
          'balanceUnits': creditsBalance + units,
          'totalEarnedUnits': creditsEarned + units,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return RedeemOutcome(
        RedeemStatus.redeemed,
        pointsRedeemed: pointsBalance,
        unitsCredited: units,
      );
    });
  }

  @override
  Future<ScanCounter> fetchScanCounter({
    required String uid,
    required String manilaDate,
  }) async {
    final snap =
        await _scanCounterDoc(scanCounterId(uid, manilaDate)).get();
    final data = snap.data();
    if (data == null) return const ScanCounter(freeUsed: 0, paidUsed: 0);
    return ScanCounter(
      freeUsed: (data['freeUsed'] as num?)?.toInt() ?? 0,
      paidUsed: (data['paidUsed'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<FreeScanOutcome> useFreeScan({
    required String uid,
    required String manilaDate,
  }) async {
    final counterRef = _scanCounterDoc(scanCounterId(uid, manilaDate));
    return _db.runTransaction<FreeScanOutcome>((tx) async {
      final snap = await tx.get(counterRef);
      final data = snap.data();
      final freeUsed = (data?['freeUsed'] as num?)?.toInt() ?? 0;
      final paidUsed = (data?['paidUsed'] as num?)?.toInt() ?? 0;
      if (freeUsed >= freeScansPerDay) {
        return const FreeScanOutcome(FreeScanStatus.noneLeft);
      }
      tx.set(
        counterRef,
        {
          'userId': uid,
          'date': manilaDate,
          'freeUsed': freeUsed + 1,
          'paidUsed': paidUsed,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return FreeScanOutcome(
        FreeScanStatus.granted,
        freeRemaining: freeScansPerDay - (freeUsed + 1),
      );
    });
  }

  @override
  Future<ScanChargeOutcome> chargePaidScan({
    required String uid,
    required String manilaDate,
    required String scanReferenceId,
  }) async {
    return _db.runTransaction<ScanChargeOutcome>((tx) async {
      // Idempotency: the same scan reference can never charge twice
      // (protects against duplicate/concurrent success callbacks).
      final chargeRef = _creditsTxnDoc(scanReferenceId);
      if ((await tx.get(chargeRef)).exists) {
        return const ScanChargeOutcome(ScanChargeStatus.alreadyCharged);
      }
      final walletRef = _creditsWalletDoc(uid);
      final walletSnap = await tx.get(walletRef);
      final walletData = walletSnap.data();
      final balance =
          (walletData?['balanceUnits'] as num?)?.toInt() ?? 0;
      if (balance < paidScanCostUnits) {
        return const ScanChargeOutcome(ScanChargeStatus.insufficient);
      }
      tx.set(
        chargeRef,
        CreditsTransaction(
          id: scanReferenceId,
          userId: uid,
          type: 'scan_charge',
          units: -paidScanCostUnits,
          description: 'AI Scanner — paid scan (1 credit)',
          source: 'scan',
          referenceId: scanReferenceId,
          date: manilaDate,
          status: 'completed',
        ).toDoc(),
      );
      final earned =
          (walletData?['totalEarnedUnits'] as num?)?.toInt() ?? balance;
      final spent = (walletData?['totalSpentUnits'] as num?)?.toInt() ?? 0;
      tx.set(
        walletRef,
        {
          'balanceUnits': balance - paidScanCostUnits,
          'totalEarnedUnits': earned,
          'totalSpentUnits': spent + paidScanCostUnits,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      // Count the paid scan on today's counter (best effort inside
      // the same transaction — the charge itself is what matters).
      final counterRef = _scanCounterDoc(scanCounterId(uid, manilaDate));
      final counterSnap = await tx.get(counterRef);
      final counterData = counterSnap.data();
      tx.set(
        counterRef,
        {
          'userId': uid,
          'date': manilaDate,
          'freeUsed': (counterData?['freeUsed'] as num?)?.toInt() ?? 0,
          'paidUsed':
              ((counterData?['paidUsed'] as num?)?.toInt() ?? 0) + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return const ScanChargeOutcome(ScanChargeStatus.charged);
    });
  }

  @override
  Future<List<CreditsTransaction>> fetchAdRewards(String uid) async {
    final snap = await _db
        .collection(adRewardsCollection)
        .where('userId', isEqualTo: uid)
        .get();
    final entries =
        snap.docs.map((d) => CreditsTransaction.fromDoc(d.id, d.data()));
    final sorted = entries.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  @override
  Future<AdminSettings> fetchAdminSettings() async {
    final snap = await _db
        .collection(adminSettingsCollection)
        .doc(adminSettingsDocId)
        .get();
    return AdminSettings.fromDoc(snap.data());
  }
}

/// App-level credits state shared by the Student Hub Rewards Center
/// and the Account tab, mirroring [PointsWalletController]. A null
/// [repository] means local-only mode: balances stay 0 and screens
/// show honest signed-out / unavailable states, never fake values.
/// Load failures never throw out of this controller.
class CreditsController extends ChangeNotifier {
  CreditsController({
    this.repository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CreditsRepository? repository;
  final DateTime Function() _clock;

  bool get remote => repository != null;

  String? _uid;
  int _balanceUnits = 0;
  int _totalEarnedUnits = 0;
  int _totalSpentUnits = 0;
  List<CreditsTransaction> _entries = [];
  List<CreditsTransaction> _adRewards = [];
  ScanCounter _scanCounter = const ScanCounter(freeUsed: 0, paidUsed: 0);
  AdminSettings _settings = AdminSettings.defaults();
  bool _loading = false;
  Future<void>? _inFlight;

  int get balanceUnits => _balanceUnits;
  int get totalEarnedUnits => _totalEarnedUnits;
  int get totalSpentUnits => _totalSpentUnits;
  List<CreditsTransaction> get entries => List.unmodifiable(_entries);
  List<CreditsTransaction> get adRewards => List.unmodifiable(_adRewards);
  ScanCounter get scanCounter => _scanCounter;
  AdminSettings get settings => _settings;
  bool get loading => _loading;

  /// Asia/Manila "today" for this controller's clock.
  DateTime get manilaToday => manilaDateTime(_clock());

  Future<void> loadForUser(String uid) {
    if (_uid != uid) {
      _uid = uid;
      _balanceUnits = 0;
      _totalEarnedUnits = 0;
      _totalSpentUnits = 0;
      _entries = [];
      _adRewards = [];
      _scanCounter = const ScanCounter(freeUsed: 0, paidUsed: 0);
      _settings = AdminSettings.defaults();
    }
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _load(uid);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _load(String uid) async {
    final repo = repository;
    if (repo == null) return;
    _loading = true;
    try {
      final wallet = await repo.fetchWallet(uid);
      final entries = await repo.fetchTransactions(uid);
      final counter = await repo.fetchScanCounter(
        uid: uid,
        manilaDate: manilaDateKey(_clock()),
      );
      final adRewards = await repo.fetchAdRewards(uid);
      final settings = await repo.fetchAdminSettings();
      _balanceUnits = wallet.balanceUnits;
      _totalEarnedUnits = wallet.totalEarnedUnits;
      _totalSpentUnits = wallet.totalSpentUnits;
      _entries = entries;
      _scanCounter = counter;
      _adRewards = adRewards;
      _settings = settings;
    } catch (_) {
      // Offline or backend error: keep the previous state.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// One-button redeem-all. On success the caller should also
  /// refresh the points controller (the points balance drops by
  /// the redeemed amount via the ledger repair).
  Future<RedeemOutcome> redeemAll() async {
    final uid = _uid;
    final repo = repository;
    if (uid == null || repo == null) {
      return const RedeemOutcome(RedeemStatus.unavailable);
    }
    try {
      final outcome = await repo.redeemAll(
        uid: uid,
        manilaDate: manilaDateKey(_clock()),
      );
      if (outcome.status == RedeemStatus.redeemed) {
        await loadForUser(uid);
      }
      return outcome;
    } catch (_) {
      return const RedeemOutcome(RedeemStatus.failed);
    }
  }

  /// Consumes one free scan (3/day). The scanner calls this when a
  /// scan starts; when it returns noneLeft the scanner must ask
  /// for the paid path (confirmation + [chargePaidScan] on success).
  Future<FreeScanOutcome> useFreeScan() async {
    final uid = _uid;
    final repo = repository;
    if (uid == null || repo == null) {
      return const FreeScanOutcome(FreeScanStatus.unavailable);
    }
    try {
      final outcome = await repo.useFreeScan(
        uid: uid,
        manilaDate: manilaDateKey(_clock()),
      );
      if (outcome.status == FreeScanStatus.granted) {
        await loadForUser(uid);
      }
      return outcome;
    } catch (_) {
      return const FreeScanOutcome(FreeScanStatus.failed);
    }
  }

  /// Charges 1 credit AFTER a successful paid scan. Callers must
  /// never call this for a failed or cancelled scan — that is the
  /// whole guarantee behind "failed scanner = no charge".
  Future<ScanChargeOutcome> chargePaidScan(String scanReferenceId) async {
    final uid = _uid;
    final repo = repository;
    if (uid == null || repo == null) {
      return const ScanChargeOutcome(ScanChargeStatus.unavailable);
    }
    try {
      final outcome = await repo.chargePaidScan(
        uid: uid,
        manilaDate: manilaDateKey(_clock()),
        scanReferenceId: scanReferenceId,
      );
      if (outcome.status == ScanChargeStatus.charged) {
        await loadForUser(uid);
      }
      return outcome;
    } catch (_) {
      return const ScanChargeOutcome(ScanChargeStatus.failed);
    }
  }

  /// Records that a scan FAILED or was CANCELLED. Deliberately a
  /// no-op: a failed scan must never touch the wallet or the
  /// counters, and making that explicit (instead of leaving it
  /// implicit) is what future scanner code calls. Returns true so
  /// call sites can assert the no-charge path in tests.
  bool noteFailedScan() => true;
}

// ------------------------------------------------------------------
// DAILY LOGIN POPUP AD — DESIGN NOTE ONLY (no working UI).
//
// The spec's popup ad is a DIFFERENT mechanism from rewarded ads
// and is blocked on the same missing AdMob SDK, so nothing here
// displays, simulates, or grants anything. When the SDK + ad units
// exist, the implementation must satisfy ALL of these (each is a
// test in the spec: N, O, P, Q):
//   - Shown only AFTER a successful login AND after the +10 award
//     is recorded; it is a regular (interstitial-style) ad, and it
//     pays NO credits.
//   - It must never block auth or access: login completes and the
//     dashboard is usable whether the ad loads or not.
//   - The +10 award must NEVER depend on viewing, clicking, or
//     dismissing the ad (the sign-in claim transaction is
//     untouched by ad code).
//   - Closable with an accessible close button; at most one popup
//     per login session (a session flag, not a counter).
//   - Silent when there is no ad inventory: normal login flow,
//     no error, no placeholder.
//   - Never shown over payment, security, or emergency flows.
//   - Frequency caps + privacy/consent (UMP) apply before any
//     display; the admin popupAdsEnabled toggle gates it.
// Until then, the login flow contains zero ad code — which is why
// tests N–Q hold trivially today (no popup exists to misbehave).
// ------------------------------------------------------------------
