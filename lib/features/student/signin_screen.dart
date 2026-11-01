// 7-Day Attendance Sign-in — daily check-in with streaks and
// local reward points.
//
// This is NOT the Attendance Sheet (class attendance records). A
// sign-in is a once-a-day app check-in: one record per calendar date
// (Asia/Manila device date), a streak of consecutive days, a 7-day
// cycle with a Day 7 completion reward, and a history log. Points are
// always re-derived from the record log — never from a stored counter
// — and duplicate check-ins are blocked both in the UI and in the
// save handler. Points live on this device only and are separate
// from the Account Points Wallet (which needs an account backend).
import 'package:flutter/material.dart';

import 'student_data.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  List<CheckinRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
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
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 12),
          const Text('This cycle',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
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
                      const SizedBox(height: 2),
                      Text('Day $day',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: checkedCells / 7),
          const SizedBox(height: 2),
          Text('Weekly progress: $checkedCells/7 days'),
          const SizedBox(height: 16),
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
              onPressed: _checkIn,
              icon: const Icon(Icons.check),
              label: Text(todayDay == 7
                  ? 'Check in — Day 7 reward!'
                  : 'Check in today · Day $todayDay'),
            ),
          const SizedBox(height: 16),
          const Text('Daily rewards',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Day 1–6: 10 points each · Day 7: 50 points '
              '(completion reward).'),
          const SizedBox(height: 16),
          const Text('Check-in history',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
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
          const SizedBox(height: 16),
          const Text(
            'Dates follow this phone\'s calendar (Asia/Manila). Points are saved on this device only and are separate from the Account Points Wallet.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
