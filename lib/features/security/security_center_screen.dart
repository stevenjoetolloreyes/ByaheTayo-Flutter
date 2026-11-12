// Login Alerts + Session Manager — Security Center (Sessions).
//
// Account → Security. Lists the account's signed-in sessions from
// the Firestore `user_sessions` records (preview v1, screen 2):
// 'This device' with the green CURRENT badge, per-session
// last-active time, per-session 'Log out', and 'Log out all other
// devices'. A session disappears from another device when that
// device next comes online (its revocation watcher signs it out);
// until then it still shows here, because its record still exists.
//
// No sample data: an empty list honestly says only this device is
// signed in (or that no session record exists yet).
import 'package:flutter/material.dart';

import '../onboarding/auth_service.dart';
import 'login_history_screen.dart';
import 'security_theme.dart';
import 'session_models.dart';
import 'session_service.dart';

/// Account → Security → Sessions. [onBack] returns to the Account
/// tab (the screen is shown inside it, like Membership/About).
class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({
    super.key,
    required this.sessionService,
    required this.user,
    required this.authService,
    required this.onBack,
  });

  final SessionService sessionService;
  final AuthUser user;
  final AuthService authService;
  final VoidCallback onBack;

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  List<UserSession> _sessions = const [];
  bool _passwordChangeRequired = false;
  bool _loading = true;
  String? _error;
  bool _working = false;

  SessionService get _service => widget.sessionService;
  String? get _currentId => _service.currentSessionId;

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
      final sessions = await _service.loadSessions(widget.user.uid);
      final flag = await _service.isPasswordChangeRequired(widget.user.uid);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _passwordChangeRequired = flag;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not load your sessions. Check your connection '
            'and try again.';
        _loading = false;
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kSecurityDeepLeaves, width: 3),
        ),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: securityDangerButtonStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _logOutSession(UserSession session) async {
    final ok = await _confirm(
      'Log out this device?',
      '${session.deviceLabel} will be signed out of your account. '
          'It signs out when it next comes online.',
      'Log out',
    );
    if (!ok || !mounted) return;
    setState(() => _working = true);
    await _service.revokeSession(session);
    if (!mounted) return;
    setState(() => _working = false);
    _showSnack('Signed out ${session.deviceLabel}.');
    await _load();
  }

  Future<void> _logOutAllOthers() async {
    final others = _sessions.where((s) => s.id != _currentId).toList();
    if (others.isEmpty) return;
    final ok = await _confirm(
      'Log out all other devices?',
      'Every device except this one will be signed out of your '
          'account. Each signs out when it next comes online.',
      'Log out all',
    );
    if (!ok || !mounted) return;
    setState(() => _working = true);
    await _service.revokeAllOtherSessions(widget.user.uid);
    if (!mounted) return;
    setState(() => _working = false);
    _showSnack('All other devices signed out.');
    await _load();
  }

  Future<void> _sendPasswordReset() async {
    try {
      await widget.authService.sendPasswordReset(email: widget.user.email);
      if (!mounted) return;
      _showSnack('Password reset link sent. Check your email.');
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message);
    }
  }

  Future<void> _markPasswordChanged() async {
    await _service.clearPasswordChangeRequired(widget.user.uid);
    if (!mounted) return;
    setState(() => _passwordChangeRequired = false);
    _showSnack('Got it — password change marked as done.');
  }

  IconData _iconFor(UserSession session) {
    switch (session.platform) {
      case 'web':
        return Icons.language;
      case 'ios':
        return session.formFactor == 'tablet'
            ? Icons.tablet_mac
            : Icons.phone_iphone;
      case 'windows':
      case 'macos':
      case 'linux':
        return Icons.computer;
      default:
        return session.formFactor == 'tablet'
            ? Icons.tablet_android
            : Icons.smartphone;
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = _sessions.where((s) => s.id != _currentId).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
          tooltip: 'Back',
        ),
        title: const Text('Security Center'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const Text(
                    'Signed-in devices',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These are the devices signed in to your account. '
                    'Log out anything you don\'t recognize.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_passwordChangeRequired) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kSecurityGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kSecurityDirt, width: 3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber, color: kSecurityDirt),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Password change required',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'You asked to secure your account after a '
                            'sign-in you didn\'t recognize. Change your '
                            'password, then mark it done below.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                style: securityBlockButtonStyle(context),
                                onPressed: _sendPasswordReset,
                                child: const Text('Send reset link'),
                              ),
                              OutlinedButton(
                                style: securityDangerButtonStyle(context),
                                onPressed: _markPasswordChanged,
                                child: const Text('I\'ve changed it'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  else if (_sessions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: securityCardDecoration(context),
                      child: const Text(
                        'No sessions recorded yet. Your current sign-in '
                        'will appear here once its record is saved.',
                      ),
                    )
                  else
                    for (final session in _sessions)
                      _SessionCard(
                        session: session,
                        isCurrent: session.id == _currentId,
                        icon: _iconFor(session),
                        working: _working,
                        onLogOut: () => _logOutSession(session),
                      ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: securityDangerButtonStyle(context),
                      onPressed: others.isEmpty || _working
                          ? null
                          : _logOutAllOthers,
                      child: const Text('Log out all other devices'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: securityCardDecoration(context),
                    // The ListTile needs its own Material inside the
                    // decorated card, or its ink splash is hidden
                    // behind the card background (Flutter asserts).
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: kSecuritySky.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kSecuritySky, width: 2),
                          ),
                          child: const Icon(Icons.history, color: kSecuritySky),
                        ),
                        title: const Text(
                          'Login History',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'Every sign-in attempt on your account',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LoginHistoryScreen(
                                sessionService: _service,
                                user: widget.user,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sessions are recorded when you sign in on a '
                    'device. A device that never signed in through '
                    'this app has no record and can\'t appear here. '
                    'A signed-out device disappears when it next '
                    'comes online.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.isCurrent,
    required this.icon,
    required this.working,
    required this.onLogOut,
  });

  final UserSession session;
  final bool isCurrent;
  final IconData icon;
  final bool working;
  final VoidCallback onLogOut;

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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kSecurityGrass.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kSecurityDeepLeaves, width: 2),
                ),
                child: Icon(icon, color: kSecurityDeepLeaves),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.deviceLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          securityCurrentBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.detailLine,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (session.locationLabel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 6),
                Text(session.locationLabel!),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16),
              const SizedBox(width: 6),
              Text(session.lastActiveLabel()),
              if (session.trusted && !isCurrent) ...[
                const SizedBox(width: 12),
                const Icon(Icons.verified, size: 16, color: kSecurityGrass),
                const SizedBox(width: 4),
                const Text('Trusted'),
              ],
            ],
          ),
          if (!isCurrent) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: securityDangerButtonStyle(context),
                onPressed: working ? null : onLogOut,
                child: const Text('Log out'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
