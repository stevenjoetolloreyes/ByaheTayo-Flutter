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
import 'package:flutter/material.dart';

import '../app_layout.dart';
import '../points_wallet_repository.dart';
import 'student_data.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key, this.userId, this.walletController});

  /// The signed-in user's UID. Null in bare widget tests (legacy
  /// local-only mode).
  final String? userId;

  /// Shared wallet state. Null in bare widget tests (legacy
  /// local-only mode).
  final PointsWalletController? walletController;

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  List<CheckinRecord> _records = [];
  bool _claiming = false;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(dayIndex == 7
            ? 'Day 7 complete! +$points points.'
            : 'Checked in! Day $dayIndex · +$points points.'),
      ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(outcome.dayIndex == 7
                ? 'Day 7 complete! +${outcome.points} points.'
                : 'Checked in! Day ${outcome.dayIndex} '
                    '· +${outcome.points} points.'),
          ),
        );
      case ClaimStatus.alreadyClaimed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already checked in today.')),
        );
      case ClaimStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not sync your check-in. Check your '
                'connection and try again.'),
          ),
        );
      case ClaimStatus.unavailable:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = _today;
    final streak = checkinStreak(_records, today);
    final checkedToday = hasCheckedInToday(_records, today);
    final checkedCells = currentCycleChecked(_records, today);
    final todayDay = checkedToday
        ? _records
            .firstWhere((r) => dateKey(r.date) == dateKey(today))
            .dayIndex
        : nextCycleDay(streak);
    final total = totalCheckinPoints(_records);

    return Scaffold(
      appBar: AppBar(title: const Text('7-Day Sign-in')),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          Card(
            child: Padding(
              padding: AppLayout.cardPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current streak'),
                        Text('$streak day${streak == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total points'),
                        Text('$total pts',
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          const Text('This cycle',
              style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              for (var day = 1; day <= 7; day++)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: day <= checkedCells
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          border: day == todayDay
                              ? Border.all(
                                  color: scheme.primary, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          day <= checkedCells
                              ? Icons.check
                              : (day == 7
                                  ? Icons.star_outline
                                  : Icons.circle_outlined),
                          size: 20,
                          color: day <= checkedCells
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text('Day $day',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          LinearProgressIndicator(value: checkedCells / 7),
          const SizedBox(height: AppSpacing.s2),
          Text('Weekly progress: $checkedCells/7 days'),
          const SizedBox(height: AppLayout.headerGap),
          if (checkedToday)
            Card(
              child: ListTile(
                leading:
                    Icon(Icons.check_circle, color: scheme.primary),
                title: const Text('Checked in today'),
                subtitle: Text(
                    'Day $todayDay · +${pointsForDay(todayDay)} points earned today. Come back tomorrow.'),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _claiming ? null : _checkIn,
              icon: const Icon(Icons.check),
              label: Text(todayDay == 7
                  ? 'Check in — Day 7 reward!'
                  : 'Check in today · Day $todayDay'),
            ),
          const SizedBox(height: AppLayout.headerGap),
          const Text('Daily rewards',
              style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.s4),
          const Text('Day 1–6: 10 points each · Day 7: 50 points '
              '(completion reward).'),
          const SizedBox(height: AppLayout.headerGap),
          const Text('Check-in history',
              style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.s8),
          if (_records.isEmpty)
            const Card(
                child: ListTile(title: Text('No check-in history yet.')))
          else
            for (final r in _records)
              Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle,
                      color: scheme.primary, size: 20),
                  title: Text(formatDate(r.date)),
                  subtitle: Text('Day ${r.dayIndex} of 7'),
                  trailing: Text('+${r.points} pts',
                      style:
                          const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
          const SizedBox(height: AppLayout.headerGap),
          Text(
            _remote
                ? 'Dates follow Asia/Manila time. Points are saved to your account and show in your Account Points Wallet.'
                : 'Dates follow this phone\'s calendar (Asia/Manila). Points are saved on this device only and are separate from the Account Points Wallet.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
