// 7-Day Attendance Sign-in — daily check-in with streaks and
// reward points.
//
// Minecraft theme (Feature 2 extension): the page shell is
// blocky Minecraft — grass hero, MinecraftCard sections,
// MinecraftIconBadge headers, blocky day tiles
// ([SigninDayTiles] with `minecraft: true`, the same treatment
// the Student Hub card already uses), a MinecraftXpBar, and a
// blocky check-in button with reward tap feedback. Visual-only:
// every value, state, and tap still comes from the record log /
// wallet controller exactly as before. The day-tile STATE colors
// stay the approved ones (light-green completed, deep-emerald
// current, pale-gold Day 7, grey upcoming) — the Minecraft mode
// changes geometry + label font only, per the approved Feature 2
// decision locked by `student_minecraft_theme_test.dart`.
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
import '../local_notifications.dart';
import '../minecraft_tap_animation.dart';
import '../minecraft_theme.dart';
import '../points_wallet_repository.dart';
import '../onboarding/splash_sound.dart';
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

  Future<void> _save() async {
    await StudentStorage.saveList(
      StudentStorage.checkinsKey,
      _records.map((r) => r.toJson()).toList(),
    );
    requestLocalNotificationRefresh();
  }

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
                border: Border.all(
                  color: MinecraftColors.border,
                  width: MinecraftShapes.chipBorderWidth,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    height: 20,
                    decoration: const BoxDecoration(
                      color: MinecraftColors.grassGreen,
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(9)),
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
                                                ? MinecraftColors.grassGreen
                                                : const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: checkedCells
                                                  .contains((row, col))
                                              ? const Icon(Icons.check,
                                                  size: 10,
                                                  color: Colors.white)
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
                  decoration: BoxDecoration(
                    color: MinecraftColors.gold,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: MinecraftColors.border,
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.star,
                      size: 20, color: MinecraftColors.ink),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: MinecraftColors.goldDark,
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
  /// as a locked light-green block (never a second claim tap);
  /// available state is the grass block button from the Minecraft
  /// theme, with reward tap feedback (gold ring + music note +
  /// level-up sound) on the claim tap.
  Widget _checkinButton(bool checkedToday, int todayDay) {
    if (checkedToday || _claiming) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: kSigninLightGreen,
          borderRadius:
              BorderRadius.circular(MinecraftShapes.buttonRadius),
          border: MinecraftShapes.buttonBorder,
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
                style: MinecraftText.button(
                  color: kStudentEmerald,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return MinecraftTapAnimation(
      reward: true,
      sound: MinecraftSoundKind.levelup,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MinecraftColors.grassGreen,
          borderRadius:
              BorderRadius.circular(MinecraftShapes.buttonRadius),
          border: MinecraftShapes.buttonBorder,
          boxShadow: const [MinecraftShapes.hardShadow],
        ),
        child: InkWell(
          onTap: _checkIn,
          borderRadius:
              BorderRadius.circular(MinecraftShapes.buttonRadius),
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
                  style: MinecraftText.button(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
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
      backgroundColor: MinecraftColors.paper,
      appBar: AppBar(
        title: Text(
          '7-Day Sign-in',
          style: MinecraftText.heading(color: Colors.white, fontSize: 20),
        ),
        backgroundColor: MinecraftColors.grassGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          // Grass hero banner.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  MinecraftColors.grassBright,
                  MinecraftColors.grassMid,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.circular(MinecraftShapes.cardRadius),
              border: MinecraftShapes.blockBorder,
              boxShadow: const [MinecraftShapes.cardShadow],
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
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Study Rewards',
                              style: MinecraftText.pixel(
                                color: Colors.white,
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('7-Day Sign-in',
                          style: MinecraftText.heading(
                              color: Colors.white, fontSize: 26)),
                      Text(
                        'Build your study habit and earn rewards!',
                        style: MinecraftText.body(color: Colors.white70),
                      ),
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
                child: MinecraftCard(
                  padding: AppLayout.cardPadding,
                  child: Row(
                    children: [
                      const MinecraftIconBadge(
                        icon: Icons.local_fire_department_rounded,
                        backgroundColor: kSigninFlameTile,
                        iconColor: kSigninFlame,
                        size: 40,
                        iconSize: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Streak',
                              style: MinecraftText.caption(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              streak == 1 ? '1 day' : '$streak days',
                              style: MinecraftText.title(
                                color: kStudentEmerald,
                              ),
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
                child: MinecraftTapAnimation(
                  enabled: widget.onViewWallet != null,
                  sound: MinecraftSoundKind.pop,
                  child: MinecraftCard(
                    onTap: widget.onViewWallet,
                    padding: AppLayout.cardPadding,
                    child: Row(
                      children: [
                        const MinecraftIconBadge(
                          icon: Icons.monetization_on_rounded,
                          backgroundColor: kSigninLightGreen,
                          iconColor: kStudentEmeraldAccent,
                          size: 40,
                          iconSize: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Points',
                                style: MinecraftText.caption(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                '$totalPoints pts',
                                style: MinecraftText.title(
                                  color: kStudentEmerald,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: kStudentSubtext,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.cardGap),
          // This Cycle tracker + progress + check-in button.
          MinecraftCard(
            padding: AppLayout.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MinecraftIconBadge(
                      icon: Icons.calendar_month_rounded,
                      size: 40,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This Cycle',
                            style: MinecraftText.heading(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Complete 7 consecutive days to get the bonus reward!',
                            style: MinecraftText.caption(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kSigninLightGreen,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: MinecraftColors.border,
                          width: MinecraftShapes.chipBorderWidth,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 14, color: kStudentEmerald),
                          const SizedBox(width: 4),
                          Text(
                            resetsLabel,
                            style: MinecraftText.button(
                              color: kStudentEmerald,
                              fontSize: 12,
                            ),
                          ),
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
                  minecraft: true,
                ),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  children: [
                    Expanded(
                      child: MinecraftXpBar(value: checkedCells / 7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$checkedCells / 7 Days',
                      style: MinecraftText.button(
                        color: kStudentEmerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                _checkinButton(checkedToday, todayDay),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          // Daily Rewards card.
          MinecraftCard(
            padding: AppLayout.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MinecraftIconBadge(
                      icon: Icons.emoji_events_rounded,
                      backgroundColor: MinecraftColors.gold,
                      iconColor: MinecraftColors.ink,
                      size: 40,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Rewards',
                            style: MinecraftText.heading(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Earn points for checking in daily!',
                            style: MinecraftText.caption(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: kStudentEmeraldAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Day 1 – 6: ',
                              style: MinecraftText.bodySemiBold(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: '10 points each',
                              style: MinecraftText.body(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: kSigninGold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Day 7: ',
                              style: MinecraftText.bodySemiBold(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: '50 points (completion reward)',
                              style: MinecraftText.body(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ),
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
          MinecraftCard(
            key: const ValueKey('signin-history'),
            padding: AppLayout.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MinecraftIconBadge(
                      icon: Icons.history_rounded,
                      size: 40,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Check-in History',
                        style: MinecraftText.heading(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (_records.isNotEmpty)
                      MinecraftTapAnimation(
                        sound: MinecraftSoundKind.pop,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _showAll = !_showAll),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _showAll ? 'Show less' : 'View All',
                                style: MinecraftText.button(
                                  color: kStudentEmerald,
                                  fontSize: 12,
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: kStudentEmerald),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                if (_records.isEmpty)
                  Text(
                    'No check-in history yet.',
                    style: MinecraftText.body(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  )
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
                                style: MinecraftText.title(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                formatDate(visibleHistory[i].date),
                                style: MinecraftText.caption(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: kSigninLightGreen,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: MinecraftColors.border,
                              width: MinecraftShapes.chipBorderWidth,
                            ),
                          ),
                          child: Text(
                            '+${visibleHistory[i].points} pts',
                            style: MinecraftText.button(
                              color: kStudentEmerald,
                              fontSize: 12,
                            ),
                          ),
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
              borderRadius:
                  BorderRadius.circular(MinecraftShapes.buttonRadius),
              border: MinecraftShapes.buttonBorder,
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
                    style: MinecraftText.caption(
                      color: MinecraftColors.ink,
                      fontSize: 12,
                    ),
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
