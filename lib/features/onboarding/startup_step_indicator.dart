// Startup progress indicator for the 9-step first-time flow:
//
//   1 Splash, 2–5 Onboarding, 6 Create Account, 7 Sign In,
//   8 Profile Setup, 9 Student tab.
//
// Renders [totalSteps] dots (past steps filled, the current step an
// expanded pill, later steps muted) plus a "Step N of 9" label.
// Colors are passed in so entry screens (EntryColors) and app-theme
// screens (ColorScheme, e.g. Profile Setup) can both use it.
//
// The splash (step 1) and the Student tab (step 9) show no
// indicator: the splash is a timed intro animation and the Student
// tab is the destination, not a startup step. The indicator appears
// on steps 2–8 only, always labeled against the full 9-step flow.
import 'package:flutter/material.dart';

import '../app_layout.dart';

class StartupStepIndicator extends StatelessWidget {
  const StartupStepIndicator({
    super.key,
    required this.step,
    this.totalSteps = 9,
    required this.activeColor,
    required this.inactiveColor,
    required this.labelColor,
  }) : assert(step >= 1 && step <= totalSteps);

  /// 1-based step within the 9-step startup flow.
  final int step;

  final int totalSteps;
  final Color activeColor;
  final Color inactiveColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('startup-step-indicator'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 1; i <= totalSteps; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == step ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i <= step
                      ? activeColor
                      : inactiveColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Step $step of $totalSteps',
          style: AppText.captionSemiBold.copyWith(color: labelColor),
        ),
      ],
    );
  }
}
