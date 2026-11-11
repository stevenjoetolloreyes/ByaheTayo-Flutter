// Walking Goal details screen.
//
// Opened from the hub card wrapped in StudentHubTheme (dark-aware),
// so every color here comes from the ambient theme and the screen
// renders correctly in both Light and Dark modes. No color in this
// file is hardcoded to a light palette.
//
// The numbers are the shared WalkingController's real recorded
// steps; distance, duration, and calories are estimates and are
// labeled as such. The background-tracking limit is stated in the
// info note at the bottom, not hidden.
import 'package:flutter/material.dart';

import '../app_layout.dart';
import '../minecraft_theme.dart';
import 'walking_repository.dart';

class WalkingGoalScreen extends StatelessWidget {
  const WalkingGoalScreen({super.key, required this.controller});

  final WalkingController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walking Goal')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          switch (controller.status) {
            case WalkingStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case WalkingStatus.noSensor:
              return const _Message(
                title: 'Step counting isn\'t available',
                body: 'This device has no step-counter sensor, and '
                    'Health Connect isn\'t available either, so no '
                    'steps can be recorded.',
              );
            case WalkingStatus.healthConnectRequired:
              return _Message(
                title: 'Connect Health Connect',
                body: 'Your phone has no step-counter sensor, so the '
                    'app can read your steps from Health Connect '
                    'instead. Steps come from apps like Google Fit.',
                actionLabel: 'Connect Health Connect',
                onAction: controller.requestHealthConnectPermission,
                secondLabel: 'Check again',
                onSecond: controller.recheckHealthConnect,
              );
            case WalkingStatus.permissionRequired:
              return _Message(
                title: 'Activity permission needed',
                body: 'Allow activity tracking so the app can read '
                    'your steps.',
                actionLabel: 'Allow activity tracking',
                onAction: controller.requestPermission,
              );
            case WalkingStatus.permissionDenied:
              return _Message(
                title: 'Activity permission denied',
                body: 'Enable activity tracking in app settings to '
                    'count steps.',
                actionLabel: 'Open settings',
                onAction: controller.openSettings,
                secondLabel: 'Check again',
                onSecond: controller.recheckPermission,
              );
            case WalkingStatus.error:
              return _Message(
                title: 'Couldn\'t load walking data',
                body: 'Something went wrong while loading your '
                    'walking records.',
                actionLabel: 'Retry',
                onAction: controller.retry,
              );
            case WalkingStatus.ready:
              return _ReadyBody(controller: controller);
          }
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondLabel,
    this.onSecond,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondLabel;
  final VoidCallback? onSecond;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppLayout.pagePaddingTab,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: MinecraftText.heading(), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body,
              style: MinecraftText.body(), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: minecraftBlockButtonStyle(),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
          if (secondLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onSecond, child: Text(secondLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.controller});

  final WalkingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = controller.todaySteps;
    final goal = controller.goal;
    final progress = controller.todayProgress;
    final week = controller.weeklyHistory;
    final maxWeek = week.fold<int>(
        0, (max, e) => (e.steps ?? 0) > max ? (e.steps ?? 0) : max);
    return ListView(
      padding: AppLayout.pagePaddingTab,
      children: [
        MinecraftCard(
          padding: AppLayout.cardPadding,
          child: Column(
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 16,
                          color: scheme.primary,
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatNumber(steps),
                            style: MinecraftText.heading(
                              color: MinecraftColors.emerald,
                              fontSize: 32,
                            ),
                          ),
                          const Text('steps', style: AppText.caption),
                          const SizedBox(height: 4),
                          Text(
                            'of ${_formatNumber(goal)} goal',
                            style: AppText.captionSemiBold,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Daily Step Goal',
                          style: AppText.sectionTitle),
                    ),
                    Text('${_formatNumber(goal)} steps',
                        style: AppText.captionSemiBold),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _editGoal(context),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
              ],
            ),
        ),
        const SizedBox(height: AppLayout.cardGap),
        MinecraftCard(
          padding: AppLayout.cardPadding,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MinecraftSectionHeader(
                  icon: Icons.today_rounded,
                  title: 'Today',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detailStat(
                        Icons.directions_walk_rounded,
                        _formatNumber(steps),
                        'Current Steps',
                      ),
                    ),
                    Expanded(
                      child: _detailStat(
                        Icons.location_on_rounded,
                        '${controller.todayDistanceKm.toStringAsFixed(1)} km',
                        'Distance (est.)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detailStat(
                        Icons.schedule_rounded,
                        '${controller.todayDurationMin} min',
                        'Duration (est.)',
                      ),
                    ),
                    Expanded(
                      child: _detailStat(
                        Icons.local_fire_department_rounded,
                        '${controller.todayCalories.toStringAsFixed(0)} kcal',
                        'Calories (est.)',
                      ),
                    ),
                  ],
                ),
                if (!controller.receivedEvent) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Waiting for your first steps…',
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
        ),
        const SizedBox(height: AppLayout.cardGap),
        MinecraftCard(
          padding: AppLayout.cardPadding,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Weekly Walking History',
                          style: AppText.sectionTitle),
                    ),
                    Text(
                      '${_formatNumber(controller.weeklyTotal)} steps',
                      style: AppText.captionSemiBold,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final entry in week) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            _dayLabel(entry.dateKey),
                            style: AppText.captionSemiBold,
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: entry.steps == null || maxWeek == 0
                                  ? 0
                                  : entry.steps! / maxWeek,
                              minHeight: 12,
                              color: entry.dateKey == controller.todayKey
                                  ? scheme.primary
                                  : scheme.primary
                                      .withValues(alpha: 0.55),
                              backgroundColor:
                                  scheme.primary.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: Text(
                            entry.steps == null
                                ? 'No data'
                                : '${_formatNumber(entry.steps!)} steps',
                            style: AppText.caption,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                const Text(
                  'Days the app was never opened show as no data, '
                  'never as zero steps.',
                  style: AppText.caption,
                ),
              ],
            ),
        ),
        const SizedBox(height: AppLayout.cardGap),
        // Health Connect is a snapshot source, not a live stream:
        // the count is from the last read, and Refresh re-reads it.
        // The sensor note below it does not apply in this mode.
        if (controller.isHealthConnect) ...[
          Row(
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
          const SizedBox(height: 4),
          const Text(
            'Steps come from Health Connect (recorded by apps like '
            'Google Fit), even while this app is closed. Distance, '
            'duration, and calories are estimates.',
            style: AppText.caption,
          ),
        ] else
          const Text(
            'Steps count while the app is open. Steps walked while '
            'the app is closed are picked up when you reopen it on '
            'the same day; steps from before a reboot or across '
            'midnight while closed land on the reopen day. Distance, '
            'duration, and calories are estimates.',
            style: AppText.caption,
          ),
      ],
    );
  }

  Widget _detailStat(IconData icon, String value, String label) {
    return Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          children: [
            Icon(icon, color: scheme.primary, size: 22),
            const SizedBox(height: 4),
            Text(value, style: AppText.titleStrong),
            Text(label, style: AppText.caption),
          ],
        );
      },
    );
  }

  Future<void> _editGoal(BuildContext context) async {
    final input = TextEditingController(text: controller.goal.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily Step Goal'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Steps per day',
            helperText: 'Between 1,000 and 100,000 steps.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: minecraftBlockButtonStyle(),
            onPressed: () {
              final parsed = int.tryParse(input.text.trim());
              Navigator.pop(context, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await controller.setGoal(result);
    }
  }

  static String _dayLabel(String dateKey) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    final date = DateTime(
      int.tryParse(parts[0]) ?? 2000,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
    return labels[date.weekday - 1];
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
