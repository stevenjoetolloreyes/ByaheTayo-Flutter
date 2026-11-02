// Unified Account Points Wallet + 7-Day Sign-in backend — Firestore.
//
// PROBLEM THIS FIXES: the Account Points Wallet was a hardcoded 0
// with no ledger, and 7-Day Sign-in points lived only on-device
// (`byahetayo_student_checkins`). A reinstall or clear-data wiped
// the sign-in log, resetting the streak to Day 1, and the wallet
// never reflected sign-in earnings at all. From this file on, the
// wallet and the sign-in are ONE system: every sign-in credit is a
// ledger entry, and the wallet balance is derived from that ledger.
//
// DESIGN (ledger-authoritative, no separate progress store):
//   Wallet doc: collection `points_wallets`, document ID = UID.
//     Fields: `account_points_balance`, `totalEarned`, `updatedAt`.
//     The wallet doc is a CACHE: on every load the balance is
//     repaired from the ledger sum, so a drifted cache self-heals.
//   Ledger: collection `points_transactions`, document ID = the
//     idempotency reference `signin_<uid>_<manila-date>`. The same
//     claim can never credit twice: the claim runs inside a
//     `runTransaction` that checks the claim doc first, then creates
//     the ledger entry AND updates the wallet atomically.
//   Sign-in progress is DERIVED from ledger sign-in transactions
//     (mapped back to [CheckinRecord]s so the existing streak /
//     cycle / points helpers keep working unchanged). There is no
//     second progress store to drift.
//   Manila dates: every new-ledger date is a UTC+8 calendar date
//     (see [manilaDateKey]) — NEVER the device local date — so a
//     phone set to another timezone cannot claim twice or skip a
//     day. Legacy local records keep their stored device dates when
//     migrated (they were earned under the old logic).
//   Missed day: the existing [checkinStreak] rule already resets the
//     streak to 0 after a gap (next claim is Day 1) while the points
//     total (a plain sum) is preserved. Day 7 pays 50 and completes
//     a cycle; the next claim starts a new cycle (Day 1).
//   Migration: legacy local check-in records are uploaded ONCE, in
//     date order, deduped by the same reference ID — re-runs are
//     no-ops. Corrupt local records (points outside the 10/50 reward
//     table) are skipped, never uploaded.
//   Offline claim failure: a failed claim writes NOTHING locally.
//     The user sees an honest error and can retry; writing a local
//     record for a failed claim would let the local streak disagree
//     with the ledger. The next authenticated load re-migrates any
//     genuinely local (pre-cloud) records.
//   Local storage role: offline cache only, same pattern as the
//     profile fix. After every successful load/claim the
//     ledger-derived records are written back to the local check-ins
//     key so the Student tab card (which reads local storage) stays
//     in sync with the ledger.
//
// HONEST LIMIT (no Cloud Functions in this project): the strongest
// available validation is Firestore rules (owner-only, append-only
// ledger, points restricted to the 10/50 reward table, dayIndex
// 1..7, referenceId must equal the document ID) + transaction doc
// IDs + ledger-authoritative balances. A client could still claim a
// day it did not "earn" by calling the repository directly, but it
// cannot double-credit a day, inflate an amount beyond the reward
// table, or touch another user's ledger. True server-side validation
// would need Cloud Functions (a follow-up, not this task).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'student/student_data.dart';

/// Firestore collection for one wallet document per user.
const pointsWalletsCollection = 'points_wallets';

/// Firestore collection for the append-only points ledger.
const pointsTransactionsCollection = 'points_transactions';

/// Asia/Manila is UTC+8 (no daylight saving).
const manilaOffset = Duration(hours: 8);

/// The Asia/Manila calendar date-time for an instant [now]: the UTC
/// instant shifted +8h, so its calendar fields ARE the Manila date.
/// [dateKey] on the result is the Manila date key.
DateTime manilaDateTime(DateTime now) => now.toUtc().add(manilaOffset);

/// Asia/Manila calendar-date key ('YYYY-MM-DD') for an instant.
/// NEVER use the device local date for ledger dates.
String manilaDateKey(DateTime now) => dateKey(manilaDateTime(now));

/// Parses a 'YYYY-MM-DD' ledger date key back to a local-midnight
/// date. Unparseable keys map to the epoch so they sort last and
/// never match today (ledger dates written by this file are always
/// valid; this is only a defensive fallback).
DateTime parseDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return DateTime.fromMillisecondsSinceEpoch(0);
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime(year, month, day);
}

/// Idempotency reference for a sign-in claim: one document per user
/// per Manila date. Used as BOTH the ledger document ID and the
/// entry's `referenceId` field (the rules require them to match).
String signinReferenceId(String uid, String manilaDate) =>
    'signin_${uid}_$manilaDate';

/// Human-readable ledger description for a sign-in credit.
String signinDescription(int dayIndex) => '7-Day Sign-in — Day $dayIndex';

/// One ledger entry. Field names match the user spec: transaction ID
/// (the document ID, also stored as `referenceId`), user ID, type,
/// points, description, source, reference ID, date, status — plus
/// `dayIndex` (which cycle day this credit was for) and `createdAt`.
class PointsTransaction {
  const PointsTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.points,
    required this.description,
    required this.source,
    required this.referenceId,
    required this.date,
    required this.dayIndex,
    required this.status,
  });

  final String id;
  final String userId;
  // 'signin' (positive credit) or 'redemption' (negative debit
  // written by Queue #2 redeem-all into this same ledger).
  final String type;
  final int points;
  final String description;
  final String source; // 'signin' (live claim) or 'migration'.
  final String referenceId;
  final String date; // Manila 'YYYY-MM-DD'.
  final int dayIndex; // 1..7.
  final String status; // 'completed'.

  Map<String, dynamic> toDoc() {
    return {
      'userId': userId,
      'type': type,
      'points': points,
      'description': description,
      'source': source,
      'referenceId': referenceId,
      'date': date,
      'dayIndex': dayIndex,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static PointsTransaction fromDoc(String id, Map<String, dynamic>? data) {
    final d = data ?? {};
    return PointsTransaction(
      id: id,
      userId: d['userId'] as String? ?? '',
      type: d['type'] as String? ?? '',
      points: (d['points'] as num?)?.toInt() ?? 0,
      description: d['description'] as String? ?? '',
      source: d['source'] as String? ?? '',
      referenceId: d['referenceId'] as String? ?? id,
      date: d['date'] as String? ?? '',
      dayIndex: (d['dayIndex'] as num?)?.toInt() ?? 1,
      status: d['status'] as String? ?? '',
    );
  }

  /// Maps this ledger entry back to a [CheckinRecord] so the
  /// existing streak/cycle/points helpers work unchanged.
  CheckinRecord toCheckinRecord() {
    return CheckinRecord(
      id: id,
      date: parseDateKey(date),
      dayIndex: dayIndex.clamp(1, 7),
      points: points,
    );
  }
}

/// The wallet cache: what the Account tab shows. Always repaired
/// from the ledger sum on load (see [PointsWalletRepository]).
class PointsWallet {
  const PointsWallet({required this.balance, required this.totalEarned});

  /// Mirrors the `account_points_balance` wallet field: the sum of
  /// ALL ledger entries, including negative 'redemption' debits
  /// (Queue #2 redeem-all writes its debit into this same ledger).
  final int balance;

  /// Sum of positive ledger credits only. Redemption debits never
  /// reduce this: total earned is lifetime earnings, balance is
  /// what is left to spend.
  final int totalEarned;
}

/// Remote wallet + ledger storage. Tests use an in-memory fake;
/// production uses [FirestorePointsWalletRepository].
abstract class PointsWalletRepository {
  /// Loads the wallet for [uid], repairing the cached balance from
  /// the ledger sum when it drifted (or creating the wallet doc on
  /// first load). Throws on Firestore errors — callers decide how
  /// to surface them (the controller swallows load errors).
  Future<PointsWallet> fetchWallet(String uid);

  /// All ledger entries for [uid], newest first.
  Future<List<PointsTransaction>> fetchTransactions(String uid);

  /// Atomically credits a sign-in reward. Returns true when this
  /// call created the credit, false when the day was already
  /// claimed (idempotent — a duplicate never credits twice).
  /// Throws [ArgumentError] when [dayIndex]/[points] do not match
  /// the reward table, and on Firestore errors.
  Future<bool> claimSignin({
    required String uid,
    required String manilaDate,
    required int dayIndex,
    required int points,
  });

  /// Uploads legacy local check-in records for [uid] into the
  /// ledger, deduped by reference. Returns how many NEW entries
  /// were created (re-runs return 0 when everything is already
  /// uploaded). Records with points outside the reward table are
  /// skipped, never uploaded.
  Future<int> migrateSignin({
    required String uid,
    required List<CheckinRecord> records,
  });
}

/// Firestore implementation of [PointsWalletRepository].
class FirestorePointsWalletRepository implements PointsWalletRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _walletDoc(String uid) =>
      _db.collection(pointsWalletsCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _txnDoc(String referenceId) =>
      _db.collection(pointsTransactionsCollection).doc(referenceId);

  CollectionReference<Map<String, dynamic>> get _txns =>
      _db.collection(pointsTransactionsCollection);

  void _checkReward(int dayIndex, int points) {
    if (dayIndex < 1 ||
        dayIndex > 7 ||
        points != pointsForDay(dayIndex)) {
      throw ArgumentError(
          'Invalid sign-in reward: day $dayIndex = $points points');
    }
  }

  @override
  Future<PointsWallet> fetchWallet(String uid) async {
    final entries = await fetchTransactions(uid);
    var sum = 0;
    var earned = 0;
    for (final e in entries) {
      sum += e.points;
      if (e.points > 0) earned += e.points;
    }
    final snap = await _walletDoc(uid).get();
    final cached = snap.data()?['account_points_balance'];
    final cachedEarned = snap.data()?['totalEarned'];
    if (!snap.exists || cached != sum || cachedEarned != earned) {
      await _walletDoc(uid).set(
        {
          'account_points_balance': sum,
          'totalEarned': earned,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    return PointsWallet(balance: sum, totalEarned: earned);
  }

  @override
  Future<List<PointsTransaction>> fetchTransactions(String uid) async {
    // No orderBy here on purpose: where(userId) + orderBy(date)
    // would need a composite Firestore index. The ledger per user
    // is small (one entry per day), so sorting client-side keeps
    // this working with zero Console setup.
    final snap = await _txns.where('userId', isEqualTo: uid).get();
    final entries =
        snap.docs.map((d) => PointsTransaction.fromDoc(d.id, d.data()));
    final sorted = entries.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  @override
  Future<bool> claimSignin({
    required String uid,
    required String manilaDate,
    required int dayIndex,
    required int points,
  }) async {
    _checkReward(dayIndex, points);
    final ref = signinReferenceId(uid, manilaDate);
    return _db.runTransaction<bool>((tx) async {
      final txnRef = _txnDoc(ref);
      final existing = await tx.get(txnRef);
      if (existing.exists) return false;
      tx.set(
        txnRef,
        PointsTransaction(
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
        ).toDoc(),
      );
      final walletRef = _walletDoc(uid);
      final walletSnap = await tx.get(walletRef);
      final data = walletSnap.data();
      final current = (data?['account_points_balance'] as num?)?.toInt() ?? 0;
      final earned = (data?['totalEarned'] as num?)?.toInt() ?? current;
      tx.set(
        walletRef,
        {
          'account_points_balance': current + points,
          'totalEarned': earned + points,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return true;
    });
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
      // Only genuine reward-table values are ever uploaded; a
      // corrupt local record must not mint arbitrary points.
      if (record.points != 10 && record.points != 50) continue;
      final date = dateKey(record.date);
      final ref = signinReferenceId(uid, date);
      final done = await _db.runTransaction<bool>((tx) async {
        final txnRef = _txnDoc(ref);
        if ((await tx.get(txnRef)).exists) return false;
        tx.set(
          txnRef,
          PointsTransaction(
            id: ref,
            userId: uid,
            type: 'signin',
            points: record.points,
            description: signinDescription(record.dayIndex),
            source: 'migration',
            referenceId: ref,
            date: date,
            dayIndex: record.dayIndex,
            status: 'completed',
          ).toDoc(),
        );
        final walletRef = _walletDoc(uid);
        final walletSnap = await tx.get(walletRef);
        final data = walletSnap.data();
        final current =
            (data?['account_points_balance'] as num?)?.toInt() ?? 0;
        final earned = (data?['totalEarned'] as num?)?.toInt() ?? current;
        tx.set(
          walletRef,
          {
            'account_points_balance': current + record.points,
            'totalEarned': earned + record.points,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return true;
      });
      if (done) migrated++;
    }
    return migrated;
  }
}

/// Outcome of a sign-in claim attempt (see [PointsWalletController]).
enum ClaimStatus {
  /// A new ledger entry was created and the wallet credited.
  credited,

  /// Today was already claimed (this device or another) — no credit.
  alreadyClaimed,

  /// The claim could not reach the backend — nothing was credited
  /// and nothing was written locally; the user can retry.
  failed,

  /// No signed-in user or no repository (unconfigured build) —
  /// the caller should use the legacy local-only path instead.
  unavailable,
}

class ClaimOutcome {
  const ClaimOutcome(this.status, {this.dayIndex = 0, this.points = 0});

  final ClaimStatus status;
  final int dayIndex;
  final int points;
}

/// App-level wallet state shared by the Account tab, the Student
/// tab card, and the Sign-in screen, so a claim updates the Account
/// UI immediately even though the tabs stay mounted in an
/// IndexedStack. Created once in the dashboard shell; a null
/// [repository] means local-only mode (unconfigured builds and
/// widget tests): balance stays 0 and screens use their legacy
/// local paths.
///
/// Load failures never throw out of this controller: the previous
/// state is kept and screens fall back to local records, exactly
/// like the profile restore pattern.
class PointsWalletController extends ChangeNotifier {
  PointsWalletController({
    this.repository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The backend, or null in local-only mode (unconfigured builds
  /// and widget tests).
  final PointsWalletRepository? repository;

  /// Clock for "now" (injectable in tests to walk across days).
  final DateTime Function() _clock;

  /// True when a real backend is wired (signed-in + configured).
  bool get remote => repository != null;

  String? _uid;
  int _balance = 0;
  int _totalEarned = 0;
  List<PointsTransaction> _entries = [];
  bool _loading = false;
  Future<void>? _inFlight;
  String? _migratedUid;

  int get balance => _balance;
  int get totalEarned => _totalEarned;
  List<PointsTransaction> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;

  /// Asia/Manila "today" for this controller's clock.
  DateTime get manilaToday => manilaDateTime(_clock());

  /// Ledger sign-in entries mapped to check-in records, newest
  /// first — the single source of truth for streak/cycle/points
  /// math in remote mode (via the existing helpers).
  List<CheckinRecord> get derivedRecords {
    final records = _entries
        .where((e) => e.type == 'signin')
        .map((e) => e.toCheckinRecord())
        .toList()
      ..sort((a, b) => dateKey(b.date).compareTo(dateKey(a.date)));
    return records;
  }

  /// Loads (and, on first load per user, migrates) the wallet for
  /// [uid]. Concurrent calls share one in-flight load; a uid change
  /// resets the state first. Never throws.
  Future<void> loadForUser(String uid) {
    if (_uid != uid) {
      _uid = uid;
      _balance = 0;
      _totalEarned = 0;
      _entries = [];
      _migratedUid = null;
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
    // Captured once: field promotion does not survive awaits, so
    // the local keeps the non-null repo for the whole load.
    final repo = repository;
    if (repo == null) return;
    // NOTE: no notifyListeners() here on purpose. This load is
    // typically triggered from a tab's initState while the shell is
    // still building, and a synchronous notify would call setState
    // on already-built sibling tabs during the build phase (a
    // framework error). The finally-notify below runs after awaits
    // — outside the build phase — which is when screens refresh.
    _loading = true;
    try {
      if (_migratedUid != uid) {
        final local =
            await StudentStorage.loadList(StudentStorage.checkinsKey);
        final records = local.map(CheckinRecord.fromJson).toList();
        if (records.isNotEmpty) {
          await repo.migrateSignin(uid: uid, records: records);
        }
        _migratedUid = uid;
      }
      final wallet = await repo.fetchWallet(uid);
      final entries = await repo.fetchTransactions(uid);
      _balance = wallet.balance;
      _totalEarned = wallet.totalEarned;
      _entries = entries;
      // Keep the local cache in sync so the Student tab card (which
      // reads local storage) shows ledger progress.
      await StudentStorage.saveList(
        StudentStorage.checkinsKey,
        derivedRecords.map((r) => r.toJson()).toList(),
      );
    } catch (_) {
      // Offline or backend error: keep the previous state; screens
      // fall back to local records. Never blocks the UI.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Claims today's sign-in reward for the loaded user. The day,
  /// streak, and points are computed from the ledger-derived
  /// records and the Manila date; the transaction itself guarantees
  /// at most one credit per day.
  Future<ClaimOutcome> claimToday() async {
    final uid = _uid;
    final repo = repository;
    if (uid == null || repo == null) {
      return const ClaimOutcome(ClaimStatus.unavailable);
    }
    final todayKey = manilaDateKey(_clock());
    final already = _entries.where(
      (e) => e.type == 'signin' && e.date == todayKey,
    );
    if (already.isNotEmpty) {
      final entry = already.first;
      return ClaimOutcome(
        ClaimStatus.alreadyClaimed,
        dayIndex: entry.dayIndex,
        points: entry.points,
      );
    }
    final records = derivedRecords;
    final today = parseDateKey(todayKey);
    final dayIndex = nextCycleDay(checkinStreak(records, today));
    final points = pointsForDay(dayIndex);
    bool credited;
    try {
      credited = await repo.claimSignin(
        uid: uid,
        manilaDate: todayKey,
        dayIndex: dayIndex,
        points: points,
      );
    } catch (_) {
      return ClaimOutcome(
        ClaimStatus.failed,
        dayIndex: dayIndex,
        points: points,
      );
    }
    if (!credited) {
      // Lost a race (another device claimed today): refresh so the
      // UI shows the real state instead of a stale button.
      await loadForUser(uid);
      final entry = _entries.where(
        (e) => e.type == 'signin' && e.date == todayKey,
      );
      if (entry.isNotEmpty) {
        return ClaimOutcome(
          ClaimStatus.alreadyClaimed,
          dayIndex: entry.first.dayIndex,
          points: entry.first.points,
        );
      }
      return ClaimOutcome(
        ClaimStatus.alreadyClaimed,
        dayIndex: dayIndex,
        points: points,
      );
    }
    // Success: refresh from the ledger (single source of truth) so
    // the balance, history, and progress update immediately.
    await loadForUser(uid);
    return ClaimOutcome(
      ClaimStatus.credited,
      dayIndex: dayIndex,
      points: points,
    );
  }
}
