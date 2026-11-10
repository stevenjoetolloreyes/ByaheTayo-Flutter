// Game-style Student tab entrance (Feature 5 of the startup
// preview -> real app build).
//
// Plays ONCE, only when the Student tab appears right after the
// Welcome Back overlay finishes (Sign In path — see
// [StudentTab.playEntrance]). Every element staggers in
// top-to-bottom with a spring-overshoot bounce (~70 ms apart),
// the whole entrance taking ~2 s. All animated values are the
// LIVE ones — the points count-up ends at the real wallet balance,
// the Walking Goal fill ends at the real walking progress, and the
// streak celebration ticks in the real checked day cells —
// nothing here hardcodes a sample number.
//
// Reduced motion (MediaQuery.disableAnimations) skips the whole
// entrance: the tab shows static, instantly. Starting the Watch
// demo tour while the entrance is playing completes the entrance
// cleanly (all values jump to their live end states) so the tour
// takes over without a fight.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Total entrance length. The last item starts at 14 x 70 ms and
/// runs 500 ms, so everything lands by ~1.5 s; the remaining time
/// is the tail for the points count-up and the confetti burst.
const studentEntranceDuration = Duration(milliseconds: 2000);

/// Stagger between consecutive items.
const studentEntranceStagger = Duration(milliseconds: 70);

/// How long one item's slide + bounce runs.
const studentEntranceItemDuration = Duration(milliseconds: 500);

/// Number of staggered items on the tab, top to bottom (see the
/// index constants below — they must match the build order in
/// StudentTab.build).
const kStudentEntranceItemCount = 15;

/// Stagger indices, in the tab's top-to-bottom build order.
const studentEntranceHeaderIndex = 0;
const studentEntranceWatchDemoIndex = 1;
const studentEntranceAtAGlanceIndex = 2;
const studentEntranceRewardsHeaderIndex = 3;
const studentEntranceSigninIndex = 4;
const studentEntranceRewardsIndex = 5;
const studentEntranceWalkingIndex = 6;
const studentEntranceStudyHeaderIndex = 7;
const studentEntranceClassesIndex = 8;
const studentEntranceMoneyHeaderIndex = 9;
const studentEntranceAllowanceIndex = 10;
const studentEntranceInspirationHeaderIndex = 11;
const studentEntranceVerseIndex = 12;
const studentEntranceQuotesIndex = 13;
const studentEntranceCalendarIndex = 14;

/// Test keys for the entrance-only overlays.
const entrancePointsFloatKey = ValueKey('entrance-points-float');
const entranceConfettiKey = ValueKey('entrance-confetti');

/// 0..1 progress of stagger item [index] at [controllerValue]
/// (the entrance controller's 0..1 value), eased with a
/// spring-overshoot curve ([Curves.easeOutBack]) so the item
/// bounces slightly past its resting place. Overshoot is clamped
/// to 1 for opacity use — callers that need the raw overshoot for
/// scale should use the unclamped value via [entranceItemScale].
double entranceItemProgress(double controllerValue, int index) {
  final start =
      index * studentEntranceStagger.inMilliseconds /
          studentEntranceDuration.inMilliseconds;
  final end =
      (index * studentEntranceStagger.inMilliseconds +
              studentEntranceItemDuration.inMilliseconds) /
          studentEntranceDuration.inMilliseconds;
  final t = Interval(start, end.clamp(0.0, 1.0)).transform(
    controllerValue.clamp(0.0, 1.0),
  );
  return Curves.easeOutBack.transform(t).clamp(0.0, 1.0);
}

/// Raw (unclamped) spring progress of stagger item [index], for
/// scale transforms — values slightly above 1 are the overshoot
/// bounce. Never below 0.
double entranceItemScale(double controllerValue, int index) {
  final start =
      index * studentEntranceStagger.inMilliseconds /
          studentEntranceDuration.inMilliseconds;
  final end =
      (index * studentEntranceStagger.inMilliseconds +
              studentEntranceItemDuration.inMilliseconds) /
          studentEntranceDuration.inMilliseconds;
  final t = Interval(start, end.clamp(0.0, 1.0)).transform(
    controllerValue.clamp(0.0, 1.0),
  );
  return math.max(0.0, Curves.easeOutBack.transform(t));
}

/// The points count-up value at [progress] (0..1) toward the live
/// [target] balance: eased 0 -> target, never above the target.
int entranceCountUp(int target, double progress) =>
    (target * Curves.easeOut.transform(progress.clamp(0.0, 1.0))).round();

/// How many of the [totalChecked] day cells are ticked in at
/// [progress] (0..1): whole cells only, one by one, never more
/// than the real checked count.
int entranceCheckedCells(int totalChecked, double progress) =>
    (totalChecked * progress.clamp(0.0, 1.0)).floor();

/// Confetti burst over the streak badge: ~26 dots in emerald,
/// amber and gold that fly outward from the centre and fade out
/// as [progress] runs 0 -> 1. Deterministic (no Random) so widget
/// tests see the same burst every run. Pure decoration — pointer
/// events pass straight through.
class EntranceConfetti extends StatelessWidget {
  const EntranceConfetti({super.key, required this.progress});

  /// 0..1 burst progress. Below 0.05 or at/after 1 the burst is
  /// invisible (not yet fired / fully faded).
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress < 0.05 || progress >= 1.0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _ConfettiPainter(progress: progress),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress});

  final double progress;

  static const _colors = <Color>[
    Color(0xFFF59E0B), // amber — the streak flame
    Color(0xFF16A34A), // brand emerald
    Color(0xFF34D399), // bright accent
    Color(0xFFFBBF24), // gold
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.max(size.width, size.height) * 0.45;
    for (var i = 0; i < 26; i++) {
      // Golden-angle spread: every dot gets its own direction and
      // distance so the burst reads as a spray, not a ring.
      final angle = i * 2.39996;
      final distance = (0.35 + 0.65 * ((i * 37 % 10) / 10)) * maxRadius;
      final travelled = distance * Curves.easeOut.transform(progress);
      final offset = Offset(
        center.dx + math.cos(angle) * travelled,
        center.dy + math.sin(angle) * travelled + 18 * progress * progress,
      );
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(
          alpha: (1 - progress) * 0.95,
        );
      final radius = 2.0 + (i % 3);
      if (i % 3 == 0) {
        canvas.drawRect(
          Rect.fromCircle(center: offset, radius: radius),
          paint,
        );
      } else {
        canvas.drawCircle(offset, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
