// Account dashboard — ByaheTayo Flutter app (Account tab).
//
// HONEST STATE: this Flutter app has NO account backend yet (no Firebase
// auth, no profile, no points). So the header is a guest state (no
// invented name/email, no fake verification badge), the wallet is 0
// points (true — no points exist), and every action that needs a backend
// says so plainly in a SnackBar instead of faking success. What DOES
// really work: theme switching (wired to the whole app), and local
// notification/language preferences persisted with SharedPreferences.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shown for every action that needs the account backend (not ported yet).
const _notPortedMessage =
    'Hindi pa available — hindi pa naka-port ang account system sa Flutter app.';

/// Shown for Sign Out: there is nobody signed in to sign out.
const _signedOutMessage =
    'Walang naka-sign in — hindi pa naka-port ang account system sa Flutter app.';

const _prefsNotificationsKey = 'byahetayo_pref_notifications';
const _prefsLanguageKey = 'byahetayo_pref_language';

class AccountTab extends StatefulWidget {
  const AccountTab({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  bool _notifications = true;
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notifications = prefs.getBool(_prefsNotificationsKey) ?? true;
        _language = prefs.getString(_prefsLanguageKey) ?? 'English';
      });
    } catch (_) {
      // Preferences unavailable: keep the defaults. Never crash the tab
      // over a local setting.
    }
  }

  Future<void> _saveNotifications(bool value) async {
    setState(() => _notifications = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsNotificationsKey, value);
    } catch (_) {
      // Local save failed; the switch already reflects the choice.
    }
  }

  Future<void> _saveLanguage(String value) async {
    setState(() => _language = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLanguageKey, value);
    } catch (_) {
      // Local save failed; the selection already reflects the choice.
    }
  }

  void _showNotPorted() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(_notPortedMessage)));
  }

  void _showInfoDialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  Future<void> _pickTheme() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme Settings'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: widget.themeMode,
            onChanged: (value) {
              if (value != null) Navigator.of(context).pop(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    title: Text(_themeModeLabel(mode)),
                    value: mode,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) widget.onThemeModeChanged(selected);
  }

  Future<void> _pickLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Language Settings'),
        children: [
          RadioGroup<String>(
            groupValue: _language,
            onChanged: (value) {
              if (value != null) Navigator.of(context).pop(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final language in ['English', 'Filipino'])
                  RadioListTile<String>(title: Text(language), value: language),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              'Naka-save ang pinili mo. Hindi pa nito binabago ang wika ng app.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
    if (selected != null) await _saveLanguage(selected);
  }

  Future<void> _showTransactionHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transaction History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 12),
            Text('Wala pang transactions.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 600;
        final header = _headerCard(scheme);
        final wallet = _walletCard();
        final history = Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Transaction History'),
            subtitle: const Text('Wala pang transactions.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showTransactionHistory,
          ),
        );
        final info = _sectionCard(
          title: 'Account Information',
          tiles: [
            _infoTile(Icons.person_outline, 'Personal Information'),
            _infoTile(Icons.school_outlined, 'Student Information'),
            _infoTile(Icons.work_outlined, 'Employment Information'),
          ],
        );
        final preferences = _sectionCard(
          title: 'Preferences',
          tiles: [
            SwitchListTile(
              title: const Text('Notification Settings'),
              subtitle: const Text('Mga abiso mula sa app'),
              value: _notifications,
              onChanged: _saveNotifications,
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Theme Settings'),
              subtitle: Text(_themeModeLabel(widget.themeMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTheme,
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language Settings'),
              subtitle: Text(_language),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickLanguage,
            ),
          ],
        );
        final security = _sectionCard(
          title: 'Security & Privacy',
          tiles: [
            _actionTile(Icons.lock_outline, 'Change Password', _showNotPorted),
            _actionTile(
              Icons.verified_outlined,
              'Account Verification',
              _showNotPorted,
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Privacy Settings',
                'Ang Flutter app na ito ay walang account pa. Ang naka-save '
                    'lang dito sa device ay ang mga local setting mo: sidebar, '
                    'theme, notification at language. Walang profile, walang '
                    'points, at walang data na ipinapadala sa server mula sa '
                    'app na ito. Ang buong privacy policy ay kasama ng account '
                    'system pag na-port na ito.',
              ),
            ),
          ],
        );
        final actions = _sectionCard(
          title: 'Account Actions',
          tiles: [
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Help & Support',
                'ByaheTayo v1.0.0. Ang Flutter app ay nasa development pa. '
                    'Walang sign-in o support chat dito sa ngayon — ang account '
                    'system ay hindi pa naka-port. Ang gumaganang feature ngayon '
                    'ay ang Map at Fares tabs; ang Student at Friends tabs '
                    'ay may structure na pero walang backend pa.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About ByaheTayo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'About ByaheTayo',
                'ByaheTayo — Northern PH commute at jeepney companion. Trip '
                    'planner, LTFRB fare calculator, at student hub. '
                    'Version 1.0.0 (com.byahetayo.app).',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms and Conditions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Terms and Conditions',
                'Wala pang buong Terms and Conditions dito — kasama ito ng '
                    'account system pag na-port na. Walang pekeng legal text '
                    'dito.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Privacy Policy',
                'Ang Flutter app na ito ay walang account pa, kaya walang '
                    'profile o points data na naka-save. Ang naka-save lang dito '
                    'sa device ay ang mga local setting mo: sidebar, theme, '
                    'notification at language. Ang buong privacy policy ay '
                    'kasama ng account system pag na-port na ito.',
              ),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Sign Out', style: TextStyle(color: scheme.error)),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(_signedOutMessage)),
                );
              },
            ),
          ],
        );

        final sections = <Widget>[
          header,
          const SizedBox(height: 16),
          wallet,
          const SizedBox(height: 16),
          history,
          const SizedBox(height: 16),
          if (twoColumns) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                Expanded(child: preferences),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: security),
                const SizedBox(width: 16),
                Expanded(child: actions),
              ],
            ),
          ] else ...[
            info,
            const SizedBox(height: 16),
            preferences,
            const SizedBox(height: 16),
            security,
            const SizedBox(height: 16),
            actions,
          ],
        ];

        // Full width on purpose: no narrow centered container.
        return SingleChildScrollView(
          key: const Key('account-scroll-view'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections,
            ),
          ),
        );
      },
    );
  }

  Widget _headerCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.primary,
                  child: const Icon(
                    Icons.person,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guest',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Mag-sign in para makita ang profile mo.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Chip(label: Text('Guest account')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _showNotPorted,
              child: const Text('Edit Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text(
                  'Points Wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Spacer(),
                Icon(Icons.account_balance_wallet, color: Colors.white),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '0 points',
              key: ValueKey('points-balance'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Wala ka pang points. Kailangan ng account system para '
              'makaipon at makita ang history.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF16A34A),
              ),
              onPressed: _showNotPorted,
              child: const Text('Earn Points'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> tiles}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Divider(height: 8),
            ...tiles,
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showNotPorted,
    );
  }

  Widget _actionTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
