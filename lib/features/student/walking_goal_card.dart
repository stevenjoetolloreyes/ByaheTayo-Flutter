// Walking Goal hub card — full-width, visually matching the 7-Day
// Sign-in card (icon tile header, progress bar, stats row).
//
// Every color comes from the ambient theme (hub light theme or the
// dark-aware hub theme); nothing here hardcodes a light palette, so
// the card reads correctly in both modes. All numbers are real
// recorded steps or honest empty states — never fabricated counts.
import 'package:flutter/material.dart';

import '../app_layout.dart';
import 'student_theme.dart';
import 'walking_repository.dart';

/// Full-width Walking Goal card for the Student Hub.
///
/// [controller] is the hub tab's shared controller (also used by the
/// details screen, so both always agree). [onOpen] pushes the
/// details screen; it is only wired when the card has live data.
class WalkingGoalCard extends StatelessWidget {
  const WalkingGoalCard({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final WalkingController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('walking-hub-card'),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final ready = controller.status == WalkingStatus.ready;
          return InkWell(
            onTap: ready ? onOpen : null,
            borderRadius:
                BorderRadius.circular(kStudentCardRadius),
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
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.directions_walk_rounded,
                          color: scheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Walking Goal',
                                style: kStudentCardHeading),
                            Text(
                              'Stay active and reach your weekly goal!',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      if (ready) const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: AppLayout.cardGap),
                  _body(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (controller.status) {
      case WalkingStatus.loading:
        // The label flexes: on narrow phones the fixed-width row
        // used to overflow (11px in a 318px card) and fail tests.
        return const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('Loading walking data…')),
          ],
        );
      case WalkingStatus.noSensor:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Step counting isn\'t available on this device.',
                style: AppText.body),
            SizedBox(height: 4),
            Text(
              'This device has no step-counter sensor, and Health '
              'Connect isn\'t available either, so no steps can be '
              'recorded.',
              style: AppText.caption,
            ),
          ],
        );
      case WalkingStatus.healthConnectRequired:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your phone has no step-counter sensor, so the app '
              'can read your steps from Health Connect instead.',
              style: AppText.body,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: controller.requestHealthConnectPermission,
                  child: const Text('Connect Health Connect'),
                ),
                TextButton(
                  onPressed: controller.recheckHealthConnect,
                  child: const Text('Check again'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Steps come from apps like Google Fit via Health '
              'Connect.',
              style: AppText.caption,
            ),
          ],
        );
      case WalkingStatus.permissionRequired:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step counting needs activity permission to read '
              'your steps.',
              style: AppText.body,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: controller.requestPermission,
              child: const Text('Allow activity tracking'),
            ),
          ],
        );
      case WalkingStatus.permissionDenied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activity permission was denied. Enable it in app '
              'settings to count steps.',
              style: AppText.body,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: controller.openSettings,
                  child: const Text('Open settings'),
                ),
                TextButton(
                  onPressed: controller.recheckPermission,
                  child: const Text('Check again'),
                ),
              ],
            ),
          ],
        );
      case WalkingStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Couldn\'t load walking data.',
                style: AppText.body),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: controller.retry,
              child: const Text('Retry'),
            ),
          ],
        );
      case WalkingStatus.ready:
        return _readyBody(context);
    }
  }

  Widget _readyBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = controller.todaySteps;
    final goal = controller.goal;
    final progress = controller.todayProgress;
    final week = controller.weeklyHistory;
    final maxWeek = week.fold<int>(
        0, (max, e) => (e.steps ?? 0) > max ? (e.steps ?? 0) : max);
    const dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                _formatNumber(steps),
                style: kStudentPageTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 3),
              child: Text('Steps', style: AppText.caption),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                '${_formatNumber(steps)} / ${_formatNumber(goal)} steps',
                style: AppText.captionSemiBold,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            color: scheme.primary,
            backgroundColor: scheme.primary.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final entry in week)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 36,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 10,
                          height: entry.steps == null
                              ? 4
                              : maxWeek == 0
                                  ? 4
                                  : (36 * entry.steps! / maxWeek)
                                      .clamp(4.0, 36.0),
                          decoration: BoxDecoration(
                            color: entry.steps == null
                                ? scheme.outline
                                : entry.dateKey == controller.todayKey
                                    ? scheme.primary
                                    : scheme.primary
                                        .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayLabels[_weekdayOf(entry.dateKey) - 1],
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _stat(
                context,
                Icons.directions_walk_rounded,
                _formatNumber(steps),
                'Steps',
              ),
            ),
            Expanded(
              child: _stat(
                context,
                Icons.location_on_rounded,
                '${controller.todayDistanceKm.toStringAsFixed(1)} km',
                'Distance',
              ),
            ),
            Expanded(
              child: _stat(
                context,
                Icons.local_fire_department_rounded,
                '${controller.todayCalories.toStringAsFixed(0)} kcal',
                'Calories',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Distance and calories are estimates.',
          style: AppText.caption,
        ),
        // Health Connect is a snapshot source, not a live stream:
        // the count is from the last read, and Refresh re-reads it.
        if (controller.isHealthConnect)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Steps from Health Connect'
                    '${controller.lastHealthConnectReadLabel.isEmpty ? '' : ' · ${controller.lastHealthConnectReadLabel}'}',
                    style: AppText.caption,
                  ),
                ),
                TextButton(
                  onPressed: controller.refreshSteps,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        if (!controller.receivedEvent)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Waiting for your first steps…',
              style: AppText.caption,
            ),
          ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: scheme.primary, size: 20),
        const SizedBox(height: 4),
        Text(value, style: AppText.captionSemiBold),
        Text(label, style: AppText.caption),
      ],
    );
  }

  static int _weekdayOf(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return 1;
    final date = DateTime(
      int.tryParse(parts[0]) ?? 2000,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
    return date.weekday;
  }

  static String _formatNumber(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }
}
