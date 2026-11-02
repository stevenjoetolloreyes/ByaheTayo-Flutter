// Shared presentation for the approved 7-Day Sign-in redesign
// (Student Hub card + full Details Page). These widgets render
// ONLY values derived from the existing check-in records / wallet
// controller — never hardcoded days, points, or progress. The
// backend (points_wallet_repository.dart) is untouched: Day 1-6 =
// 10 points, Day 7 = 50, cycle total 110, Manila dates, idempotent
// ledger claims.
import 'package:flutter/material.dart';

import '../app_layout.dart';
import 'student_data.dart';
import 'student_theme.dart';

/// Spec palette additions (deep emerald / bright green come from
/// student_theme.dart as kStudentEmerald / kStudentEmeraldAccent).
const kSigninLightGreen = Color(0xFFDCFCE7);
const kSigninPageBg = Color(0xFFF5F7FA);
const kSigninGold = Color(0xFFF59E0B);
const kSigninPaleGold = Color(0xFFFEF3C7);
const kSigninGrayTile = Color(0xFFF1F5F9);
const kSigninGrayIcon = Color(0xFF94A3B8);
const kSigninFlame = Color(0xFFF97316);
const kSigninFlameTile = Color(0xFFFFEDD5);
const kSigninTrack = Color(0xFFE2E8F0);

/// The seven day tiles, shared by the Student Hub card and the
/// Details Page so both always agree.
///
/// States (all from real records):
/// - completed (day <= [checkedCells]): light green tile + green
///   check circle; Day 7 keeps its gold tile.
/// - current (day == [currentDay], not yet checked today): deep
///   emerald highlighted tile + white outlined circle.
/// - Day 7 upcoming: gold tile + gift icon.
/// - upcoming: light gray tile + gray outlined circle.
///
/// [showPoints] adds the per-day reward label under each tile
/// ("+10 pts", Day 7 "+50 pts") on the Details Page; the Hub card
/// shows compact "D1".."D7" labels instead.
class SigninDayTiles extends StatelessWidget {
  const SigninDayTiles({
    super.key,
    required this.checkedCells,
    required this.currentDay,
    required this.checkedToday,
    this.showPoints = false,
  });

  final int checkedCells;
  final int currentDay;
  final bool checkedToday;
  final bool showPoints;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var day = 1; day <= 7; day++)
          Expanded(child: _tile(day)),
      ],
    );
  }

  Widget _tile(int day) {
    final completed = day <= checkedCells;
    final current = !checkedToday && day == currentDay;
    final Color tileColor;
    final IconData icon;
    final Color iconColor;
    if (completed) {
      tileColor = day == 7 ? kSigninPaleGold : kSigninLightGreen;
      icon = Icons.check_circle_rounded;
      iconColor = kStudentEmeraldAccent;
    } else if (current) {
      tileColor = kStudentEmerald;
      icon = Icons.radio_button_unchecked_rounded;
      iconColor = Colors.white;
    } else if (day == 7) {
      tileColor = kSigninPaleGold;
      icon = Icons.card_giftcard_rounded;
      iconColor = kSigninGold;
    } else {
      tileColor = kSigninGrayTile;
      icon = Icons.radio_button_unchecked_rounded;
      iconColor = kSigninGrayIcon;
    }
    final labelColor =
        current ? Colors.white : kStudentText;
    final subColor =
        current ? Colors.white70 : kStudentSubtext;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(height: 4),
          Text(
            showPoints ? 'Day $day' : 'D$day',
            style: AppText.tiny.copyWith(color: labelColor),
          ),
          if (showPoints)
            Text(
              '+${pointsForDay(day)} pts',
              style: AppText.tiny.copyWith(color: subColor),
            ),
        ],
      ),
    );
  }
}

/// Animated green progress bar for the sign-in cycle. Animates
/// smoothly to the new value whenever the completed count changes
/// (e.g. right after a successful check-in).
class AnimatedSigninProgressBar extends StatelessWidget {
  const AnimatedSigninProgressBar({super.key, required this.value});

  /// Completed fraction, 0..1.
  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, animated, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: animated,
            minHeight: 8,
            backgroundColor: kSigninTrack,
            valueColor: const AlwaysStoppedAnimation<Color>(
                kStudentEmeraldAccent),
          ),
        );
      },
    );
  }
}

/// Reward schedule bottom sheet, opened from the Hub card's
/// "Next Reward" stat. Every value comes from the shared reward
/// table ([pointsForDay]); the cycle total is summed from it, so
/// the sheet can never disagree with the backend.
void showSigninRewardSchedule(BuildContext context) {
  final cycleTotal =
      List.generate(7, (i) => pointsForDay(i + 1)).reduce((a, b) => a + b);
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => Padding(
      padding: AppLayout.pagePaddingLarge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                child: const Icon(Icons.trending_up_rounded,
                    color: kStudentEmeraldAccent, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Reward schedule',
                    style: AppText.headingStrong),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: kStudentEmeraldAccent, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Day 1 – 6: 10 points each')),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          const Row(
            children: [
              Icon(Icons.card_giftcard_rounded,
                  color: kSigninGold, size: 20),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Day 7: 50 points (completion reward)')),
            ],
          ),
          const Divider(height: 24),
          Text('Full cycle: $cycleTotal points',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.s4),
          const Text(
            'Points come from your Points Wallet ledger — there is '
            'no separate balance. One check-in per day, Asia/Manila '
            'time; a missed day restarts the streak.',
            style: AppText.caption,
          ),
        ],
      ),
    ),
  );
}
