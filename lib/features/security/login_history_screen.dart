// Login Alerts + Session Manager — Login History.
//
// Account → Security → Login History. Date-grouped sign-in
// attempts (preview v1, screen 3), newest first: successful
// sign-ins green, failed attempts red with the reason
// ('Failed sign-in — wrong password'). Each entry shows the device,
// time, and location when one was recorded.
//
// HONEST LIMIT (shown on the screen, not hidden): a failed attempt
// can only be linked to this account when the app knew the account
// — while signed in, or from this device and flushed after a later
// successful sign-in for the same email. A failed attempt from an
// unknown device that never signs in cannot be attributed to an
// account, so it never appears here.
import 'package:flutter/material.dart';

import '../onboarding/auth_service.dart';
import 'security_theme.dart';
import 'session_models.dart';
import 'session_service.dart';

class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({
    super.key,
    required this.sessionService,
    required this.user,
  });

  final SessionService sessionService;
  final AuthUser user;

  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  List<LoginAttempt> _attempts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final attempts =
          await widget.sessionService.loadAttempts(widget.user.uid);
      if (!mounted) return;
      setState(() {
        _attempts = attempts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your login history. Check your '
            'connection and try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupAttemptsByDay(_attempts);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login History'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const Text(
                    'Sign-in attempts',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every sign-in attempt on your account, newest first.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: securityCardDecoration(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 12),
                          FilledButton(
                            style: securityBlockButtonStyle(context),
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  else if (_attempts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: securityCardDecoration(context),
                      child: const Text(
                        'No sign-in attempts recorded yet. Your next '
                        'sign-in will appear here.',
                      ),
                    )
                  else
                    for (final group in groups) ...[
                      _DayHeader(day: group.day),
                      const SizedBox(height: 8),
                      for (final attempt in group.attempts)
                        _AttemptCard(attempt: attempt),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kSecurityGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kSecurityDirt, width: 3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'See a failed sign-in you don\'t recognize? '
                          'Change your password and log out all other '
                          'devices in the Security Center.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Failed attempts from a device that never '
                          'signed in can\'t be linked to this account, '
                          'so they don\'t appear here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: securityBlockButtonStyle(context),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Open Security Center'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final header = dayGroupHeader(day);
    return Row(
      children: [
        Text(
          header.label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          header.sublabel,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({required this.attempt});

  final LoginAttempt attempt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: securityCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  attempt.titleLine,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              securityStatusPill(attempt.success),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            attempt.platform == 'web'
                ? 'Web browser'
                : '${attempt.deviceLabel} · EstudyanteGO app',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (attempt.locationLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 6),
                Text(attempt.locationLabel!),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            formatTimeOfDay(attempt.createdAt),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
