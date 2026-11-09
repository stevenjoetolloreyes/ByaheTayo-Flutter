// Student Overview Dashboard — redesigned per the Nov 1 reference
// image (premium light emerald), NOT a new app.
//
// Layout: single column of full-width landscape cards on every
// screen size (his 12:09 correction overruled the earlier 2/3-column
// grid: on tablets it looked sparse with mismatched card heights).
// Section order (Full Development Update Phase 1): Walking Goal,
// Sign-in, Bible, then the pre-existing summary widgets
// (Allowance, Classes, Notes, Attendance,
// Quotes, Commute). The Quick Buttons section was removed Nov 5
// at his request — the screens stay in the codebase.
// (The Tasks & Assignments and Upcoming cards were removed Nov 8
// at his request — the Classes screen stays reachable from the
// Classes & Timetable card.)
//
// Honest mappings for reference-only items:
// - Notification bell -> honest empty sheet (no notification
//   system exists, so there is never a fake unread dot).
// - Profile circle -> placeholder icon until an account system
//   exists; no photo is baked into the app.
// - Greeting name "Steven" matches the reference mockup; it becomes
//   dynamic when an account system exists.
import 'dart:async';
import 'top_popup.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';
import 'app_layout.dart';
import 'app_review_notifications.dart';
import 'credits_repository.dart';
import 'ios_components.dart';
import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'ph_holidays.dart';
import 'points_wallet_repository.dart';
import 'rewards_center.dart';
import 'rewards_screen.dart';
import 'student/allowance_screen.dart';
import 'student/bible_screen.dart';
import 'student/classes_screen.dart';
import 'student/custom_school_days.dart';
import 'student/edit_school_calendar_screen.dart';
import 'student/google_events.dart';
import 'student/quotes_screen.dart';
import 'student/share_card.dart';
import 'student/signin_screen.dart';
import 'student/signin_components.dart';
import 'student/student_data.dart';
import 'student/student_theme.dart';
import 'student/walking_goal_card.dart';
import 'student/walking_goal_screen.dart';
import 'student/walking_repository.dart';
import 'student/week_grid.dart';

class StudentTab extends StatefulWidget {
  const StudentTab({
    super.key,
    this.onViewOnMap,
    this.onViewAccount,
    this.user,
    this.profile,
    this.walletController,
    this.creditsController,
    this.walkingController,
    this.adService,
    this.reviewNotificationRepository,
  });

  /// Switches the shell to the Map tab (used by My Commute jumps).
  final VoidCallback? onViewOnMap;

  /// Switches the shell to the Account tab. Null in bare widget tests.
  final VoidCallback? onViewAccount;

  /// The signed-in user. Null in bare widget tests.
  final AuthUser? user;

  /// The same profile object the shell passes to the Account tab.
  /// The welcome card reads its `photoPath` on every build, so it
  /// always shows the Account Profile photo with no second copy.
  /// Null in bare widget tests (default avatar shows instead).
  final UserProfile? profile;

  /// Shared wallet state (null in bare widget tests). When it has a
  /// real backend, the sign-in card reads ledger-derived progress
  /// instead of the local cache.
  final PointsWalletController? walletController;

  /// Shared credits state (null in bare widget tests). When it has
  /// a real backend, the Rewards Center card reads live credits
  /// data; otherwise it shows the signed-out state.
  final CreditsController? creditsController;

  /// Shared walking state (null in bare widget tests, in which case
  /// the tab owns a controller backed by the platform sensor — which
  /// degrades to "not available" under test, never a crash).
  final WalkingController? walkingController;

  /// Shared AdMob state (null in bare widget tests, in which case
  /// the Rewards screen keeps its honest no-ads notice and no login
  /// popup is attempted).
  final AdService? adService;

  /// Reads the student's admin-reply notifications (null in bare
  /// widget tests and when Firebase is not configured, in which
  /// case the Notifications sheet keeps its empty state and the
  /// bell shows no badge).
  final AppReviewNotificationRepository? reviewNotificationRepository;

  @override
  State<StudentTab> createState() => _StudentTabState();
}

class _StudentTabState extends State<StudentTab> {
  bool _loading = true;
  bool _hideBalance = false;
  String _classesTab = 'today';
  List<AllowanceTxn> _txns = [];
  List<SavingsGoal> _goals = [];
  List<BudgetLimit> _budgets = [];
  List<Subject> _subjects = [];

  /// Synced Google Calendar events (mock sync — the sample set,
  /// stored locally; see google_events.dart).
  List<GoogleCalendarEvent> _googleEvents = [];

  /// Red now-line refresh: every 30s the hub rebuilds so the
  /// now-line follows the real clock. Rebuilding never moves the
  /// grids' scroll (their ScrollControllers live in the grid
  /// states, set once in initState).
  Timer? _nowTimer;

  List<CheckinRecord> _checkins = [];
  Set<String> _quoteFavs = {};
  List<String> _quoteHistory = [];
  String? _school;

  /// Custom marked days + holiday overrides for the School
  /// Calendar (loaded with the rest of the hub state; the Edit
  /// page writes them, _load re-reads them when it pops, so the
  /// calendar updates immediately after a save).
  List<CustomSchoolDay> _customDays = [];
  List<HolidayOverride> _overrides = [];

  /// The month the calendar card shows (defaults to this month)
  /// and the tapped day whose detail line shows below the grid
  /// (defaults to today). Both survive _load — flipping months
  /// or saving an edit never resets the view.
  DateTime? _calendarMonth;
  DateTime? _selectedDay;

  final _quoteKey = GlobalKey();

  late final WalkingController _walking;
  bool _walkingOwned = false;

  /// Remote mode: the wallet controller has a real backend.
  bool get _signinRemote => widget.walletController?.remote ?? false;

  /// Records the sign-in card reads: ledger-derived in remote mode
  /// (so a claim made in the Sign-in screen shows here immediately),
  /// the local cache otherwise.
  List<CheckinRecord> get _signinRecords =>
      _signinRemote ? widget.walletController!.derivedRecords : _checkins;

  /// "Today" for the sign-in card: Manila date in remote mode,
  /// device date otherwise.
  DateTime get _signinToday =>
      _signinRemote ? widget.walletController!.manilaToday : DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.walletController?.addListener(_onWalletChanged);
    widget.creditsController?.addListener(_onWalletChanged);
    _loadCredits();
    _walking = widget.walkingController ?? WalkingController();
    _walkingOwned = widget.walkingController == null;
    _walking.addListener(_onWalkingChanged);
    _walking.init();
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    widget.walletController?.removeListener(_onWalletChanged);
    widget.creditsController?.removeListener(_onWalletChanged);
    _walking.removeListener(_onWalkingChanged);
    if (_walkingOwned) _walking.dispose();
    super.dispose();
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(StudentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creditsController != widget.creditsController ||
        oldWidget.user?.uid != widget.user?.uid) {
      oldWidget.creditsController?.removeListener(_onWalletChanged);
      widget.creditsController?.addListener(_onWalletChanged);
      _loadCredits();
    }
  }

  void _loadCredits() {
    final uid = widget.user?.uid;
    final controller = widget.creditsController;
    if (uid != null && controller != null) {
      controller.loadForUser(uid);
    }
  }

  /// One-button redeem-all for the Rewards Center card: after a
  /// successful redemption the points controller reloads too, so
  /// the points balance drops by the redeemed amount immediately.
  Future<RedeemOutcome> Function()? _redeemCallback() {
    final credits = widget.creditsController;
    final points = widget.walletController;
    final uid = widget.user?.uid;
    if (credits == null || !credits.remote || uid == null) return null;
    return () async {
      final outcome = await credits.redeemAll();
      if (outcome.status == RedeemStatus.redeemed) {
        await points?.loadForUser(uid);
      }
      return outcome;
    };
  }

  /// Rewards Center hub card (Queue #2): points + credits summary,
  /// redeem-all, free-scan allowance, and the honest ads-blocked
  /// notice. The full center is a pushed route; no new tab.
  Widget _rewardsCenterWidget(BuildContext context) {
    final credits = widget.creditsController;
    final signedIn = widget.user != null && credits != null;
    return RewardsCenterCard(
      key: const ValueKey('rewards-center'),
      pointsBalance: widget.walletController?.balance ?? 0,
      creditsBalanceUnits: credits?.balanceUnits ?? 0,
      scanFreeRemaining: credits?.scanCounter.freeRemaining ?? freeScansPerDay,
      signedIn: signedIn,
      onRedeem: _redeemCallback(),
      onOpenFullCenter: () => _open(
        RewardsScreen(
          pointsBalance: widget.walletController?.balance ?? 0,
          onOpenStudentHub: () => Navigator.of(context).pop(),
          creditsBalanceUnits: credits?.balanceUnits ?? 0,
          creditsTotalEarnedUnits: credits?.totalEarnedUnits ?? 0,
          creditsTotalSpentUnits: credits?.totalSpentUnits ?? 0,
          creditsEntries: credits?.entries ?? const [],
          adRewardEntries: credits?.adRewards ?? const [],
          scanFreeRemaining:
              credits?.scanCounter.freeRemaining ?? freeScansPerDay,
          dailyAdLimit: credits?.settings.dailyAdLimit ?? 5,
          onRedeem: _redeemCallback(),
          adService: widget.adService,
        ),
        darkAware: true,
      ),
    );
  }

  void _onWalkingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final txns = await StudentStorage.loadList(StudentStorage.txnsKey);
    final goals = await StudentStorage.loadList(StudentStorage.goalsKey);
    final budgets =
        await StudentStorage.loadList(StudentStorage.budgetsKey);
    final subjects =
        await StudentStorage.loadList(StudentStorage.subjectsKey);
    final googleEvents = await loadGoogleEvents();
    final customDays = await SchoolCalendarStore.loadCustomDays();
    final overrides = await SchoolCalendarStore.loadOverrides();
    final checkins =
        await StudentStorage.loadList(StudentStorage.checkinsKey);
    final quoteFavs =
        await StudentStorage.loadStrings(StudentStorage.quoteFavsKey);
    final quoteHistory =
        await StudentStorage.loadStrings(StudentStorage.quoteHistoryKey);
    if (!mounted) return;
    setState(() {
      _txns = txns.map(AllowanceTxn.fromJson).toList();
      _goals = goals.map(SavingsGoal.fromJson).toList();
      _budgets = budgets.map(BudgetLimit.fromJson).toList();
      _subjects = subjects.map(Subject.fromJson).toList();
      _googleEvents = googleEvents;
      _customDays = customDays;
      _overrides = overrides;

      _school = prefs.getString('byahetayo_profile_school');
      _checkins = checkins.map(CheckinRecord.fromJson).toList();
      _quoteFavs = quoteFavs.toSet();
      _quoteHistory = quoteHistory;
      _loading = false;
    });
  }

  Future<void> _open(Widget screen, {bool darkAware = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => darkAware
            ? StudentHubTheme(child: screen)
            : StudentTheme(child: screen),
      ),
    );
    _load();
  }

  Future<void> _toggleQuoteFav(String id) async {
    setState(() {
      if (_quoteFavs.contains(id)) {
        _quoteFavs.remove(id);
      } else {
        _quoteFavs.add(id);
      }
    });
    await StudentStorage.saveStrings(
        StudentStorage.quoteFavsKey, _quoteFavs.toList());
  }

  /// Notifications bottom sheet (bell in the Student Hub header).
  /// Bottom sheet, not a page. It shows the student's admin-reply
  /// notifications (AppReviewNotificationsSheet) — an admin reply
  /// to one of the student's reviews appears here with an unread
  /// dot, replacing the empty state. The empty state shows only
  /// when there are no notifications. When the sheet closes, the
  /// notifications are marked read, so the bell badge clears.
  void _showNotifications() {
    final repository = widget.reviewNotificationRepository;
    final userId = widget.user?.uid;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => AppReviewNotificationsSheet(
        repository: repository,
        userId: userId,
      ),
    ).then((_) {
      if (repository != null && userId != null) {
        unawaited(repository.markAllRead(userId));
      }
    });
  }

  /// The Student Hub header with a live unread badge on the bell.
  /// When there is no notification repository or no signed-in user,
  /// the plain header (no badge) is used.
  Widget _headerWithNotifications(DateTime now) {
    final stream = _headerNotificationStream();
    if (stream == null) {
      return studentHeader(
        greetingName: greetingFor(now),
        onBell: _showNotifications,
        profile: widget.profile,
      );
    }
    return StreamBuilder<List<AppReviewNotification>>(
      stream: stream,
      builder: (context, snapshot) {
        final unread = (snapshot.data ?? const <AppReviewNotification>[])
            .where((n) => !n.read)
            .length;
        return studentHeader(
          greetingName: greetingFor(now),
          onBell: _showNotifications,
          profile: widget.profile,
          unreadNotifications: unread,
        );
      },
    );
  }

  /// The student's reply-notification stream for the header bell
  /// badge. Created once per signed-in user and reused across
  /// rebuilds — never created in build, or every rebuild would
  /// resubscribe and re-emit. (The Notifications section card
  /// that used a second stream was removed Nov 9 at Steven's
  /// request; admin replies still reach the student through the
  /// bell badge, the top popup, and the Notifications sheet.)
  Stream<List<AppReviewNotification>>? _headerNotificationsStream;
  String? _notificationsStreamUserId;

  void _ensureNotificationStreams() {
    final repository = widget.reviewNotificationRepository;
    final userId = widget.user?.uid;
    if (repository == null || userId == null) {
      _headerNotificationsStream = null;
      _notificationsStreamUserId = null;
      return;
    }
    if (_notificationsStreamUserId == userId &&
        _headerNotificationsStream != null) {
      return;
    }
    _notificationsStreamUserId = userId;
    _headerNotificationsStream = repository.watchForUser(userId);
  }

  Stream<List<AppReviewNotification>>? _headerNotificationStream() {
    _ensureNotificationStreams();
    return _headerNotificationsStream;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Single column of full-width cards on EVERY screen size (his
    // 12:09 correction: the tablet 2/3-column grid looked sparse
    // with mismatched card heights — "wag ganito").
    //
    // Preview port (Nov 6): the same sections, reorganized into 4
    // headed groups — Rewards & Goals, Study, Money,
    // Inspiration & Calendar. (The Quick Buttons section was
    // removed Nov 5 at his request; Classes/Notes/Allowance/Tasks
    // stay one tap away via their summary cards, but Attendance
    // has no Hub entry point anymore. The Commute, Subject
    // breakdown, and Notifications sections were removed Nov 9 at
    // his request.)
    final now = DateTime.now();
    final groups = <({String title, List<Widget> sections})>[
      (
        title: 'Rewards & Goals',
        sections: [
          _signinWidget(context),
          _rewardsCenterWidget(context),
          _walkingWidget(context),
        ],
      ),
      (
        title: 'Study',
        sections: [
          _classesWidget(context),
        ],
      ),
      (
        title: 'Money',
        sections: [_allowanceWidget(context)],
      ),
      (
        title: 'Inspiration & Calendar',
        sections: [
          _bibleWidget(context),
          _quotesWidget(context),
          _attendanceWidget(context),
        ],
      ),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // ChatGPT spacing: 20px horizontal screen padding,
        // 24px between sections.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        children: [
          _headerWithNotifications(now),
          const SizedBox(height: 16),
          _atAGlanceWidget(context, now),
          for (final g in groups) ...[
            const SizedBox(height: 24),
            _groupHeader(g.title),
            const SizedBox(height: 12),
            for (final s in g.sections) ...[
              s,
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Group heading for the preview-port sections (Material 3).
  Widget _groupHeader(String title) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: kStudentSectionHeading,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// At-a-glance summary under the greeting hero: today's date
  /// plus the three live counts — points, free scans, classes
  /// today. All real data; zero states stay honest.
  Widget _atAGlanceWidget(BuildContext context, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final points = widget.walletController?.balance ?? 0;
    final freeScans =
        widget.creditsController?.scanCounter.freeRemaining ??
            freeScansPerDay;
    final classesToday = classesOnDay(_subjects, now.weekday).length;

    Widget stat(String label, String value) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: AppText.bodyStrong.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppText.small.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: AppLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${weekdayName(now.weekday)}, ${monthName(now.month)} ${now.day}, ${now.year}',
              style: AppText.caption.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                stat('Points', '$points'),
                stat('Free scans', '$freeScans/$freeScansPerDay'),
                stat(
                  'Classes today',
                  '$classesToday',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ shell

  Widget _widgetCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onOpen,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final header = Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: kStudentCardHeading),
              if (subtitle != null)
                Text(subtitle,
                    style: AppText.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (trailing != null) trailing,
        if (onOpen != null) const Icon(Icons.chevron_right),
      ],
    );
    return Card(
      child: Padding(
        padding: AppLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onOpen == null)
              header
            else
              InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(14),
                child: header,
              ),
            const SizedBox(height: AppLayout.cardGap),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- walking goal

  /// Walking Goal hub card (Phase 1). Opens the details screen
  /// wrapped in the dark-aware hub theme so it renders correctly
  /// in both modes; other module screens keep the light wrapper.
  Widget _walkingWidget(BuildContext context) {
    return WalkingGoalCard(
      controller: _walking,
      onOpen: () => _open(
        WalkingGoalScreen(controller: _walking),
        darkAware: true,
      ),
    );
  }

  // ------------------------------------------------------------ sign-in

  /// 7-Day Sign-in card — approved redesign (Nov 2 previews).
  /// Premium minimalist white Material 3 card: calendar header +
  /// "Day X of 7" badge, seven day tiles, animated progress bar,
  /// and three live stats (wallet balance, streak, next reward).
  /// Every value comes from the ledger-derived records (remote)
  /// or the local record log (legacy) — nothing is hardcoded.
  /// The WHOLE card is one tap target into the dedicated sign-in
  /// page; only the Next Reward stat has its own tap (the reward
  /// schedule sheet).
  Widget _signinWidget(BuildContext context) {
    final records = _signinRecords;
    final today = _signinToday;
    final streak = checkinStreak(records, today);
    final checkedToday = hasCheckedInToday(records, today);
    final checkedCells = currentCycleChecked(records, today);
    final todayDay = checkedToday
        ? records
            .firstWhere((r) => dateKey(r.date) == dateKey(today))
            .dayIndex
        : nextCycleDay(streak);
    // Remote: the live wallet balance (repaired from the ledger on
    // load). Legacy: the sum of the local record log.
    final totalPoints = _signinRemote
        ? widget.walletController!.balance
        : totalCheckinPoints(records);
    // Dark Mode (Nov 2 polish): the card itself follows the hub
    // theme, but these inner accents are hardcoded light pastels —
    // they get dark tints here so the card reads as one dark card.
    // Light mode keeps the exact approved values below.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileGreen = isDark
        ? kStudentEmeraldAccent.withValues(alpha: 0.18)
        : kSigninLightGreen;
    final tileGold = isDark
        ? kSigninGold.withValues(alpha: 0.18)
        : kSigninPaleGold;
    final tileFlame = isDark
        ? kSigninFlame.withValues(alpha: 0.18)
        : kSigninFlameTile;
    final emphasis = isDark ? kStudentDarkAccent : kStudentEmerald;
    final divider = isDark ? kStudentDarkBorder : kStudentBorder;
    final muted = isDark ? kStudentDarkSubtext : kStudentSubtext;
    return Card(
      key: const ValueKey('signin-hub-card'),
      child: InkWell(
        onTap: () => _open(SigninScreen(
          userId: widget.user?.uid,
          walletController: widget.walletController,
          onViewWallet: widget.onViewAccount,
          adService: widget.adService,
        )),
        borderRadius: BorderRadius.circular(kStudentCardRadius),
        child: Padding(
          padding: AppLayout.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tileGreen,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.calendar_month_rounded,
                        color: kStudentEmeraldAccent, size: 26),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('7-Day Sign-in',
                            style: kStudentCardHeading),
                        Text('Build your study habit and earn rewards!',
                            style: AppText.caption),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tileGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: kStudentEmeraldAccent, size: 16),
                        const SizedBox(width: 4),
                        Text('Day $todayDay of 7',
                            style: AppText.smallBold
                                .copyWith(color: emphasis)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppLayout.cardGap),
              SigninDayTiles(
                checkedCells: checkedCells,
                currentDay: todayDay,
                checkedToday: checkedToday,
              ),
              const SizedBox(height: AppSpacing.s8),
              Row(
                children: [
                  Expanded(
                    child: AnimatedSigninProgressBar(
                        value: checkedCells / 7),
                  ),
                  const SizedBox(width: 8),
                  Text('$checkedCells / 7 Days',
                      style: AppText.smallBold
                          .copyWith(color: emphasis)),
                ],
              ),
              const SizedBox(height: AppLayout.cardGap),
              Row(
                children: [
                  Expanded(
                    child: _signinStat(
                      icon: Icons.workspace_premium_rounded,
                      iconBg: tileGold,
                      iconColor: kSigninGold,
                      label: 'Total Points',
                      value: '$totalPoints',
                      valueColor: emphasis,
                    ),
                  ),
                  Container(
                      width: 1, height: 44, color: divider),
                  Expanded(
                    child: _signinStat(
                      icon: Icons.local_fire_department_rounded,
                      iconBg: tileFlame,
                      iconColor: kSigninFlame,
                      label: 'Current Streak',
                      value: streak == 1 ? '1 day' : '$streak days',
                      valueColor: emphasis,
                    ),
                  ),
                  Container(
                      width: 1, height: 44, color: divider),
                  Expanded(
                    child: InkWell(
                      onTap: () => showSigninRewardSchedule(context),
                      borderRadius: BorderRadius.circular(14),
                      child: _signinStat(
                        icon: Icons.card_giftcard_rounded,
                        iconBg: tileGreen,
                        iconColor: kStudentEmeraldAccent,
                        label: 'Next Reward',
                        value: '${pointsForDay(7)} Points',
                        valueColor: emphasis,
                        trailing: Icon(Icons.chevron_right,
                            size: 18, color: muted),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One Hub-card stat: icon tile + label above value, as in the
  /// approved preview.
  Widget _signinStat({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.caption),
              Text(value,
                  style: AppText.smallBold
                      .copyWith(color: valueColor)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  // -------------------------------------------------------------- bible

  Widget _bibleWidget(BuildContext context) {
    final daily = verseOfDay(DateTime.now());
    return Card(
      key: const ValueKey('bible-hub-card'),
      child: InkWell(
        onTap: () => _open(const BibleScreen()),
        borderRadius: BorderRadius.circular(kStudentCardRadius),
        child: Container(
          padding: AppLayout.cardPadding,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kStudentEmerald, kStudentEmeraldAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(
                Radius.circular(kStudentCardRadius)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Bible Verse',
                      style: kStudentCardHeading.copyWith(
                          color: Colors.white)),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                '"${daily.text}"',
                style: AppText.body.copyWith(fontStyle: FontStyle.italic, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.s8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${daily.ref} (KJV)',
                    style: AppText.smallBold.copyWith(color: kStudentEmerald)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- allowance

  Widget _allowanceWidget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final balance = allowanceBalance(_txns);
    var totalIncome = 0.0;
    var totalExpense = 0.0;
    for (final t in _txns) {
      if (t.kind == 'income') {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }
    final bars = lastMonthsExpense(_txns, now, 6);
    final totalSpent =
        bars.fold<double>(0, (s, b) => s + b.amount);
    var budgetedSpent = 0.0;
    var budgetTotal = 0.0;
    for (final b in _budgets) {
      budgetTotal += b.limit;
      budgetedSpent += _txns
          .where((t) =>
              t.kind == 'expense' &&
              t.category == b.category &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold<double>(0, (s, t) => s + t.amount);
    }
    final totalSaved =
        _goals.fold<double>(0, (s, g) => s + g.saved);
    final recent = List.of(_txns)
      ..sort((a, b) => b.date.compareTo(a.date));

    Widget miniBox(String label, String value, Color color, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Expanded(child: Text(label, style: AppText.small)),
                ],
              ),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      );
    }

    // Income vs Expenses split bar: widths are the real shares;
    // both ₱0.00 means a 0% / 0% empty track.
    final splitTotal = totalIncome + totalExpense;
    final incomeShare =
        splitTotal > 0 ? totalIncome / splitTotal : 0.0;
    final expenseShare =
        splitTotal > 0 ? totalExpense / splitTotal : 0.0;

    Widget legendDot(Color color, String label, double value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('$label ${peso(value)}', style: AppText.small),
        ],
      );
    }

    // Budget Utilization donut: empty track with a "— Used"
    // center when no budgets exist; overall utilization otherwise.
    final overallUtilization =
        budgetTotal > 0 ? (budgetedSpent / budgetTotal).clamp(0, 1) : 0.0;
    final donutCenter = budgetTotal > 0
        ? '${(overallUtilization * 100).toStringAsFixed(0)}% Used'
        : '— Used';

    return _widgetCard(
      context,
      icon: Icons.account_balance_wallet_outlined,
      title: 'Allowance & Budgeting',
      subtitle: 'Track your money, spend wisely.',
      onOpen: () => _open(const AllowanceScreen()),
      children: [
        Container(
          padding: AppLayout.cardPadding,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kStudentEmerald, kStudentEmeraldAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available Balance',
                            style: TextStyle(color: Colors.white70)),
                        Text(
                          _hideBalance ? '₱••••' : peso(balance),
                          style: AppText.displaySmall
                              .copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  if (_budgets.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'No budgets set',
                        style: AppText.smallBold
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _hideBalance = !_hideBalance),
                    icon: Icon(
                        _hideBalance
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Income ${peso(totalIncome)} · Expenses ${peso(totalExpense)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppLayout.cardGap),
        const Text('Income vs Expenses',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s4),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 10,
                color: scheme.outline.withValues(alpha: 0.5),
                child: Row(
                  children: [
                    if (incomeShare > 0)
                      Container(
                        width: width * incomeShare,
                        color: scheme.secondary,
                      ),
                    if (expenseShare > 0)
                      Container(
                        width: width * expenseShare,
                        color: kStudentError,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.s4),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            legendDot(
              scheme.secondary,
              'Income',
              totalIncome,
            ),
            legendDot(
              kStudentError,
              'Expenses',
              totalExpense,
            ),
          ],
        ),
        const SizedBox(height: AppLayout.cardGap),
        Row(
          children: [
            miniBox('Income', peso(totalIncome), scheme.secondary,
                Icons.trending_up),
            const SizedBox(width: AppSpacing.s8),
            miniBox('Expenses', peso(totalExpense), kStudentError,
                Icons.trending_down),
            const SizedBox(width: AppSpacing.s8),
            miniBox(
                'Remaining',
                _budgets.isEmpty
                    ? 'No budgets'
                    : peso(budgetTotal - budgetedSpent),
                scheme.primary,
                Icons.account_balance_wallet_outlined),
          ],
        ),
        const SizedBox(height: AppLayout.cardGap),
        const Text('Monthly Spending (Last 6 Months)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
          ),
          child: MoneySpendingChart(
            bars: bars,
            totalSpent: totalSpent,
            now: now,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        const Text('Budget Utilization',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: overallUtilization.toDouble(),
                      strokeWidth: 8,
                      backgroundColor:
                          scheme.outline.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    donutCenter,
                    textAlign: TextAlign.center,
                    style: AppText.micro.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_budgets.isEmpty) ...[
                    const Text('No budget limits set yet.'),
                    Text('Budgets set: 0',
                        style: AppText.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
                    const SizedBox(height: AppSpacing.s8),
                    FilledButton(
                      onPressed: () => _open(const AllowanceScreen()),
                      child: const Text('Set limit'),
                    ),
                  ] else ...[
                    Text('Budgets set: ${_budgets.length}',
                        style: AppText.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
                    for (final b in _budgets.take(3))
                      Builder(builder: (_) {
                        final spent = _txns
                            .where((t) =>
                                t.kind == 'expense' &&
                                t.category == b.category &&
                                t.date.year == now.year &&
                                t.date.month == now.month)
                            .fold<double>(0, (s, t) => s + t.amount);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${b.category}: ${peso(spent)} of ${peso(b.limit)}'),
                              const SizedBox(height: AppSpacing.s2),
                              LinearProgressIndicator(
                                value: b.limit > 0
                                    ? (spent / b.limit).clamp(0, 1).toDouble()
                                    : 0,
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        const Text('Savings Progress',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (_goals.isEmpty) ...[
          const Text('No savings goals yet.'),
          Text(
            'Saved ${peso(0)} / Goal: not set',
            style: AppText.caption
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s2),
          LinearProgressIndicator(
            value: 0,
            backgroundColor: scheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.s8),
          FilledButton(
            onPressed: () => _open(const AllowanceScreen()),
            child: const Text('New goal'),
          ),
        ] else ...[
          Text(
            'Saved ${peso(totalSaved)} / Goal: ${peso(_goals.fold<double>(0, (s, g) => s + g.target))}',
            style: AppText.caption
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          for (final g in _goals.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${g.name}: ${peso(g.saved)} of ${peso(g.target)}'),
                  const SizedBox(height: AppSpacing.s2),
                  LinearProgressIndicator(
                    value: g.target > 0
                        ? (g.saved / g.target).clamp(0, 1).toDouble()
                        : 0,
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.s8),
        const Text('Recent Transactions',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: scheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('No transactions yet.'),
                ),
              ],
            ),
          )
        else
          for (final group in groupTxnsByDay(recent.take(3).toList())) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                dayHeaderLabel(group.day),
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final t in group.txns)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          scheme.primary.withValues(alpha: 0.12),
                      child: Icon(
                        allowanceTxnIcon(t),
                        color: scheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.note.isEmpty ? t.category : t.note,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            t.note.isEmpty
                                ? formatDate(t.date)
                                : '${t.category} · ${formatDate(t.date)}',
                            style: AppText.caption.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${t.kind == 'income' ? '+' : '−'}${peso(t.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t.kind == 'income'
                            ? scheme.primary
                            : scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
          ],
      ],
    );
  }

  // ----------------------------------------------------------- classes

  /// Classes & Timetable hub card — redesigned Nov 9, 2026 to the
  /// approved hub-card preview: Today / This Week tabs only (the
  /// All Classes tab, the "Your week at a glance" chart, Upcoming
  /// Exams, Assignment Deadlines, and the View Timetable button
  /// are gone). Today is the compact 4x5 widget-size timeline
  /// (5 hour-rows, whole 24h day inside) with the red now-line
  /// and auto-scroll to now; This Week is the full-size Mon–Sun
  /// grid (14-row viewport) with a day-grouped list under it.
  /// Google Calendar events (mock sync) sit ON both timelines
  /// with white G badges, and in both lists — timeline, grid,
  /// and lists all render the same merged entries, so they can
  /// never diverge. The header opens the full Classes &
  /// Timetable screen; the + menu for adding classes is a
  /// separate preview and is NOT built here.
  Widget _classesWidget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final next = nextClass(_subjects, now);
    // The Today list: today's classes + every synced Google
    // event, time order, Google rows carrying their day prefix.
    final todayEntries =
        todayListEntries(_subjects, _googleEvents, now.weekday);

    Widget tabBody;
    if (_classesTab == 'today') {
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClassWeekGrid(
            key: const ValueKey('today-grid'),
            subjects: _subjects,
            days: [now],
            now: now,
            googleEvents: _googleEvents,
            viewportHeight: 5 * 48,
            onGoogleEventTap: _onGoogleEventTap,
          ),
          const SizedBox(height: AppSpacing.s8),
          if (next != null) ...[
            _nextClassBanner(context, next),
            const SizedBox(height: AppSpacing.s8),
          ],
          if (todayEntries.isEmpty)
            _emptyRow(
              context,
              Icons.event_available_outlined,
              'No classes today.',
              'Relax, study, or get ahead on your tasks!',
            )
          else
            for (final entry in todayEntries) _timetableRow(entry),
        ],
      );
    } else {
      final monday = mondayOfWeek(now);
      final weekDays = [
        for (var i = 0; i < 7; i++)
          DateTime(monday.year, monday.month, monday.day + i),
      ];
      final hasAny =
          _subjects.isNotEmpty || _googleEvents.isNotEmpty;
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClassWeekGrid(
            key: const ValueKey('week-grid'),
            subjects: _subjects,
            days: weekDays,
            now: now,
            googleEvents: _googleEvents,
            viewportHeight: 14 * 48,
            onGoogleEventTap: _onGoogleEventTap,
          ),
          if (!hasAny) ...[
            const SizedBox(height: AppSpacing.s8),
            _emptyRow(
              context,
              Icons.event_available_outlined,
              'No classes this week.',
              null,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.s8),
            for (final day in weekDays)
              if (entriesForDay(_subjects, _googleEvents, day.weekday)
                  .isNotEmpty) ...[
                Text(
                  '${weekdayName(day.weekday).toUpperCase()} · ${day.day}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s4),
                for (final entry in entriesForDay(
                    _subjects, _googleEvents, day.weekday))
                  _timetableRow(entry),
                const SizedBox(height: AppSpacing.s4),
              ],
          ],
        ],
      );
    }

    // Redesign (Nov 8, 2026): the card keeps the same Card shell,
    // padding and tap-to-open behaviour as _widgetCard, but builds
    // its own header (rounded-square emerald tile instead of the
    // shared CircleAvatar) so the other cards stay untouched. The
    // segmented control and the ClassWeekGrid below are NOT
    // redesigned — they are the circled calendar region Steven
    // asked to keep ("eto wag galawin").
    return Card(
      child: Padding(
        padding: AppLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _open(const ClassesScreen()),
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.calendar_month_outlined,
                      color: scheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Classes & Timetable',
                          style: kStudentCardHeading,
                        ),
                        Text(
                          'Your schedule at a glance.',
                          style: AppText.caption.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Container(
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  const Expanded(child: Text('Total Subjects')),
                  Text(
                    '${_subjects.length}',
                    key: const ValueKey('total-subjects-count'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            IosSegmentedControl<String>(
              segments: const [
                IosSegment(value: 'today', label: 'Today'),
                IosSegment(value: 'week', label: 'This Week'),
              ],
              groupValue: _classesTab,
              onValueChanged: (value) => setState(() => _classesTab = value),
            ),
            const SizedBox(height: AppSpacing.s8),
            tabBody,
          ],
        ),
      ),
    );
  }

  /// One timetable row (hub lists): "7:30 AM–9:00 AM ·
  /// Introduction Of Computing" on the left, "UNP · Sir Supnet"
  /// on the right, with the subject's color dot. Google rows
  /// carry their day prefix in the Today list ("Thu · 3:00
  /// PM–4:30 PM · Discrete Mathematics") plus the white G badge,
  /// and open the Edit / Remove sheet on tap. The row renders the
  /// same merged entry as the timeline block above it.
  Widget _timetableRow(TimetableEntry entry) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(
              color: Color(entry.color),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(entry.label),
                ),
                if (entry.isGoogle) ...[
                  const SizedBox(width: 6),
                  const GBadge(),
                ],
              ],
            ),
          ),
          if (entry.detail.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                entry.detail,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
    if (!entry.isGoogle || entry.googleEvent == null) return row;
    final event = entry.googleEvent!;
    return InkWell(
      onTap: () => _onGoogleEventTap(event),
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }

  /// Google-event tap (block on either timeline, or its list
  /// row): the Edit / Remove sheet. Edits and removals save
  /// locally and re-render both hub views; the full screen
  /// reloads the same stored set when it opens.
  Future<void> _onGoogleEventTap(GoogleCalendarEvent event) async {
    await showGoogleEventActionSheet(
      context,
      event: event,
      onUpdated: (updated) async {
        setState(() {
          final i =
              _googleEvents.indexWhere((e) => e.id == updated.id);
          if (i >= 0) _googleEvents[i] = updated;
        });
        await saveGoogleEvents(_googleEvents);
      },
      onRemoved: (removed) async {
        setState(
            () => _googleEvents.removeWhere((e) => e.id == removed.id));
        await saveGoogleEvents(_googleEvents);
      },
    );
  }

  /// Next-class banner (Today view): emerald-tinted, schedule icon,
  /// "NEXT CLASS" micro label + subject · day time in bold. Same
  /// data as the old plain row — name, weekday, start time — plus
  /// the room · teacher line when either exists.
  Widget _nextClassBanner(
    BuildContext context,
    ({Subject subject, DateTime date}) next,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (next.subject.room.isNotEmpty) next.subject.room,
      if (next.subject.teacher.isNotEmpty) next.subject.teacher,
    ].join(' · ');
    return Container(
      key: const ValueKey('next-class-banner'),
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_outlined,
            color: scheme.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXT CLASS',
                  style: AppText.micro.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${next.subject.name} · ${weekdayName(next.date.weekday)} ${formatMinutes(next.subject.startMin)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: AppText.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state under the calendar grid: icon + bold title, with
  /// an optional second line. The strings are the card's exact
  /// honest empty states — only the styling is new.
  Widget _emptyRow(
    BuildContext context,
    IconData icon,
    String title,
    String? subtitle,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) Text(subtitle),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ quotes
  // (Preserved so the module stays reachable.)

  Widget _quotesWidget(BuildContext context) {
    final daily = quoteOfDay(DateTime.now());
    final history = _quoteHistory
        .map((id) {
          for (final q in bundledQuotes) {
            if (q.id == id) return q;
          }
          return null;
        })
        .whereType<BundledQuote>()
        .toList();

    return _widgetCard(
      context,
      icon: Icons.format_quote_outlined,
      title: 'Daily Quotes',
      subtitle: 'Quote of the Day and your history.',
      onOpen: () => _open(const QuotesScreen()),
      children: [
        RepaintBoundary(
          key: _quoteKey,
          child: shareCardContent(
            body: '"${daily.text}"',
            attribution: '— ${daily.author}',
            footer: 'EstudyanteGO · Daily Quotes',
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text('${daily.category} · Quote of the Day',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: '"${daily.text}" — ${daily.author}'));
                  TopPopup.show(context, message: 'Quote copied.');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => shareBoundaryAsImage(
                  boundaryKey: _quoteKey,
                  filename: 'byahetayo-quote.png',
                  fallbackText: '"${daily.text}" — ${daily.author}',
                ),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share image'),
              ),
            ),
            IconButton(
              icon: Icon(
                _quoteFavs.contains(daily.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: _quoteFavs.contains(daily.id) ? kStudentError : null,
              ),
              onPressed: () => _toggleQuoteFav(daily.id),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        const Text('Quote history',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (history.isEmpty)
          const Text('No quote history yet.')
        else
          for (final q in history.take(3))
            _row('— ${q.author}', '"${q.text}"'),
      ],
    );
  }

  // -------------------------------------------------------- attendance
  // (Preserved so the School Calendar stays reachable from the
  // dashboard. The Subject breakdown and Monthly report donuts
  // were removed Nov 9 at Steven's request; attendance detail
  // still lives in the Attendance screen.)

  Widget _attendanceWidget(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final month = _calendarMonth ?? DateTime(now.year, now.month);
    final selected = _selectedDay ?? today;
    final monthStart = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = monthStart.weekday; // 1 = Mon
    final schoolLabel = _school?.trim();
    final scheme = Theme.of(context).colorScheme;

    // The visible month's effective entries drive the dynamic
    // legend; the next marked days drive Coming up below the
    // card. Both come from the same effective list the Edit page
    // writes (holidays + school events + custom days, overrides
    // applied), so a save updates everything at once.
    final monthEntries = effectiveMarkedDays(
      school: _school,
      custom: _customDays,
      overrides: _overrides,
    )
        .where((e) =>
            e.date.year == month.year && e.date.month == month.month)
        .toList();
    final upcoming = comingUpMarkedDays(
      school: _school,
      custom: _customDays,
      overrides: _overrides,
      from: now,
    );
    final selectedEntry = markedDayOn(
      selected,
      school: _school,
      custom: _customDays,
      overrides: _overrides,
    );

    final card = _widgetCard(
      context,
      icon: Icons.calendar_month_outlined,
      title: 'School Calendar',
      subtitle: schoolLabel == null || schoolLabel.isEmpty
          ? 'School days and no-school days — holidays in red.'
          : '$schoolLabel · School days and no-school days',
      trailing: TextButton.icon(
        key: const ValueKey('school-calendar-edit'),
        onPressed: () => _open(
          EditSchoolCalendarScreen(
            school: _school,
            days: groupMarkedDays(effectiveMarkedDays(
              school: _school,
              custom: _customDays,
              overrides: _overrides,
            )),
          ),
          darkAware: true,
        ),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Edit'),
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${monthName(month.month)} ${month.year}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              key: const ValueKey('calendar-prev-month'),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
              onPressed: () => setState(() => _calendarMonth =
                  DateTime(month.year, month.month - 1)),
            ),
            IconButton(
              key: const ValueKey('calendar-next-month'),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
              onPressed: () => setState(() => _calendarMonth =
                  DateTime(month.year, month.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(d,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
          ),
          itemCount: (firstWeekday - 1) + daysInMonth,
          itemBuilder: (_, i) {
            if (i < firstWeekday - 1) return const SizedBox.shrink();
            final day = i - (firstWeekday - 1) + 1;
            final dayDate = DateTime(month.year, month.month, day);
            // The effective entry for this date — custom days and
            // overrides included, so a renamed/removed holiday or
            // an added school day shows here immediately.
            final entry = markedDayOn(
              dayDate,
              school: _school,
              custom: _customDays,
              overrides: _overrides,
            );
            final kind = schoolDayKind(dayDate);
            final isToday = dayDate == today;
            final isSelected = dayDate == selected;
            final Color? dayColor = switch (entry?.type) {
              MarkedDayType.holiday => scheme.error,
              MarkedDayType.noClasses => scheme.onSurfaceVariant,
              MarkedDayType.event => null,
              null => kind == SchoolDayKind.weekend
                  ? scheme.onSurfaceVariant
                  : null,
            };
            final dotColor = entry == null
                ? null
                : markedDayTypeColor(entry.type);
            return Center(
              child: InkWell(
                key: ValueKey('calendar-day-$day'),
                onTap: () => setState(() => _selectedDay = dayDate),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Google Calendar style: today is a filled
                    // emerald circle with white text; the tapped
                    // day gets an emerald ring.
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: isToday
                          ? const BoxDecoration(
                              color: kStudentEmerald,
                              shape: BoxShape.circle,
                            )
                          : isSelected
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: scheme.primary, width: 2),
                                )
                              : null,
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          color: isToday ? Colors.white : dayColor,
                          fontWeight: isToday ||
                                  entry?.type == MarkedDayType.holiday
                              ? FontWeight.w800
                              : null,
                        ),
                      ),
                    ),
                    // A fixed 6px slot keeps dotted and undotted
                    // numbers aligned. Dot colour follows the
                    // entry type (holiday red, no classes amber,
                    // event blue) — same as the legend.
                    SizedBox(
                      height: 6,
                      child: dotColor == null
                          ? null
                          : Icon(Icons.circle, size: 6, color: dotColor),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Legend (dynamic): only the types present in the visible
        // month show, plus Today. Dot colours match the edit
        // page (holiday red, no classes amber, event blue).
        // (The Add school chip was removed Nov 9 at Steven's
        // request; the school itself is set under Student
        // Information in the Account tab, and edited from the
        // Edit button above.)
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (monthEntries
                .any((e) => e.type == MarkedDayType.holiday))
              _legendItem(
                  markedDayTypeColor(MarkedDayType.holiday), 'Holiday'),
            if (monthEntries
                .any((e) => e.type == MarkedDayType.noClasses))
              _legendItem(
                  markedDayTypeColor(MarkedDayType.noClasses), 'No classes'),
            if (monthEntries.any((e) => e.type == MarkedDayType.event))
              _legendItem(
                  markedDayTypeColor(MarkedDayType.event), 'Event'),
            _legendItem(kStudentEmerald, 'Today'),
          ],
        ),
        // Day detail: the tapped day (today by default). A marked
        // day shows its name + type; a weekend says so — a plain
        // weekday is a regular school day.
        const SizedBox(height: AppSpacing.s8),
        Text(
          '${monthName(selected.month)} ${selected.day}, '
          '${selected.year}${selected == today ? ' · Today' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        if (selectedEntry != null)
          Text(
            '${selectedEntry.name} · ${selectedEntry.type.label}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else if (isWeekend(selected))
          Text(
            'Weekend — no classes.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else
          Text(
            'Regular school day — classes as usual.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        card,
        // Coming up — no-school days & events (next 5 from
        // today), below the card, exactly like the preview.
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Coming up — no-school days & events',
              style: kStudentCardHeading),
          const SizedBox(height: 8),
          for (final entry in upcoming) _comingUpRow(context, entry),
        ],
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: AppSpacing.s4),
        Text(label),
      ],
    );
  }

  Widget _comingUpRow(BuildContext context, MarkedDayEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 8, color: markedDayTypeColor(entry.type)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  formatMarkedDayRange(entry),
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: markedDayTypeColor(entry.type)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              entry.type.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: markedDayTypeColor(entry.type),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
