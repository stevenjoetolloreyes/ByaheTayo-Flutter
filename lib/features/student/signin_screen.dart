// 7-Day Attendance Sign-in — daily check-in with streaks and
// reward points.
//
// This is NOT the Attendance Sheet (class attendance records). A
// sign-in is a once-a-day app check-in: one record per calendar date
// (Asia/Manila), a streak of consecutive days, a 7-day cycle with a
// Day 7 completion reward, and a history log. Points are always
// re-derived from the record log — never from a stored counter —
// and duplicate check-ins are blocked both in the UI and in the
// save handler.
//
// TWO MODES: with a [walletController] that has a real backend
// (remote mode), progress is derived from the Firestore ledger and
// a claim is an atomic, idempotent transaction credited to the
// unified Account Points Wallet. Without one (unconfigured builds,
// bare widget tests), the screen keeps its legacy local-only
// behavior: device dates, local records, local points.
import 'dart:async';
import '../top_popup.dart';

import 'package:flutter/material.dart';

import '../ad_service.dart';
import '../app_layout.dart';
import '../points_wallet_repository.dart';
import 'signin_components.dart';
import 'student_data.dart';
import 'student_theme.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen(
      {super.key,
      this.userId,
      this.walletController,
      this.onViewWallet,
      this.adService});

  /// The signed-in user's UID. Null in bare widget tests (legacy
  /// local-only mode).
  final String? userId;

  /// Shared wallet state. Null in bare widget tests (legacy
  /// local-only mode).
  final PointsWalletController? walletController;

  /// Opens the existing Account Points Wallet view (the Account
  /// tab). Null in bare widget tests; the Total Points stat is
  /// then untappable.
  final VoidCallback? onViewWallet;

  /// Shared AdMob state (null in bare widget tests, in which case
  /// no login popup is attempted). When present, the login popup
  /// interstitial is shown once per app session after a successful
  /// sign-in award (see _maybeShowLoginPopupAd): it never blocks
  /// auth or access, grants no credits, and stays silent when
  /// there is no inventory.
  final AdService? adService;

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  List<CheckinRecord> _records = [];
  bool _claiming = false;

  /// History list toggle: first 5 rows, or the full record log.
  bool _showAll = false;

  /// Remote mode: a controller with a real backend is wired.
  bool get _remote => widget.walletController?.remote ?? false;

  /// "Today" for all streak math: the Manila date in remote mode,
  /// the device date in legacy local mode.
  DateTime get _today =>
      _remote ? widget.walletController!.manilaToday : DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.walletController?.addListener(_onWalletChanged);
    _load();
  }

  @override
  void dispose() {
    widget.walletController?.removeListener(_onWalletChanged);
    super.dispose();
  }

  void _onWalletChanged() {
    if (!mounted || !_remote) return;
    setState(() {
      _records = widget.walletController!.derivedRecords;
    });
  }

  Future<void> _load() async {
    final controller = widget.walletController;
    final uid = widget.userId;
    if (_remote && controller != null && uid != null) {
      await controller.loadForUser(uid);
      if (!mounted) return;
      setState(() {
        _records = controller.derivedRecords;
      });
      return;
    }
    final records =
        await StudentStorage.loadList(StudentStorage.checkinsKey);
    if (!mounted) return;
    setState(() {
      _records = records.map(CheckinRecord.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _save() => StudentStorage.saveList(
      StudentStorage.checkinsKey,
      _records.map((r) => r.toJson()).toList());

  Future<void> _checkIn() async {
    if (_remote) {
      await _checkInRemote();
      return;
    }
    final today = DateTime.now();
    // Duplicate guard, re-checked at save time.
    if (hasCheckedInToday(_records, today)) return;
    final streak = checkinStreak(_records, today);
    final dayIndex = nextCycleDay(streak);
    final points = pointsForDay(dayIndex);
    setState(() {
      _records.insert(
        0,
        CheckinRecord(
          id: newId(),
          date: today,
          dayIndex: dayIndex,
          points: points,
        ),
      );
    });
    await _save();
    if (!mounted) return;
    TopPopup.show(context, message: dayIndex == 7 ? 'Day 7 complete! +$points points.' : 'Checked in! Day $dayIndex · +$points points.');
    _maybeShowLoginPopupAd();
  }

  /// Login popup ad: fire-and-forget, once per app session (the
  /// service enforces it). Called only after a successful award, so
  /// the popup never precedes the +10, never blocks anything, and
  /// never depends on the award: the award is already final when
  /// this runs, and a missing ad changes nothing.
  void _maybeShowLoginPopupAd() {
    final adService = widget.adService;
    if (adService == null) return;
    unawaited(adService.showLoginPopupAd());
  }

  /// Remote claim: one atomic, idempotent ledger transaction. A
  /// failed claim writes nothing locally (see the repository file
  /// header for why) — the user sees an honest error and retries.
  Future<void> _checkInRemote() async {
    if (_claiming) return;
    final controller = widget.walletController;
    if (controller == null) return;
    setState(() => _claiming = true);
    final outcome = await controller.claimToday();
    if (!mounted) return;
    setState(() => _claiming = false);
    switch (outcome.status) {
      case ClaimStatus.credited:
        TopPopup.show(context, message: outcome.dayIndex == 7 ? 'Day 7 complete! +${outcome.points} points.' : 'Checked in! Day ${outcome.dayIndex} ' '· +${outcome.points} points.');
        // Eligible login: signed in and today's award is final.
        _maybeShowLoginPopupAd();
      case ClaimStatus.alreadyClaimed:
        TopPopup.show(context, message: 'Already checked in today.');
        // Today's award already exists: same eligible login.
        _maybeShowLoginPopupAd();
      case ClaimStatus.failed:
        TopPopup.show(context, message: 'Could not sync your check-in. Check your ' 'connection and try again.');
      case ClaimStatus.unavailable:
        break;
    }
  }

  /// Widget-drawn hero illustration: a calendar card with
  /// checkmarks plus gold reward coins. This is an honest
  /// widget-drawn illustration, not a pixel copy of the mockup
  /// artwork (which would need image assets).
  Widget _heroIllustration() {
    const checkedCells = {(0, 0), (0, 1), (1, 0)};
    return SizedBox(
      width: 108,
      height: 92,
      child: Stack(
        children: [
          const Positioned(
            left: 6,
            top: 0,
            child: SizedBox(
              width: 26,
              height: 26,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 4,
            child: Container(
              width: 86,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    height: 20,
                    decoration: const BoxDecoration(
                      color: kStudentEmeraldAccent,
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white54,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white54,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        children: [
                          for (var row = 0; row < 3; row++)
                            Expanded(
                              child: Row(
                                children: [
                                  for (var col = 0; col < 3; col++)
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.all(2),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: checkedCells
                                                    .contains((row, col))
                                                ? kSigninLightGreen
                                                : const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: checkedCells
                                                  .contains((row, col))
                                              ? const Icon(Icons.check,
                                                  size: 10,
                                                  color:
                                                      kStudentEmeraldAccent)
                                              : null,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: kSigninGold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star,
                      size: 20, color: Colors.white),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.star,
                        size: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full-width check-in button. Claimed or claiming states render
  /// as a locked light-green pill (never a second claim tap);
  /// available state is the green gradient pill from the preview.
  Widget _checkinButton(bool checkedToday, int todayDay) {
    if (checkedToday || _claiming) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: kSigninLightGreen,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_claiming)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: kStudentEmerald),
              )
            else
              const Icon(Icons.check_circle_rounded,
                  color: kStudentEmerald),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _claiming ? 'Checking in…' : 'Already checked in today',
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kStudentEmerald,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kStudentEmerald, kStudentEmeraldAccent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: _checkIn,
        borderRadius: BorderRadius.circular(28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Check in today · Day $todayDay',
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final streak = checkinStreak(_records, today);
    final checkedToday = hasCheckedInToday(_records, today);
    final checkedCells = currentCycleChecked(_records, today);
    final todayDay = checkedToday
        ? _records
            .firstWhere((r) => dateKey(r.date) == dateKey(today))
            .dayIndex
        : nextCycleDay(streak);
    // Remote: the live wallet balance (repaired from the ledger on
    // load). Legacy: the sum of the local record log.
    final totalPoints = _remote
        ? widget.walletController!.balance
        : totalCheckinPoints(_records);
    final remaining = 7 - checkedCells;
    final resetsLabel = remaining == 0
        ? 'Cycle complete!'
        : 'Resets in $remaining day${remaining == 1 ? '' : 's'}';
    final visibleHistory =
        _showAll ? _records : _records.take(5).toList();

    return Scaffold(
      backgroundColor: kSigninPageBg,
      appBar: AppBar(
        title: const Text('7-Day Sign-in'),
        backgroundColor: Colors.white,
        foregroundColor: kStudentEmerald,
        elevation: 0,
      ),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          // Premium hero banner.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kStudentEmerald, kStudentEmeraldAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Study Rewards',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('7-Day Sign-in',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                      const Text(
                          'Build your study habit and earn rewards!',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _heroIllustration(),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          // Statistics cards.
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: AppLayout.cardPadding,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    border: Border.all(color: kStudentBorder),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kSigninFlameTile,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                            Icons.local_fire_department_rounded,
                            color: kSigninFlame,
                            size: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Current Streak',
                                style: AppText.caption),
                            Text(
                              streak == 1 ? '1 day' : '$streak days',
                              style: AppText.titleStrong
                                  .copyWith(color: kStudentEmerald),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppLayout.cardGap),
              Expanded(
                child: InkWell(
                  onTap: widget.onViewWallet,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: AppLayout.cardPadding,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: kStudentBorder),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: kSigninLightGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.monetization_on_rounded,
                              color: kStudentEmeraldAccent, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Points',
                                  style: AppText.caption),
                              Text('$totalPoints pts',
                                  style: AppText.titleStrong.copyWith(
                                      color: kStudentEmerald)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: kStudentSubtext),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.cardGap),
          // This Cycle tracker + progress + check-in button.
          Container(
            padding: AppLayout.cardPadding,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kStudentBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kSigninLightGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calendar_month_rounded,
                          color: kStudentEmeraldAccent, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('This Cycle',
                              style: AppText.headingStrong),
                          Text(
                              'Complete 7 consecutive days to get the bonus reward!',
                              style: AppText.caption),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kSigninLightGreen,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 14, color: kStudentEmerald),
                          const SizedBox(width: 4),
                          Text(resetsLabel,
                              style: AppText.smallBold
                                  .copyWith(color: kStudentEmerald)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                SigninDayTiles(
                  checkedCells: checkedCells,
                  currentDay: todayDay,
                  checkedToday: checkedToday,
                  showPoints: true,
                ),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  children: [
                    Expanded(
                      child: AnimatedSigninProgressBar(
                          value: checkedCells / 7),
                    ),
                    const SizedBox(width: 8),
                    Text('$checkedCells / 7 Days',
                        style: AppText.smallBold
                            .copyWith(color: kStudentEmerald)),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                _checkinButton(checkedToday, todayDay),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          // Daily Rewards card.
          Container(
            padding: AppLayout.cardPadding,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kStudentBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kSigninPaleGold,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.emoji_events_rounded,
                          color: kSigninGold, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Daily Rewards',
                              style: AppText.headingStrong),
                          Text('Earn points for checking in daily!',
                              style: AppText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: kStudentEmeraldAccent, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                                text: 'Day 1 – 6: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                            TextSpan(text: '10 points each'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                const Row(
                  children: [
                    Icon(Icons.star_rounded,
                        color: kSigninGold, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                                text: 'Day 7: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                            TextSpan(
                                text:
                                    '50 points (completion reward)'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          // Check-in History — real ledger/local records only.
          // Records carry Manila dates only (no time-of-day is
          // stored), so rows show the date, never an invented time.
          Container(
            key: const ValueKey('signin-history'),
            padding: AppLayout.cardPadding,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kStudentBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kSigninLightGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.history_rounded,
                          color: kStudentEmeraldAccent, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Check-in History',
                          style: AppText.headingStrong),
                    ),
                    if (_records.isNotEmpty)
                      InkWell(
                        onTap: () =>
                            setState(() => _showAll = !_showAll),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_showAll ? 'Show less' : 'View All',
                                style: AppText.smallBold.copyWith(
                                    color: kStudentEmerald)),
                            const Icon(Icons.chevron_right,
                                size: 18, color: kStudentEmerald),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                if (_records.isEmpty)
                  const Text('No check-in history yet.')
                else
                  for (var i = 0; i < visibleHistory.length; i++) ...[
                    if (i > 0) const Divider(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: kStudentEmeraldAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Day ${visibleHistory[i].dayIndex}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  formatDate(visibleHistory[i].date),
                                  style: AppText.caption),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: kSigninLightGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                              '+${visibleHistory[i].points} pts',
                              style: AppText.smallBold
                                  .copyWith(color: kStudentEmerald)),
                        ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kSigninLightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outlined,
                    color: kStudentEmerald, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _remote
                        ? 'Dates follow Asia/Manila time. Points are saved to your account and show in your Account Points Wallet.'
                        : 'Dates follow this phone\'s calendar (Asia/Manila). Points are saved on this device only and are separate from the Account Points Wallet.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
