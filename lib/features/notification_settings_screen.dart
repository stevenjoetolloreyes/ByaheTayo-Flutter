// Notification Settings screen — EstudyanteGO Flutter app.
//
// Shown INSIDE the Account tab (the shell's bottom navigation /
// sidebar stays visible) and returned to via [onBack], the same
// pattern as the About and Subscription Membership screens.
//
// This REPLACES the old Notification Settings behaviour (a row that
// only showed the OS permission status and opened a permission
// dialog). The old page's four pre-checked toggles existed only in
// the Gemini preview HTML — the real app never had them — so this
// screen creates ten REAL local toggles, each wired to a
// [NotificationPreferences] field and to the local schedule:
//
// * Class reminders — 30 minutes before each class starts, with
//   the bus fare and trip time.
// * Quiz / exam reminders — 8:00 PM the night before an exam.
// * Assignment reminders — 8:00 AM the day before an assignment
//   is due.
// * Allowance / budget alerts — 8:00 AM while the allowance is
//   used up or a monthly budget is over.
// * 7-Day sign-in streak — 7:15 AM when the streak would break.
// * Bible Verse / Daily Quote morning — 7:00 AM.
// * School reminders — 8:00 AM the day before a school event or
//   holiday.
// * Daily login reminder — once a day, at a time the user picks
//   (default 8:00 AM).
// * Chat Support replies + App Reviews replies — announced when
//   the app opens and finds an unread admin reply (no push server,
//   so they cannot arrive while the app is closed).
//
// Every change saves the preference immediately and re-runs the
// schedule refresh on [notificationService]. Friend requests,
// community likes/comments and announcements are NOT here: they
// need the Full push system (FCM + Cloud Functions), which is not
// approved and not built — the footer says so plainly.
import 'package:flutter/material.dart';
import 'minecraft_theme.dart';
import 'top_popup.dart';

import 'ios_components.dart';
import 'local_notifications.dart';
import 'onboarding/permission_service.dart';

/// Notification Settings screen.
///
/// [permissionService] is the same service the app shell uses;
/// [notificationService] is the app shell's local notification
/// service (already initialized).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.permissionService,
    required this.notificationService,
    required this.onBack,
  });

  final PermissionService permissionService;
  final LocalNotificationService notificationService;

  /// Return to the Account page content.
  final VoidCallback onBack;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationPreferencesStore _store = NotificationPreferencesStore();

  NotificationPreferences? _prefs;
  NotificationPermissionStatus _status = NotificationPermissionStatus.unknown;
  bool _exactAlarms = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _store.load();
    final status = await widget.permissionService.notificationStatus();
    final exact = await widget.notificationService.canScheduleExact;
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _status = status;
      _exactAlarms = exact;
    });
  }

  Future<void> _loadStatus() async {
    final status = await widget.permissionService.notificationStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _updatePrefs(NotificationPreferences next) async {
    setState(() => _prefs = next);
    await _store.save(next);
    await widget.notificationService.refreshAll();
  }

  void _showSnack(String message) {
    TopPopup.show(context, message: message);
  }

  Future<void> _onPermissionButton() async {
    switch (_status) {
      case NotificationPermissionStatus.granted:
        showIosMessage(
          context: context,
          title: 'Notifications allowed',
          message: 'Notifications are allowed for EstudyanteGO. To turn '
              'them off, use your device settings.',
        );
        return;
      case NotificationPermissionStatus.permanentlyDenied:
        await widget.permissionService.openAppSettings();
        await _loadStatus();
        return;
      case NotificationPermissionStatus.denied:
      case NotificationPermissionStatus.unknown:
        final allow = await showIosAlert<bool>(
          context: context,
          title: 'Allow notifications?',
          message: 'EstudyanteGO can send you reminders about your '
              'classes, exams, allowance, sign-in streak and verse, '
              'and tell you when Steven replies. '
              'You can change this anytime in your device settings.',
          actions: const [
            IosAlertAction<bool>('Not now', value: false),
            IosAlertAction<bool>('Allow', value: true, isDefault: true),
          ],
        );
        if (allow == true) {
          final status = await widget.permissionService.requestNotification();
          if (!mounted) return;
          setState(() => _status = status);
          if (status == NotificationPermissionStatus.granted) {
            await widget.notificationService.refreshAll();
          }
        }
        return;
    }
  }

  Future<void> _pickDailyTime() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: prefs.dailyLoginTime,
    );
    if (picked == null) return;
    await _updatePrefs(prefs.copyWith(dailyLoginTime: picked));
  }

  Future<void> _onExactAlarms() async {
    await widget.notificationService.requestExactAlarms();
    final exact = await widget.notificationService.canScheduleExact;
    if (!mounted) return;
    setState(() => _exactAlarms = exact);
  }

  Future<void> _onSendTest() async {
    if (_status != NotificationPermissionStatus.granted) {
      _showSnack('Allow notifications first.');
      return;
    }
    final sent = await widget.notificationService.sendTestNotification();
    if (!mounted) return;
    if (!sent) {
      _showSnack("Couldn't send the test notification.");
    }
  }

  String _statusLabel() {
    switch (_status) {
      case NotificationPermissionStatus.granted:
        return 'Allowed';
      case NotificationPermissionStatus.denied:
        return 'Not allowed';
      case NotificationPermissionStatus.permanentlyDenied:
        return 'Blocked — open system settings';
      case NotificationPermissionStatus.unknown:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final permissionGranted = _status == NotificationPermissionStatus.granted;

    return SingleChildScrollView(
      key: const Key('notification-settings-scroll-view'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back to Account',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Text(
              'Notification Settings',
              style: MinecraftText.heading(color: onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Reminders are scheduled on this device only — no account '
              'or server is involved.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                  ),
            ),
            const SizedBox(height: 20),
            _sectionCard(
              context,
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(
                    Icons.notifications_outlined,
                    color: scheme.primary,
                  ),
                  title: const Text('Notifications'),
                  subtitle: Text(_statusLabel()),
                  trailing: FilledButton(
                    key: const Key('notification-permission-button'),
                    style: minecraftBlockButtonStyle(),
                    onPressed: _onPermissionButton,
                    child: Text(
                      permissionGranted
                          ? 'Allowed'
                          : _status ==
                                  NotificationPermissionStatus
                                      .permanentlyDenied
                              ? 'Open settings'
                              : 'Allow',
                    ),
                  ),
                ),
                if (!permissionGranted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Notifications are not allowed yet — reminders '
                      'will not arrive until you allow them above.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'REMINDERS',
              style: MinecraftText.pixel(color: muted, fontSize: 9),
            ),
            const SizedBox(height: 8),
            _sectionCard(
              context,
              children: [
                IosSwitchRow(
                  key: const Key('class-reminders-toggle'),
                  title: const Text('Class reminders'),
                  subtitle: const Text(
                      '30 minutes before each class starts, with your '
                      'bus fare and trip time.'),
                  value: prefs?.classReminders ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(classReminders: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('quiz-exam-reminders-toggle'),
                  title: const Text('Quiz / exam reminders'),
                  subtitle: const Text(
                      '8:00 PM the night before an exam.'),
                  value: prefs?.quizReminders ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(quizReminders: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('assignment-reminders-toggle'),
                  title: const Text('Assignment reminders'),
                  subtitle: const Text(
                      '8:00 AM the day before an assignment is due.'),
                  value: prefs?.assignmentReminders ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(
                        current.copyWith(assignmentReminders: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('allowance-alerts-toggle'),
                  title: const Text('Allowance / budget alerts'),
                  subtitle: const Text(
                      '8:00 AM when your allowance runs out or a '
                      'monthly budget goes over.'),
                  value: prefs?.allowanceAlerts ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(
                        current.copyWith(allowanceAlerts: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('streak-reminder-toggle'),
                  title: const Text('7-Day sign-in streak'),
                  subtitle: const Text(
                      '7:15 AM when your streak is about to break.'),
                  value: prefs?.streakReminder ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(streakReminder: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('verse-morning-toggle'),
                  title: const Text('Bible Verse / Daily Quote morning'),
                  subtitle: const Text(
                      "Today's verse or quote at 7:00 AM."),
                  value: prefs?.verseMorning ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(verseMorning: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('school-reminders-toggle'),
                  title: const Text('School reminders'),
                  subtitle: const Text(
                      '8:00 AM the day before a school event or '
                      'holiday.'),
                  value: prefs?.schoolReminders ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(schoolReminders: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('daily-login-toggle'),
                  title: const Text('Daily login reminder'),
                  subtitle: const Text(
                      "Once a day, so you don't miss sign-in points."),
                  value: prefs?.dailyLoginReminder ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(
                        current.copyWith(dailyLoginReminder: value));
                  },
                ),
                if (prefs != null && prefs.dailyLoginReminder) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    key: const Key('daily-login-time-row'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('Daily login time'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          prefs.dailyLoginTime.format(context),
                          key: const Key('daily-login-time-value'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: muted),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                      ],
                    ),
                    onTap: _pickDailyTime,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'REPLIES',
              style: MinecraftText.pixel(color: muted, fontSize: 9),
            ),
            const SizedBox(height: 8),
            _sectionCard(
              context,
              children: [
                IosSwitchRow(
                  key: const Key('chat-replies-toggle'),
                  title: const Text('Chat Support replies'),
                  subtitle: const Text(
                      'When Steven replies in Chat Support.'),
                  value: prefs?.chatReplies ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(chatReplies: value));
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                IosSwitchRow(
                  key: const Key('review-replies-toggle'),
                  title: const Text('App Reviews replies'),
                  subtitle: const Text(
                      'When EstudyanteGO replies to your review.'),
                  value: prefs?.reviewReplies ?? true,
                  onChanged: (value) {
                    final current = _prefs;
                    if (current == null) return;
                    _updatePrefs(current.copyWith(reviewReplies: value));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Replies are checked when you open the app — they '
              'cannot arrive while the app is closed until the full '
              'push system is built.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                  ),
            ),
            if (!_exactAlarms) ...[
              const SizedBox(height: 20),
              _sectionCard(
                context,
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.alarm_off_outlined,
                      color: scheme.error,
                    ),
                    title: const Text('Exact alarms are off'),
                    subtitle: const Text(
                        'Reminders may arrive a few minutes late.'),
                    trailing: OutlinedButton(
                      key: const Key('allow-exact-alarms-button'),
                      style: minecraftOutlinedButtonStyle(),
                      onPressed: _onExactAlarms,
                      child: const Text('Allow'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const Key('send-test-notification-button'),
              style: minecraftOutlinedButtonStyle(),
              onPressed: _onSendTest,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Send test notification'),
            ),
            const SizedBox(height: 20),
            Text(
              'Friend requests, community likes and comments, and '
              'announcements need the full push system — not built '
              'yet. Reminders here are scheduled on this device only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tapping a class, exam or assignment reminder opens '
              'Schedule; an allowance alert opens Money; the morning '
              'verse opens the Bible screen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context,
      {required List<Widget> children}) {
    return MinecraftCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
