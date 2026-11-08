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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';
import 'app_layout.dart';
import 'credits_repository.dart';
import 'ios_components.dart';
import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'ph_holidays.dart';
import 'points_wallet_repository.dart';
import 'rewards_center.dart';
import 'rewards_screen.dart';
import 'school_events.dart';
import 'student/allowance_screen.dart';
import 'student/bible_screen.dart';
import 'student/classes_screen.dart';
import 'student/commute_screen.dart';
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
import 'fares_tab.dart' as fares;
import 'map_tab.dart' as maps;

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
  List<AssignmentItem> _assignments = [];
  List<AttendanceRecord> _attendance = [];

  List<String> _savedKeys = [];
  List<String> _commuteFavs = [];
  List<CommuteExpense> _commuteExpenses = [];
  List<CheckinRecord> _checkins = [];
  Set<String> _quoteFavs = {};
  List<String> _quoteHistory = [];
  String? _school;
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
    _load();
  }

  @override
  void dispose() {
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
    final assignments =
        await StudentStorage.loadList(StudentStorage.assignmentsKey);
    final attendance =
        await StudentStorage.loadList(StudentStorage.attendanceKey);

    final commuteFavs =
        await StudentStorage.loadStrings(StudentStorage.commuteFavsKey);
    final commuteExpenses =
        await StudentStorage.loadList(StudentStorage.commuteExpensesKey);
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
      _assignments = assignments.map(AssignmentItem.fromJson).toList();
      _attendance = attendance.map(AttendanceRecord.fromJson).toList();

      _savedKeys = prefs.getStringList('byahetayo_saved_routes') ?? [];
      _school = prefs.getString('byahetayo_profile_school');
      _commuteFavs = commuteFavs;
      _commuteExpenses =
          commuteExpenses.map(CommuteExpense.fromJson).toList();
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

  fares.Hub? _hubByName(String name) {
    for (final h in fares.hubs) {
      if (h.name == name) return h;
    }
    return null;
  }

  void _showNotifications() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const Padding(
        padding: AppLayout.pagePaddingLarge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
                style: AppText.headingStrong),
            SizedBox(height: AppSpacing.s8),
            Text('No notifications yet.'),
            SizedBox(height: AppSpacing.s4),
            Text(
              'This app does not have a notification system yet, so there is nothing to show here.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
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
    // Preview port (Nov 6): the same sections, reorganized into 5
    // headed groups — Rewards & Goals, Study, Money, Commute,
    // Inspiration & Calendar. NOTHING is removed; only the order
    // changes. (The Quick Buttons section was removed Nov 5 at
    // his request; Classes/Notes/Allowance/Tasks stay one tap away
    // via their summary cards, but Attendance has no Hub entry
    // point anymore.)
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
        title: 'Commute',
        sections: [_commuteWidget(context)],
      ),
      (
        title: 'Inspiration & Calendar',
        sections: [
          _bibleWidget(context),
          _quotesWidget(context),
          _attendanceWidget(context),
          _notificationsWidget(context),
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
          studentHeader(
            greetingName: greetingFor(now),
            onBell: _showNotifications,
            profile: widget.profile,
          ),
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
    final maxBar =
        bars.fold<double>(0, (m, b) => b.amount > m ? b.amount : m);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 96,
                child: Stack(
                  children: [
                    // Grid lines.
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                            height: 1,
                            color: scheme.outline.withValues(alpha: 0.5),
                          ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final b in bars)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  peso(b.amount),
                                  style: AppText.micro.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  height: maxBar > 0
                                      ? 56 * (b.amount / maxBar)
                                      : 2,
                                  width: 18,
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                Text(b.label, style: AppText.micro),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                '${peso(totalSpent)} Total spent',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (totalSpent == 0)
                Text(
                  'No spending recorded in the last 6 months.',
                  style: AppText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
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
          for (final t in recent.take(3))
            _row(
              '${t.category} · ${formatDate(t.date)}',
              '${t.kind == 'income' ? '+' : '−'}${peso(t.amount)}',
            ),
      ],
    );
  }

  // ----------------------------------------------------------- classes

  Widget _classesWidget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todays = classesOnDay(_subjects, now.weekday);
    final next = nextClass(_subjects, now);
    final upcomingExams = _assignments
        .where((a) => !a.done && a.kind == 'exam')
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final upcomingAssignments = _assignments
        .where((a) => !a.done && a.kind == 'assignment')
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    String subjectName(String id) {
      for (final s in _subjects) {
        if (s.id == id) return s.name;
      }
      return 'Subject';
    }

    // Google Calendar-style grids (preview port, Nov 6): Today =
    // day grid, This Week = full Monday-first week grid, All
    // Classes = subjects list. Grids render real subjects only;
    // with none, the grid is empty and the honest empty state
    // below it stays. Both grids show the red now-line and open
    // scrolled to the current hour.
    Widget tabBody;
    if (_classesTab == 'today') {
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClassWeekGrid(subjects: _subjects, days: [now], now: now),
          const SizedBox(height: AppSpacing.s8),
          if (next != null) ...[
            _nextClassBanner(context, next),
            const SizedBox(height: AppSpacing.s8),
          ],
          if (todays.isEmpty) ...[
            _emptyRow(
              context,
              Icons.event_available_outlined,
              'No classes today.',
              'Relax, study, or get ahead on your tasks!',
            ),
          ] else
            for (final s in todays)
              _dotRow(
                color: Color(s.color),
                label:
                    '${formatMinutes(s.startMin)}–${formatMinutes(s.endMin)} · ${s.name}',
                value:
                    '${s.room.isEmpty ? '' : '${s.room} '}${s.teacher}',
              ),
        ],
      );
    } else if (_classesTab == 'week') {
      final monday = mondayOfWeek(now);
      final weekDays = [
        for (var i = 0; i < 7; i++)
          DateTime(monday.year, monday.month, monday.day + i),
      ];
      final hasAny = _subjects.isNotEmpty;
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClassWeekGrid(subjects: _subjects, days: weekDays, now: now),
          if (!hasAny) ...[
            const SizedBox(height: AppSpacing.s8),
            _emptyRow(
              context,
              Icons.event_available_outlined,
              'No classes this week.',
              null,
            ),
          ],
        ],
      );
    } else {
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_subjects.isEmpty)
            _emptyRow(
              context,
              Icons.school_outlined,
              'No subjects yet.',
              null,
            )
          else
            for (final s in _subjects)
              _dotRow(
                color: Color(s.color),
                label: s.code.isEmpty ? s.name : '${s.name} (${s.code})',
                value:
                    '${s.teacher}${s.room.isEmpty ? '' : ' · ${s.room}'}',
              ),
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
                IosSegment(value: 'all', label: 'All Classes'),
              ],
              groupValue: _classesTab,
              onValueChanged: (value) => setState(() => _classesTab = value),
            ),
            const SizedBox(height: AppSpacing.s8),
            tabBody,
            const SizedBox(height: AppSpacing.s8),
            _weekLoadGraph(context, now),
            const SizedBox(height: AppSpacing.s8),
            _sectionHeader(
              context,
              Icons.quiz_outlined,
              kStudentInfo,
              'Upcoming Exams',
            ),
            const SizedBox(height: AppSpacing.s4),
            if (upcomingExams.isEmpty)
              const Text('No upcoming exams.')
            else
              for (final e in upcomingExams.take(2))
                _dotRow(
                  color: kStudentInfo,
                  label: subjectName(e.subjectId),
                  value: '${e.title} · ${formatDate(e.due)}',
                ),
            const SizedBox(height: AppSpacing.s4),
            _sectionHeader(
              context,
              Icons.assignment_outlined,
              kStudentWarning,
              'Assignment Deadlines',
            ),
            const SizedBox(height: AppSpacing.s4),
            if (upcomingAssignments.isEmpty)
              const Text('No upcoming assignments.')
            else
              for (final a in upcomingAssignments.take(2))
                _dotRow(
                  color: kStudentWarning,
                  label: subjectName(a.subjectId),
                  value: '${a.title} · ${formatDate(a.due)}',
                ),
            const SizedBox(height: AppSpacing.s8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _open(const ClassesScreen()),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('View Timetable'),
              ),
            ),
          ],
        ),
      ),
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

  /// Label/value row with a leading color dot (the subject's own
  /// color for class rows; the section color for exams/deadlines).
  /// Same label/value data as the old plain [_row].
  Widget _dotRow({
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
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

  /// Icon + bold title for a card section (Exams, Deadlines, the
  /// week graph). Icons are Material icons — never emoji.
  Widget _sectionHeader(
    BuildContext context,
    IconData icon,
    Color color,
    String title,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        // Expanded so a long title wraps instead of overflowing
        // the row (the test font measures wider than Inter).
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// "Your week at a glance" — a 7-bar chart of REAL class hours
  /// per day (Mon–Sun) from [classHoursByWeekday]: each bar is the
  /// subject's (endMin - startMin) summed over its meeting days.
  /// Today is the solid emerald bar; other days are the same color
  /// at 45% alpha. The total line is the real weekly sum + the real
  /// meeting count. With no subjects (or no scheduled hours) there
  /// is no fake chart — the honest empty state instead. Same
  /// container/bar pattern as the allowance card's monthly chart.
  Widget _weekLoadGraph(BuildContext context, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final hours = classHoursByWeekday(_subjects);
    final total = totalWeeklyClassHours(_subjects);
    final count = weeklyClassCount(_subjects);
    final maxHours =
        hours.fold<double>(0, (m, h) => h > m ? h : m);
    final todayIndex = now.weekday - 1; // Mon = 0 .. Sun = 6.
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          Icons.bar_chart_outlined,
          scheme.primary,
          'Your week at a glance',
        ),
        const SizedBox(height: AppSpacing.s4),
        Container(
          key: const ValueKey('week-load-graph'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.6),
            ),
          ),
          child: _subjects.isEmpty
              ? Text(
                  'No subjects yet — add your classes to see your weekly load.',
                  style: AppText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : total <= 0
                  ? Text(
                      'No class hours scheduled this week.',
                      style: AppText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 96,
                          child: Stack(
                            children: [
                              Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    Container(
                                      height: 1,
                                      color: scheme.outline
                                          .withValues(alpha: 0.5),
                                    ),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (var i = 0; i < 7; i++)
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            hours[i] > 0
                                                ? formatHours(hours[i])
                                                : '',
                                            style: AppText.micro.copyWith(
                                              color:
                                                  scheme.onSurfaceVariant,
                                              // Tight line height: the
                                              // test font measures ~2x
                                              // tall, which overflowed
                                              // the 96px chart box.
                                              height: 1.0,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            height: maxHours > 0
                                                ? 56 * (hours[i] / maxHours)
                                                : 2,
                                            width: 18,
                                            decoration: BoxDecoration(
                                              color: i == todayIndex
                                                  ? scheme.primary
                                                  : scheme.primary
                                                      .withValues(alpha: 0.45),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.s2),
                                          Text(
                                            dayLetters[i],
                                            style: AppText.micro.copyWith(
                                              color: i == todayIndex
                                                  ? scheme.primary
                                                  : null,
                                              fontWeight: i == todayIndex
                                                  ? FontWeight.w700
                                                  : null,
                                              // Same tight line height
                                              // as the value label.
                                              height: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          '${formatHours(total)} total · $count ${count == 1 ? 'class' : 'classes'} this week',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ notes

  /// True when [d] falls in the current Mon–Sun week.
  bool _isThisWeek(DateTime d) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(monday).inDays;
    return diff >= 0 && diff < 7;
  }

  /// Mon–Sun counts for the week-bars (preview viz-bars): how many
  /// of [dates] fall on each day of the current week. Dates outside
  /// this week count nowhere — a quiet week draws flat bars.
  List<int> _weekCounts(Iterable<DateTime> dates) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final counts = List<int>.filled(7, 0);
    for (final d in dates) {
      final day = DateTime(d.year, d.month, d.day);
      final diff = day.difference(monday).inDays;
      if (diff >= 0 && diff < 7) counts[diff]++;
    }
    return counts;
  }

  // ----------------------------------------------------------- commute
  // (Preserved from the previous dashboard so the module stays
  // reachable; it adapts to the light theme automatically.)

  Widget _commuteWidget(BuildContext context) {
    final rate = fares.fareRates.firstWhere((r) => r.id == 'trad-jeep');
    String? firstDistance;
    double? maxFare;
    for (final key in _savedKeys) {
      final parts = key.split('>');
      if (parts.length < 2) continue;
      final origin = _hubByName(parts[0]);
      final dest = _hubByName(parts[1]);
      if (origin == null || dest == null) continue;
      final roadKm = maps.roadKmBetween(
          origin.lat, origin.lng, dest.lat, dest.lng);
      firstDistance ??= '${roadKm.toStringAsFixed(1)} km';
      final fare = fares.computeFare(rate, roadKm, false).regular;
      if (maxFare == null || fare > maxFare) maxFare = fare;
    }
    final sortedExpenses = List.of(_commuteExpenses)
      ..sort((a, b) => b.date.compareTo(a.date));
    final counts = <String, int>{};
    for (final e in _commuteExpenses) {
      counts[e.routeKey] = (counts[e.routeKey] ?? 0) + 1;
    }
    final frequent = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _widgetCard(
      context,
      icon: Icons.route_outlined,
      title: 'My Commute',
      subtitle: 'Favorites, expenses, and map shortcuts.',
      onOpen: () => _open(CommuteScreen(onViewOnMap: widget.onViewOnMap)),
      children: [
        // Graph-first (preview parity, Nov 6): Saved Routes +
        // Est. Fare stat panels, then the week's trips as bars —
        // all from the real saved routes and logged expenses.
        Row(
          children: [
            _StatPanel(
              value: '${_savedKeys.length}',
              label: 'Routes',
              sub: 'Saved Routes · Shared with Map tab',
            ),
            const SizedBox(width: AppSpacing.s8),
            _StatPanel(
              value: maxFare == null ? '₱0' : peso(maxFare),
              label: 'max',
              sub: 'Est. Fare · Jeepney',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        _row('Trip distance', firstDistance ?? 'No hub route saved'),
        const Text(
          'Fares shown for traditional jeepney. Saved routes are shared with the Map tab.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          '${sortedExpenses.where((e) => _isThisWeek(e.date)).length} Trips this week',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        _WeekBars(
            values: _weekCounts(sortedExpenses.map((e) => e.date))),
        const SizedBox(height: AppSpacing.s8),
        const Text('Recent trips',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (sortedExpenses.isEmpty)
          const Text('No trips logged yet.')
        else
          for (final e in sortedExpenses.take(3))
            _row('${e.routeKey} · ${formatDate(e.date)}', peso(e.amount)),
        const SizedBox(height: AppSpacing.s4),
        const Text('Frequently visited',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (frequent.isEmpty && _commuteFavs.isEmpty)
          const Text('No frequent destinations yet.')
        else ...[
          for (final f in frequent.take(2))
            _row(f.key, '${f.value} trip${f.value == 1 ? '' : 's'}'),
          if (_commuteFavs.isNotEmpty)
            Text('Favorites: ${_commuteFavs.join(', ')}'),
        ],
        const SizedBox(height: AppSpacing.s4),
        const Text('Recent commute history',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (sortedExpenses.isEmpty)
          const Text('Log a commute expense to build your history.')
        else
          Text(
              '${sortedExpenses.length} logged trip${sortedExpenses.length == 1 ? '' : 's'} · latest ${formatDate(sortedExpenses.first.date)}'),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Quote copied.')));
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

  // -------------------------------------------------------- notifications
  // Preview port (Nov 6): Notifications as its own section in the
  // Inspiration & Calendar group. Opens the same honest empty
  // sheet as the bells — the app has no notification system, so
  // there is never a fake unread dot.

  Widget _notificationsWidget(BuildContext context) {
    return _widgetCard(
      context,
      icon: Icons.notifications_outlined,
      title: 'Notifications',
      subtitle: 'Stay in the loop.',
      onOpen: _showNotifications,
      children: const [
        Text('No notifications yet.'),
        SizedBox(height: AppSpacing.s4),
        Text(
          'This app does not have a notification system yet, so there is nothing to show here.',
          style: AppText.caption,
        ),
      ],
    );
  }

  // -------------------------------------------------------- attendance
  // (Preserved so the calendar, breakdown, and monthly report stay
  // reachable from the dashboard.)

  Widget _attendanceWidget(BuildContext context) {
    final now = DateTime.now();
    final monthRecords = _attendance
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final monthStats = attendanceStats(monthRecords);
    final bySubject = <String, List<AttendanceRecord>>{};
    for (final r in _attendance) {
      bySubject.putIfAbsent(r.subject, () => []).add(r);
    }
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final firstWeekday = monthStart.weekday; // 1 = Mon
    final schoolLabel = _school?.trim();
    final scheme = Theme.of(context).colorScheme;

    return _widgetCard(
      context,
      icon: Icons.calendar_month_outlined,
      title: 'School Calendar',
      subtitle: schoolLabel == null || schoolLabel.isEmpty
          ? 'School days and no-school days — holidays in red.'
          : '$schoolLabel · School days and no-school days',
      children: [
        Text('${monthName(now.month)} ${now.year}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
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
            final dayDate = DateTime(now.year, now.month, day);
            final kind = schoolDayKind(dayDate);
            final dayEvents = schoolEventsOnDay(_school, dayDate);
            final hasNoClassEvent = dayEvents.any((e) => e.noClasses);
            final isToday = day == now.day;
            final isHoliday = kind == SchoolDayKind.holiday;
            final Color? dayColor = switch (kind) {
              SchoolDayKind.holiday => scheme.error,
              SchoolDayKind.weekend => scheme.onSurfaceVariant,
              SchoolDayKind.schoolDay =>
                hasNoClassEvent ? scheme.onSurfaceVariant : null,
            };
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Google Calendar style: today is a filled emerald
                  // circle with white text.
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: kStudentEmerald,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 12,
                        color: isToday ? Colors.white : dayColor,
                        fontWeight: isToday || isHoliday
                            ? FontWeight.w800
                            : null,
                      ),
                    ),
                  ),
                  // Red dot under real holidays; blue dot under
                  // school events.
                  if (isHoliday)
                    const Icon(Icons.circle, size: 6, color: Colors.red)
                  else if (dayEvents.isNotEmpty)
                    const Icon(Icons.circle, size: 6, color: kStudentInfo),
                ],
              ),
            );
          },
        ),
        // Legend (preview parity, Nov 6): holidays are red numbers
        // + dots on the dates themselves — no holiday text list —
        // and the Add school chip opens the Account tab, where the
        // school lives under Student Information.
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: scheme.error),
                const SizedBox(width: AppSpacing.s4),
                const Text('Holiday'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.circle,
                    size: 8, color: kStudentEmerald),
                const SizedBox(width: AppSpacing.s4),
                const Text('Today'),
              ],
            ),
            ActionChip(
              label: const Text('Add school'),
              onPressed: widget.onViewAccount,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        const Text('Subject breakdown',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s8),
        Center(
          child: _VizDonut(
            segments: [
              for (var i = 0; i < bySubject.entries.length; i++)
                (
                  color: _vizPalette[i % _vizPalette.length],
                  value: bySubject.entries
                      .elementAt(i)
                      .value
                      .length
                      .toDouble(),
                ),
            ],
            centerTop: '${bySubject.length} Subjects',
            centerBottom: '${_attendance.length} Records',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        if (bySubject.isEmpty)
          const Text('No records yet.')
        else
          for (var i = 0; i < bySubject.entries.length; i++)
            _row(
              bySubject.entries.elementAt(i).key,
              '${attendanceStats(bySubject.entries.elementAt(i).value).percent.toStringAsFixed(1)}% · ${bySubject.entries.elementAt(i).value.length} records',
            ),
        const SizedBox(height: AppSpacing.s4),
        const Text('Monthly report',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s8),
        Center(
          child: _VizDonut(
            segments: [
              (color: kStudentEmerald, value: monthStats.present.toDouble()),
              (color: scheme.error, value: monthStats.absent.toDouble()),
            ],
            centerTop:
                '${monthStats.percent.toStringAsFixed(1)}%',
            centerBottom: 'Present',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        _row('Present', '${monthStats.present}'),
        _row('Absent', '${monthStats.absent}'),
        Text('${monthRecords.length} records',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ------------------------------------------------------------ viz
// (Preview graph-first Student sections, Nov 6, 2026.)
//
// Ring / gauge / donut / week-bars drawn with CustomPainter —
// pure draws, no animation controller, so they are reduced-motion
// safe by construction and show the final value immediately.
// Every value comes from the app's real data; empty data draws an
// empty track with a "0" centre, never invented numbers.

/// Palette for donut segments (subject breakdown, monthly report).
const _vizPalette = <Color>[
  Color(0xFF16A34A),
  Color(0xFF2563EB),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFFEC4899),
];


class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.trackColor});

  /// (color, value) segments; empty or all-zero draws the track only.
  final List<({Color color, double value})> segments;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 14.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth / 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = math.pi * 2 * (seg.value / total);
      final fill = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        fill,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments;
}


/// Donut with a two-line centre label (preview "viz-donut":
/// Subject breakdown, Monthly report).
class _VizDonut extends StatelessWidget {
  const _VizDonut({
    required this.segments,
    required this.centerTop,
    required this.centerBottom,
  });

  final List<({Color color, double value})> segments;
  final String centerTop;
  final String centerBottom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(120, 120),
            painter: _DonutPainter(
              segments: segments,
              trackColor: scheme.outlineVariant,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerTop,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              Text(centerBottom,
                  textAlign: TextAlign.center, style: AppText.small),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mon–Sun bar chart (preview "viz-bars": Trips this week,
/// Quizzes this week). Bars scale to the week's max; zero weeks
/// draw flat tracks, never fake heights.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.values});

  /// 7 counts, Monday first.
  final List<int> values;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = values.fold<int>(0, (m, v) => v > m ? v : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${values[i]}', style: AppText.small),
                const SizedBox(height: 2),
                Container(
                  height: 36,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 14,
                    height: max == 0
                        ? 2
                        : 4 + 32 * (values[i] / max),
                    decoration: BoxDecoration(
                      color: values[i] == 0
                          ? scheme.outlineVariant
                          : kStudentEmerald,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(_labels[i], style: AppText.small),
              ],
            ),
          ),
      ],
    );
  }
}

/// Big-value stat panel (preview "viz-panel": Saved Routes,
/// Est. Fare).
class _StatPanel extends StatelessWidget {
  const _StatPanel({
    required this.value,
    required this.label,
    this.sub,
  });

  final String value;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (sub != null)
              Text(sub!, style: AppText.small),
          ],
        ),
      ),
    );
  }
}


