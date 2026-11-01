// Student Overview Dashboard — redesigned per the Nov 1 reference
// image (premium light emerald), NOT a new app.
//
// Layout: single column of full-width landscape cards on every
// screen size (his 12:09 correction overruled the earlier 2/3-column
// grid: on tablets it looked sparse with mismatched card heights).
// Section order follows the landscape spec: Sign-in, Bible,
// Allowance, Classes, Notes, Upcoming, Tasks,
// then the School Calendar, Quotes, and Commute.
//
// Honest mappings for reference-only items:
// - Tasks shortcut -> Classes screen (assignments live there).
// - Events section -> honest "No upcoming events." (no events
//   system exists; nothing is invented).
// - Notification bell -> honest empty sheet (no notification
//   system exists, so there is never a fake unread dot).
// - Profile circle -> placeholder icon until an account system
//   exists; no photo is baked into the app.
// - Greeting name "Steven" matches the reference mockup; it becomes
//   dynamic when an account system exists.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ph_holidays.dart';
import 'school_events.dart';
import 'student/allowance_screen.dart';
import 'student/attendance_screen.dart';
import 'student/bible_screen.dart';
import 'student/classes_screen.dart';
import 'student/commute_screen.dart';
import 'student/notes_screen.dart';
import 'student/quotes_screen.dart';
import 'student/share_card.dart';
import 'student/signin_screen.dart';
import 'student/student_data.dart';
import 'student/student_theme.dart';
import 'fares_tab.dart' as fares;
import 'map_tab.dart' as maps;

class StudentTab extends StatefulWidget {
  const StudentTab({super.key, this.onViewOnMap, this.onViewAccount});

  /// Switches the shell to the Map tab (used by My Commute jumps).
  final VoidCallback? onViewOnMap;

  /// Switches the shell to the Account tab. Null in bare widget tests.
  final VoidCallback? onViewAccount;

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
  List<Note> _notes = [];
  List<Quiz> _quizzes = [];
  List<QuizAttempt> _attempts = [];
  List<AttendanceRecord> _attendance = [];

  List<String> _savedKeys = [];
  List<String> _commuteFavs = [];
  List<CommuteExpense> _commuteExpenses = [];
  List<CheckinRecord> _checkins = [];
  Set<String> _quoteFavs = {};
  List<String> _quoteHistory = [];
  String? _school;
  final _quoteKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
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
    final notes = await StudentStorage.loadList(StudentStorage.notesKey);
    final quizzes =
        await StudentStorage.loadList(StudentStorage.quizzesKey);
    final attempts =
        await StudentStorage.loadList(StudentStorage.attemptsKey);
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
      _notes = notes.map(Note.fromJson).toList();
      _quizzes = quizzes.map(Quiz.fromJson).toList();
      _attempts = attempts.map(QuizAttempt.fromJson).toList();
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

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentTheme(child: screen)),
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
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('No notifications yet.'),
            SizedBox(height: 4),
            Text(
              'This app does not have a notification system yet, so there is nothing to show here.',
              style: TextStyle(fontSize: 13),
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
    final wide = MediaQuery.sizeOf(context).width >= 600;
    // Single column of full-width cards on EVERY screen size (his
    // 12:09 correction: the tablet 2/3-column grid looked sparse
    // with mismatched card heights — "wag ganito"). Sections stack
    // in spec order; shortcuts stay responsive (3x2 grid on phones,
    // one row of 6 on wide screens).
    final sections = [
      _signinWidget(context),
      _bibleWidget(context),
      _allowanceWidget(context),
      _classesWidget(context),
      _notesWidget(context),
      _upcomingWidget(context),
      _tasksWidget(context),
      _attendanceWidget(context),
      _quotesWidget(context),
      _commuteWidget(context),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          studentHeader(
            greetingName: greetingFor(DateTime.now()),
            onBell: _showNotifications,
          ),
          const SizedBox(height: 16),
          _quickAccess(context, wide),
          for (final s in sections) ...[
            const SizedBox(height: 12),
            s,
          ],
          const SizedBox(height: 16),
        ],
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (onOpen != null) const Icon(Icons.chevron_right),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onOpen == null)
              header
            else
              InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(12),
                child: header,
              ),
            const SizedBox(height: 12),
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

  // ------------------------------------------------------- quick access

  Widget _quickAccess(BuildContext context, bool wide) {
    final items = [
      ('Attendance', Icons.fact_check_outlined,
          () => _open(const AttendanceScreen())),
      ('Classes', Icons.menu_book_outlined,
          () => _open(const ClassesScreen())),
      ('Tasks', Icons.checklist_outlined,
          () => _open(const ClassesScreen())),
      ('Notes', Icons.note_outlined,
          () => _open(const NotesScreen())),
      ('Quizzes', Icons.quiz_outlined,
          () => _open(const NotesScreen(initialTab: 'quizzes'))),
      ('Budgeting', Icons.account_balance_wallet_outlined,
          () => _open(const AllowanceScreen())),
    ];
    final cards = items
        .map((item) => Card(
              child: InkWell(
                onTap: item.$3,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.$2,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 6),
                      Text(item.$1,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ))
        .toList();
    if (wide) {
      return Row(
        children: [
          for (final c in cards) Expanded(child: c),
        ],
      );
    }
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.95,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      children: cards,
    );
  }

  // ------------------------------------------------------------ sign-in

  /// 7-Day Sign-in card. The WHOLE card is one tap target into the
  /// dedicated sign-in page.
  Widget _signinWidget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final streak = checkinStreak(_checkins, today);
    final checkedToday = hasCheckedInToday(_checkins, today);
    final checkedCells = currentCycleChecked(_checkins, today);
    final todayDay = checkedToday
        ? _checkins
            .firstWhere((r) => dateKey(r.date) == dateKey(today))
            .dayIndex
        : nextCycleDay(streak);
    return Card(
      child: InkWell(
        onTap: () => _open(const SigninScreen()),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        scheme.secondary.withValues(alpha: 0.15),
                    child: Icon(Icons.local_fire_department,
                        color: scheme.secondary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('7-Day Sign-in',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        Text('Build your study habit!',
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Day $todayDay of 7',
                        style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var day = 1; day <= 7; day++)
                    Expanded(
                      child: Column(
                        children: [
                          Icon(
                            day <= checkedCells
                                ? (day == 7
                                    ? Icons.star
                                    : Icons.check_circle)
                                : (day == 7
                                    ? Icons.star_outline
                                    : Icons.circle_outlined),
                            size: 24,
                            color: day <= checkedCells
                                ? scheme.secondary
                                : scheme.onSurfaceVariant,
                          ),
                          Text('D$day',
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: checkedCells / 7),
              const SizedBox(height: 4),
              Text(
                  'Weekly progress: $checkedCells/7 · Total points: ${totalCheckinPoints(_checkins)}'),
              Text('$streak day streak',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(checkedToday
                  ? 'Checked in today · Day $todayDay'
                  : 'Not checked in yet · Day $todayDay'),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- bible

  Widget _bibleWidget(BuildContext context) {
    final daily = verseOfDay(DateTime.now());
    return Card(
      child: InkWell(
        onTap: () => _open(const BibleScreen()),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kStudentEmerald, kStudentEmeraldAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Bible Verse',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '"${daily.text}"',
                style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${daily.ref} (KJV)',
                    style: const TextStyle(
                        color: kStudentEmerald,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
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
    final recent = List.of(_txns)
      ..sort((a, b) => b.date.compareTo(a.date));

    Widget miniBox(String label, String value, Color color) {
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
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      );
    }

    return _widgetCard(
      context,
      icon: Icons.account_balance_wallet_outlined,
      title: 'Allowance & Budgeting',
      subtitle: 'Track your money, spend wisely.',
      onOpen: () => _open(const AllowanceScreen()),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: kStudentEmerald,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Available Balance',
                        style: TextStyle(color: Colors.white70)),
                    Text(
                      _hideBalance ? '₱••••' : peso(balance),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ],
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
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            miniBox('Income', peso(totalIncome), scheme.secondary),
            const SizedBox(width: 8),
            miniBox('Expenses', peso(totalExpense), Colors.red),
            const SizedBox(width: 8),
            miniBox(
                'Remaining',
                _budgets.isEmpty
                    ? 'No budgets'
                    : peso(budgetTotal - budgetedSpent),
                scheme.primary),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Monthly Spending (Last 6 Months)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in bars)
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: maxBar > 0 ? 48 * (b.amount / maxBar) : 2,
                      width: 18,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(b.label, style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Budget Utilization',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (_budgets.isEmpty)
          const Text('No budget limits set yet.')
        else
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
                    Text('${b.category}: ${peso(spent)} of ${peso(b.limit)}'),
                    const SizedBox(height: 2),
                    LinearProgressIndicator(
                      value: b.limit > 0
                          ? (spent / b.limit).clamp(0, 1).toDouble()
                          : 0,
                    ),
                  ],
                ),
              );
            }),
        const SizedBox(height: 8),
        const Text('Savings Progress',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (_goals.isEmpty)
          const Text('No savings goals yet.')
        else
          for (final g in _goals.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${g.name}: ${peso(g.saved)} of ${peso(g.target)}'),
                  const SizedBox(height: 2),
                  LinearProgressIndicator(
                    value: g.target > 0
                        ? (g.saved / g.target).clamp(0, 1).toDouble()
                        : 0,
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        const Text('Recent Transactions',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (recent.isEmpty)
          const Text('No transactions yet.')
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

    Widget tabBody;
    if (_classesTab == 'today') {
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next != null)
            _row('Next class',
                '${next.subject.name} · ${weekdayName(next.date.weekday)} ${formatMinutes(next.subject.startMin)}'),
          if (todays.isEmpty) ...[
            const Text('No classes today.',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Relax, study, or get ahead on your tasks!'),
          ] else
            for (final s in todays)
              _row(
                '${formatMinutes(s.startMin)}–${formatMinutes(s.endMin)} · ${s.name}',
                '${s.room.isEmpty ? '' : '${s.room} '}${s.teacher}',
              ),
        ],
      );
    } else if (_classesTab == 'week') {
      final days = <Widget>[];
      for (var day = 1; day <= 7; day++) {
        final dayClasses = classesOnDay(_subjects, day);
        if (dayClasses.isEmpty) continue;
        days.add(_row(
          weekdayName(day),
          dayClasses.map((s) => s.name).join(', '),
        ));
      }
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (days.isEmpty) const Text('No classes this week.'),
          ...days,
        ],
      );
    } else {
      tabBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_subjects.isEmpty)
            const Text('No subjects yet.')
          else
            for (final s in _subjects)
              _row(
                s.code.isEmpty ? s.name : '${s.name} (${s.code})',
                '${s.teacher}${s.room.isEmpty ? '' : ' · ${s.room}'}',
              ),
        ],
      );
    }

    return _widgetCard(
      context,
      icon: Icons.calendar_month_outlined,
      title: 'Classes & Timetable',
      subtitle: 'Your schedule at a glance.',
      onOpen: () => _open(const ClassesScreen()),
      children: [
        _row('Total Subjects', '${_subjects.length}'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'today', label: Text('Today')),
            ButtonSegment(value: 'week', label: Text('This Week')),
            ButtonSegment(value: 'all', label: Text('All Classes')),
          ],
          selected: {_classesTab},
          onSelectionChanged: (s) => setState(() => _classesTab = s.first),
        ),
        const SizedBox(height: 8),
        tabBody,
        const SizedBox(height: 8),
        const Text('Upcoming Exams',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (upcomingExams.isEmpty)
          const Text('No upcoming exams.')
        else
          for (final e in upcomingExams.take(2))
            _row(subjectName(e.subjectId), '${e.title} · ${formatDate(e.due)}'),
        const SizedBox(height: 4),
        const Text('Assignment Deadlines',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (upcomingAssignments.isEmpty)
          const Text('No upcoming assignments.')
        else
          for (final a in upcomingAssignments.take(2))
            _row(subjectName(a.subjectId),
                '${a.title} · ${formatDate(a.due)}'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _open(const ClassesScreen()),
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: const Text('View Timetable'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ notes

  Widget _notesWidget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attemptedIds = <String>{};
    for (final a in _attempts) {
      attemptedIds.add(a.quizTitle);
    }
    final notAttempted =
        _quizzes.where((q) => !attemptedIds.contains(q.title)).toList();
    double avg = 0;
    if (_attempts.isNotEmpty) {
      var sum = 0.0;
      for (final a in _attempts) {
        if (a.total > 0) sum += a.score / a.total * 100;
      }
      avg = sum / _attempts.length;
    }
    final notes = List.of(_notes)
      ..sort((a, b) => b.updated.compareTo(a.updated));
    final attempts = List.of(_attempts)
      ..sort((a, b) => b.date.compareTo(a.date));

    Widget statBox(IconData icon, String value, String label) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _widgetCard(
      context,
      icon: Icons.quiz_outlined,
      title: 'Review Notes & Quizzes',
      subtitle: 'Study, practice, and track your progress.',
      onOpen: () => _open(const NotesScreen()),
      children: [
        Row(
          children: [
            statBox(Icons.note_outlined, '${_notes.length}', 'Saved Notes'),
            const SizedBox(width: 8),
            statBox(Icons.quiz_outlined, '${_quizzes.length}', 'Quizzes'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            statBox(Icons.check_circle_outlined, '${_attempts.length}',
                'Completed'),
            const SizedBox(width: 8),
            statBox(Icons.bar_chart_outlined,
                _attempts.isEmpty ? '—' : '${avg.toStringAsFixed(1)}%',
                'Avg. Score'),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Learning Progress',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (_attempts.isEmpty)
          const Text('Take a quiz to start tracking progress.')
        else
          LinearProgressIndicator(
              value: (avg / 100).clamp(0, 1).toDouble()),
        const SizedBox(height: 8),
        const Text('Recent Study Activity',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (notes.isEmpty && attempts.isEmpty)
          const Text('No recent study activity.')
        else ...[
          if (notes.isNotEmpty) _row('Latest note', notes.first.title),
          if (attempts.isNotEmpty)
            _row('Latest quiz',
                '${attempts.first.quizTitle} · ${attempts.first.score}/${attempts.first.total}'),
        ],
        if (notAttempted.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text('Upcoming Study Tasks',
              style: TextStyle(fontWeight: FontWeight.w700)),
          for (final q in notAttempted.take(2))
            _row('Quiz to take', q.title),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _open(const NotesScreen(initialTab: 'quizzes')),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Take a Quiz'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- upcoming

  Widget _upcomingWidget(BuildContext context) {
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

    return _widgetCard(
      context,
      icon: Icons.event_outlined,
      title: 'Upcoming',
      subtitle: 'Your next important activities.',
      onOpen: () => _open(const ClassesScreen()),
      children: [
        const Text('Exams', style: TextStyle(fontWeight: FontWeight.w700)),
        if (upcomingExams.isEmpty)
          const Text('No upcoming exams.')
        else
          for (final e in upcomingExams.take(2))
            _row(subjectName(e.subjectId), '${e.title} · ${formatDate(e.due)}'),
        const SizedBox(height: 8),
        const Text('Assignments',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (upcomingAssignments.isEmpty)
          const Text('No upcoming assignments.')
        else
          for (final a in upcomingAssignments.take(2))
            _row(subjectName(a.subjectId),
                '${a.title} · ${formatDate(a.due)}'),
        const SizedBox(height: 8),
        const Text('Events', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('No upcoming events.'),
      ],
    );
  }

  // ------------------------------------------------- tasks & assignments

  Widget _tasksWidget(BuildContext context) {
    final pending = _assignments.where((a) => !a.done).toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    String subjectName(String id) {
      for (final s in _subjects) {
        if (s.id == id) return s.name;
      }
      return 'Subject';
    }

    return _widgetCard(
      context,
      icon: Icons.checklist_outlined,
      title: 'Tasks & Assignments',
      subtitle: 'What is due next.',
      onOpen: () => _open(const ClassesScreen()),
      children: [
        _row('Pending tasks', '${pending.length}'),
        if (pending.isEmpty)
          const Text('No pending tasks.')
        else
          for (final a in pending.take(4))
            _row(subjectName(a.subjectId),
                '${a.title} · ${formatDate(a.due)}'),
      ],
    );
  }

  // ----------------------------------------------------------- commute
  // (Preserved from the previous dashboard so the module stays
  // reachable; it adapts to the light theme automatically.)

  Widget _commuteWidget(BuildContext context) {
    final rate = fares.fareRates.firstWhere((r) => r.id == 'trad-jeep');
    String? firstDistance;
    String? firstFare;
    for (final key in _savedKeys) {
      final parts = key.split('>');
      if (parts.length < 2) continue;
      final origin = _hubByName(parts[0]);
      final dest = _hubByName(parts[1]);
      if (origin == null || dest == null) continue;
      final roadKm = maps.roadKmBetween(
          origin.lat, origin.lng, dest.lat, dest.lng);
      firstDistance = '${roadKm.toStringAsFixed(1)} km';
      firstFare = peso(fares.computeFare(rate, roadKm, false).regular);
      break;
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
        _row('Saved routes', '${_savedKeys.length}'),
        _row('Trip distance', firstDistance ?? 'No hub route saved'),
        _row('Estimated fare (jeepney)', firstFare ?? '—'),
        const Text(
          'Fares shown for traditional jeepney. Saved routes are shared with the Map tab.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text('Recent trips',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (sortedExpenses.isEmpty)
          const Text('No trips logged yet.')
        else
          for (final e in sortedExpenses.take(3))
            _row('${e.routeKey} · ${formatDate(e.date)}', peso(e.amount)),
        const SizedBox(height: 4),
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
        const SizedBox(height: 4),
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
        const SizedBox(height: 4),
        Text('${daily.category} · Quote of the Day',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
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
            const SizedBox(width: 8),
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
                color: _quoteFavs.contains(daily.id) ? Colors.red : null,
              ),
              onPressed: () => _toggleQuoteFav(daily.id),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
    final monthHolidays = philippineHolidaysInMonth(now.year, now.month);
    final monthEvents = schoolEventsInMonth(_school, now.year, now.month);
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
        const SizedBox(height: 4),
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
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: isToday
                        ? BoxDecoration(
                            border: Border.all(color: scheme.primary),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 12,
                        color: dayColor,
                        fontWeight: kind == SchoolDayKind.holiday
                            ? FontWeight.w800
                            : null,
                      ),
                    ),
                  ),
                  if (dayEvents.isNotEmpty)
                    const Icon(Icons.circle, size: 6, color: Colors.blue),
                ],
              ),
            );
          },
        ),
        if (monthHolidays.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Holidays this month',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final h in monthHolidays)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${monthShortName(now.month)} ${h.day} · ${h.name}'),
                  ),
                ],
              ),
            ),
        ],
        if (schoolLabel == null || schoolLabel.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
              'No school saved — add your school in Account → Student Information to show school events here.'),
        ] else if (monthEvents.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Events this month',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final e in monthEvents)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${formatEventRange(e)} · ${e.name} · ${e.noClasses ? 'No classes' : 'Has classes'}'),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        const Text('Subject breakdown',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (bySubject.isEmpty)
          const Text('No records yet.')
        else
          for (final e in bySubject.entries)
            _row(e.key,
                '${attendanceStats(e.value).percent.toStringAsFixed(1)}% · ${e.value.length} records'),
        const SizedBox(height: 4),
        const Text('Monthly report',
            style: TextStyle(fontWeight: FontWeight.w700)),
        Text(
            'This month: ${monthStats.percent.toStringAsFixed(1)}% · ${monthRecords.length} records · Present ${monthStats.present} · Absent ${monthStats.absent}'),
      ],
    );
  }
}


