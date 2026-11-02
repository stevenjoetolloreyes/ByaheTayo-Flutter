// Premium Account page — EstudyanteGO Flutter app (Account tab).
//
// Premium Travel App + Material 3 + minimalist card UI. No guest
// accounts anywhere: the header shows the authenticated Firebase
// user (photo or honest initials, never a fake photo), and the
// Verified badge reflects the REAL Firebase emailVerified flag.
//
// Preserved from the previous dashboard: Points Wallet (existing
// account balance), Transaction History, Account Information,
// Preferences, and Security & Privacy. What changed: every action is
// real now — profile editing, password reset, email verification,
// notification permission status, theme switching, and sign-out all
// do what they say. There is no account deletion (omitted: it needs
// Firebase re-authentication to be safe).
import 'dart:io';

import 'package:flutter/material.dart';

import 'admin_access.dart';
import 'app_layout.dart';
import 'credits_repository.dart';
import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'onboarding/permission_service.dart';
import 'points_wallet_repository.dart';
import 'rewards_screen.dart';
import 'student_id_card.dart';
import 'subscription_membership.dart';

class AccountTab extends StatefulWidget {
  const AccountTab({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.authService,
    required this.user,
    this.profile,
    required this.permissionService,
    this.walletController,
    this.creditsController,
    this.onViewStudent,
    this.onViewCommunities,
    this.onEditProfile,
    this.onSignInRequested,
    required this.onSignedOut,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// Auth backend (Firebase implementation in production, fake in
  /// tests). Never null: when Firebase is not configured the service
  /// reports isConfigured == false and [user] is null.
  final AuthService authService;

  /// The authenticated Firebase user, or null when signed out or when
  /// Firebase is not configured. The header never shows a guest
  /// identity in either case.
  final AuthUser? user;

  /// On-device profile for [user], or null when none was set up yet.
  final UserProfile? profile;

  final PermissionService permissionService;

  /// Shared wallet state (null in bare widget tests). When it has a
  /// real backend, the wallet card and transaction history show live
  /// ledger data; otherwise the legacy 0-balance display is kept.
  final PointsWalletController? walletController;

  /// Shared credits state (null in bare widget tests). When it has
  /// a real backend, the wallet card shows the live credits
  /// balance; otherwise the credits row is hidden.
  final CreditsController? creditsController;

  /// Jump to the Student tab (7-Day Sign-in, the real earn path).
  final VoidCallback? onViewStudent;

  /// Jump to the Communities tab (where admin actions live).
  final VoidCallback? onViewCommunities;

  /// Open profile setup in edit mode.
  final VoidCallback? onEditProfile;

  /// Open the sign-in screen (signed-out state only).
  final VoidCallback? onSignInRequested;

  /// Called after a successful sign-out so the app gate can show
  /// sign-in.
  final VoidCallback onSignedOut;

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  NotificationPermissionStatus _notificationStatus =
      NotificationPermissionStatus.unknown;

  /// Membership screen shown INSIDE the Account tab (the shell's
  /// bottom navigation / sidebar stays visible). The Account page
  /// itself is unchanged; only this flag swaps its content.
  bool _showingMembership = false;

  AuthUser? get _user => widget.user;
  UserProfile? get _profile => widget.profile;
  bool get _signedIn => _user != null;
  bool get _isAdmin => isAdminUser(_user);

  /// Remote mode: the wallet controller has a real backend.
  bool get _walletRemote => widget.walletController?.remote ?? false;

  /// Live balance in remote mode, 0 in legacy mode.
  int get _balance => widget.walletController?.balance ?? 0;

  /// Live total earned in remote mode, 0 in legacy mode.
  int get _totalEarned => widget.walletController?.totalEarned ?? 0;

  /// Live ledger entries in remote mode, empty in legacy mode.
  List<PointsTransaction> get _entries =>
      _walletRemote ? widget.walletController!.entries : const [];

  /// Credits remote mode: the credits controller has a real backend.
  bool get _creditsRemote => widget.creditsController?.remote ?? false;

  /// Live credits balance in minor units in remote mode, 0 otherwise.
  int get _creditsBalanceUnits =>
      widget.creditsController?.balanceUnits ?? 0;

  @override
  void initState() {
    super.initState();
    widget.walletController?.addListener(_onWalletChanged);
    widget.creditsController?.addListener(_onWalletChanged);
    _loadNotificationStatus();
    _loadWallet();
    _loadCredits();
  }

  @override
  void didUpdateWidget(AccountTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walletController != widget.walletController) {
      oldWidget.walletController?.removeListener(_onWalletChanged);
      widget.walletController?.addListener(_onWalletChanged);
    }
    if (oldWidget.creditsController != widget.creditsController) {
      oldWidget.creditsController?.removeListener(_onWalletChanged);
      widget.creditsController?.addListener(_onWalletChanged);
    }
    if (oldWidget.user?.uid != widget.user?.uid) {
      _loadWallet();
      _loadCredits();
    }
  }

  @override
  void dispose() {
    widget.walletController?.removeListener(_onWalletChanged);
    widget.creditsController?.removeListener(_onWalletChanged);
    super.dispose();
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  void _loadWallet() {
    final uid = _user?.uid;
    final controller = widget.walletController;
    if (uid != null && controller != null) {
      controller.loadForUser(uid);
    }
  }

  void _loadCredits() {
    final uid = _user?.uid;
    final controller = widget.creditsController;
    if (uid != null && controller != null) {
      controller.loadForUser(uid);
    }
  }

  Future<void> _loadNotificationStatus() async {
    final status = await widget.permissionService.notificationStatus();
    if (!mounted) return;
    setState(() => _notificationStatus = status);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _showTransactionHistory() async {
    final entries = _entries;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: AppLayout.pagePaddingLarge,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transaction History',
                style: AppText.heading,
              ),
              const SizedBox(height: AppLayout.cardGap),
              if (entries.isEmpty)
                const Text('No transactions yet.')
              else
                for (final entry in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.description),
                    subtitle: Text(entry.date),
                    trailing: Text(
                      '+${entry.points} pts',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// Actions that need an account route to sign-in when signed out.
  void _requireAccount(VoidCallback action) {
    if (!_signedIn) {
      widget.onSignInRequested?.call();
      return;
    }
    action();
  }

  void _openProfile() => _requireAccount(() => widget.onEditProfile?.call());

  void _openStudentId() {
    _requireAccount(() {
      final profile = _profile;
      if (profile == null) {
        widget.onEditProfile?.call();
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StudentIdCardScreen(
            profile: profile,
            onEditProfile: () {
              Navigator.of(context).pop();
              widget.onEditProfile?.call();
            },
          ),
        ),
      );
    });
  }

  void _openRewards() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RewardsScreen(
          pointsBalance: _balance,
          onOpenStudentHub: () {
            Navigator.of(context).pop();
            widget.onViewStudent?.call();
          },
          creditsBalanceUnits: _creditsBalanceUnits,
          creditsTotalEarnedUnits:
              widget.creditsController?.totalEarnedUnits ?? 0,
          creditsTotalSpentUnits:
              widget.creditsController?.totalSpentUnits ?? 0,
          creditsEntries: widget.creditsController?.entries ?? const [],
          adRewardEntries:
              widget.creditsController?.adRewards ?? const [],
          scanFreeRemaining:
              widget.creditsController?.scanCounter.freeRemaining ??
                  freeScansPerDay,
          dailyAdLimit:
              widget.creditsController?.settings.dailyAdLimit ?? 5,
          onRedeem: _redeemCallback(),
        ),
      ),
    );
  }

  /// Redeem-all for the Rewards screen opened from the Account tab:
  /// after a successful redemption the points controller reloads
  /// so the wallet card drops by the redeemed amount immediately.
  Future<RedeemOutcome> Function()? _redeemCallback() {
    final credits = widget.creditsController;
    final points = widget.walletController;
    final uid = _user?.uid;
    if (credits == null || !credits.remote || uid == null) return null;
    return () async {
      final outcome = await credits.redeemAll();
      if (outcome.status == RedeemStatus.redeemed) {
        await points?.loadForUser(uid);
      }
      return outcome;
    };
  }

  String _notificationStatusLabel() {
    switch (_notificationStatus) {
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

  Future<void> _handleNotificationSettings() async {
    switch (_notificationStatus) {
      case NotificationPermissionStatus.granted:
        _showInfoDialog(
          'Notifications allowed',
          'Notifications are allowed for EstudyanteGO. To turn them off, '
          'use your device settings.',
        );
        return;
      case NotificationPermissionStatus.permanentlyDenied:
        await widget.permissionService.openAppSettings();
        await _loadNotificationStatus();
        return;
      case NotificationPermissionStatus.denied:
      case NotificationPermissionStatus.unknown:
        final allow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Allow notifications?'),
            content: const Text(
              'EstudyanteGO can send you notifications about community '
              'updates and service alerts. You can change this anytime '
              'in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Allow'),
              ),
            ],
          ),
        );
        if (allow == true) {
          await widget.permissionService.requestNotification();
          await _loadNotificationStatus();
        }
        return;
    }
  }

  Future<void> _changePassword() async {
    final user = _user;
    if (user == null) return;
    try {
      await widget.authService.sendPasswordReset(email: user.email);
      if (!mounted) return;
      _showSnack('Password reset link sent. Check your email.');
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message);
    }
  }

  Future<void> _verifyEmail() async {
    try {
      await widget.authService.sendEmailVerification();
      if (!mounted) return;
      _showSnack('Verification email sent. Check your inbox.');
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.authService.signOut();
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message);
      return;
    }
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    // Membership lives inside the Account tab so the shell's
    // navigation stays visible, matching the approved preview.
    if (_showingMembership) {
      return SubscriptionMembershipScreen(
        onBack: () => setState(() => _showingMembership = false),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 600;
        final header = _headerCard();
        final wallet = _walletCard();
        final quickActions = _quickActionsCard();
        final admin = _isAdmin ? _adminCard() : null;
        final history = Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Transaction History'),
            subtitle: Text(
              _entries.isEmpty
                  ? 'No transactions yet.'
                  : '${_entries.length} transactions',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showTransactionHistory,
          ),
        );
        final info = _sectionCard(
          title: 'Account Information',
          tiles: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Personal Information'),
              subtitle: Text(
                _signedIn
                    ? '${_profile?.displayName ?? _user!.email}\n${_user!.email}'
                    : 'Sign in to view',
              ),
              isThreeLine: _signedIn,
              trailing: const Icon(Icons.chevron_right),
              onTap: _openProfile,
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Student Information'),
              subtitle: Text(_studentInfoSummary()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openProfile,
            ),
            ListTile(
              leading: const Icon(Icons.work_outlined),
              title: const Text('Employment Information'),
              subtitle: Text(_employmentInfoSummary()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openProfile,
            ),
          ],
        );
        final preferences = _sectionCard(
          title: 'Preferences',
          tiles: [
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notification Settings'),
              subtitle: Text(_notificationStatusLabel()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _handleNotificationSettings,
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
              subtitle: const Text('English'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Language',
                'EstudyanteGO is available in English only for now. '
                'Real translations are out of scope for this version.',
              ),
            ),
          ],
        );
        final security = _sectionCard(
          title: 'Security & Privacy',
          tiles: [
            if (_signedIn) ...[
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Session'),
                subtitle: Text(
                  'Signed in as ${_user!.email}\n'
                  'Email ${_user!.emailVerified ? 'verified' : 'not verified'}',
                ),
                isThreeLine: true,
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change Password'),
                subtitle: const Text('Send a reset link to your email'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePassword,
              ),
              if (_user!.emailVerified)
                const ListTile(
                  leading: Icon(Icons.verified_outlined),
                  title: Text('Account Verification'),
                  subtitle: Text('Your email is verified.'),
                )
              else
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Account Verification'),
                  subtitle: const Text('Your email is not verified yet.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _verifyEmail,
                ),
            ] else
              const ListTile(
                leading: Icon(Icons.account_circle_outlined),
                title: Text('Session'),
                subtitle: Text('No account signed in.'),
              ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Privacy Settings',
                _signedIn
                    ? 'Your account lives in Firebase (email and sign-in '
                        'state). Your profile, settings, and community '
                        'posts are stored on this device only. Nothing '
                        'else is uploaded by this app.'
                    : 'No account is signed in. Only your on-device '
                        'settings (sidebar, theme) are stored, and '
                        'nothing is uploaded by this app.',
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
                'EstudyanteGO v1.0.0. For account help, use password reset '
                'from the Security & Privacy section.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About EstudyanteGO'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'About EstudyanteGO',
                'EstudyanteGO — Northern PH commute at jeepney companion. Trip '
                'planner, LTFRB fare calculator, at student hub. '
                'Version 1.0.0 (com.estudyantego.app).',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms and Conditions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Terms and Conditions',
                'EstudyanteGO is a commute companion. Fares shown are '
                'LTFRB-based estimates and verified operator fares; '
                'community posts are user-shared and unverified unless '
                'marked otherwise.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfoDialog(
                'Privacy Policy',
                'Your Firebase account holds your email and sign-in '
                'state. Your profile, settings, and community posts stay '
                'on this device. The app does not sell or share your data.',
              ),
            ),
            if (_signedIn)
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Sign Out',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: _signOut,
              ),
          ],
        );

        final sections = <Widget>[
          header,
          const SizedBox(height: AppLayout.cardGap),
          wallet,
          const SizedBox(height: AppLayout.cardGap),
          _subscriptionCard(),
          const SizedBox(height: AppLayout.cardGap),
          quickActions,
          const SizedBox(height: AppLayout.cardGap),
          if (admin != null) ...[
            admin,
            const SizedBox(height: AppLayout.cardGap),
          ],
          history,
          const SizedBox(height: AppLayout.cardGap),
          if (twoColumns) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                Expanded(child: preferences),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
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
            const SizedBox(height: AppLayout.cardGap),
            preferences,
            const SizedBox(height: AppLayout.cardGap),
            security,
            const SizedBox(height: AppLayout.cardGap),
            actions,
          ],
        ];

        // Full width on purpose: no narrow centered container. The
        // Account page CONTENT is single-column on phones; the shell
        // (sidebar on tablets) is unchanged.
        return SingleChildScrollView(
          key: const Key('account-scroll-view'),
          child: Padding(
            padding: AppLayout.pagePaddingTab,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections,
            ),
          ),
        );
      },
    );
  }

  String _studentInfoSummary() {
    final profile = _profile;
    if (!_signedIn) return 'Sign in to view';
    if (profile == null || !profile.hasStudentInfo) {
      return 'Not provided (optional)';
    }
    final parts = <String>[];
    if ((profile.school ?? '').isNotEmpty) parts.add(profile.school!);
    if ((profile.program ?? '').isNotEmpty) parts.add(profile.program!);
    if ((profile.year ?? '').isNotEmpty) parts.add(profile.year!);
    return parts.join(' · ');
  }

  String _employmentInfoSummary() {
    final profile = _profile;
    if (!_signedIn) return 'Sign in to view';
    if (profile == null || !profile.hasEmploymentInfo) {
      return 'Not provided (optional)';
    }
    final parts = <String>[];
    if ((profile.jobTitle ?? '').isNotEmpty) parts.add(profile.jobTitle!);
    if ((profile.company ?? '').isNotEmpty) parts.add(profile.company!);
    return parts.join(' · ');
  }

  Widget _headerCard() {
    final user = _user;
    if (user == null) {
      // Signed out (or Firebase not configured): no guest identity, no
      // guest chip — just an honest signed-out state with a sign-in
      // action. When Firebase is not configured, the sign-in screen
      // explains that.
      return Card(
        child: Padding(
          padding: AppLayout.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No account signed in',
                style: AppText.titleSmall,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                widget.authService.isConfigured
                    ? 'Sign in to see your profile, points, and settings.'
                    : 'Sign-in is not available in this build yet — '
                        'Firebase is not configured.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => widget.onSignInRequested?.call(),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      );
    }
    final profile = _profile;
    final photoPath = profile?.photoPath;
    final hasPhoto =
        photoPath != null && File(photoPath).existsSync();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF16A34A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      hasPhoto ? FileImage(File(photoPath)) : null,
                  child: hasPhoto
                      ? null
                      : Text(
                          (profile?.initials ??
                                  _initialsOf(user.displayName ?? user.email))
                              ,
                          style: const TextStyle(
                            color: Color(0xFF14532D),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.displayName ??
                            user.displayName ??
                            user.email,
                        style: AppText.titleSmall.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      if (user.emailVerified)
                        const Row(
                          children: [
                            Icon(Icons.verified,
                                color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        )
                      else
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                          onPressed: _verifyEmail,
                          icon: const Icon(Icons.mark_email_unread_outlined,
                              size: 16),
                          label: const Text('Verify email'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              onPressed: () => widget.onEditProfile?.call(),
              child: const Text('Edit Profile'),
            ),
          ],
        ),
      ),
    );
  }

  static String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  Widget _walletCard() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF16A34A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Points Wallet',
                  style: AppText.heading.copyWith(color: Colors.white),
                ),
                Spacer(),
                Icon(Icons.account_balance_wallet, color: Colors.white),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            Text(
              '$_balance points',
              key: const ValueKey('points-balance'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_walletRemote) ...[
              const SizedBox(height: 4),
              Text(
                'Total earned: $_totalEarned points',
                style: AppText.label.copyWith(color: Colors.white70),
              ),
            ],
            if (_creditsRemote) ...[
              const SizedBox(height: 4),
              Text(
                '${formatMinorUnits(_creditsBalanceUnits)} credits',
                style: AppText.label.copyWith(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _walletRemote
                  ? 'Your points from the 7-Day Sign-in, saved to your '
                      'account. They follow you across devices.'
                  : 'This is your account wallet. Student Hub sign-in points '
                      'are tracked separately in the Student tab.',
              style: AppText.label.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF14532D),
              ),
              onPressed: () => widget.onViewStudent?.call(),
              child: const Text('Earn Points'),
            ),
          ],
        ),
      ),
    );
  }

  /// Subscription Member card (approved preview/screenshot).
  ///
  /// NOTE: this card did not exist in the code before this change —
  /// the approved preview and the user's Account screenshot both show
  /// it between Points Wallet and Quick Actions, so it was added
  /// there (and nowhere else) to give the Membership flow its entry
  /// point. Everything else on the Account page is untouched. The
  /// card always shows the real current plan (Free): there is no
  /// payment provider, so no paid plan can ever be active.
  Widget _subscriptionCard() {
    return Card(
      color: const Color(0xFFDCFCE7),
      child: InkWell(
        key: const Key('subscription-member-card'),
        borderRadius: BorderRadius.circular(AppLayout.cardRadius),
        onTap: () => setState(() => _showingMembership = true),
        child: Padding(
          padding: AppLayout.cardPadding,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: CrownIcon(size: 28, color: Color(0xFF14532D)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subscription Member',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Unlock premium features and get more benefits.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14532D),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Free Plan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionsCard() {
    return _sectionCard(
      title: 'Quick Actions',
      tiles: [
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
          children: [
            _quickTile(
              Icons.person_outline,
              'My Profile',
              _openProfile,
            ),
            _quickTile(
              Icons.badge_outlined,
              'My Student ID',
              _openStudentId,
            ),
            _quickTile(
              Icons.history,
              'Transactions',
              _showTransactionHistory,
            ),
            _quickTile(
              Icons.card_giftcard_outlined,
              'Rewards',
              _openRewards,
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            label,
            textAlign: TextAlign.center,
            // Guard: the wide test font wraps labels to 3 lines and
            // overflows the fixed grid cell on narrow phones. On a
            // real phone (Roboto) labels fit in 1–2 lines, so this
            // cap never clips visible text there.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.smallSemiBold,
          ),
        ],
      ),
    );
  }

  Widget _adminCard() {
    // Admin-only section: visible only to allowlisted admin accounts
    // (admin_access.dart). The actions jump to the Communities tab,
    // where the gated admin screens live — no duplicated post state.
    return _sectionCard(
      title: 'Admin',
      tiles: [
        ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: const Text('Post approvals'),
          subtitle: const Text('Review community submissions'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onViewCommunities?.call(),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: const Text('LGU directory'),
          subtitle: const Text('Manage LGU directory entries'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onViewCommunities?.call(),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<Widget> tiles}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: AppText.cardTitle,
              ),
            ),
            const Divider(height: 8),
            ...tiles,
          ],
        ),
      ),
    );
  }
}
