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

import 'ad_service.dart';
import 'admin_access.dart';
import 'app_layout.dart';
import 'credits_repository.dart';
import 'ios_glass.dart';
import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'onboarding/permission_service.dart';
import 'points_wallet_repository.dart';
import 'rewards_screen.dart';
import 'student_id_card.dart';
import 'subscription_membership.dart';

// Account tab's OWN design tokens — ChatGPT design system Steven
// adopted Nov 5 as a LOOSE UI base ("wag mo seryusuhin"): Premium
// Dark + Emerald Green with a matching Light Mode. Adapted, not
// forced — the approved Gemini layout (profile card, wallet,
// subscription, quick actions, grouped sections, admin card) is
// unchanged; only the colors, radii, typography and spacing below
// are the tab's own. Primary stays Deep Emerald Green #14532D in
// both modes; the readable dark accent is #34D399 and the light
// accent is #059669. The glass (iPhone) variant keeps its
// translucent-white surfaces; only its green tints are retokened.
const kAccountEmerald = Color(0xFF14532D);
const kAccountEmeraldAccent = Color(0xFF16A34A);
const kAccountLightAccent = Color(0xFF059669);
const kAccountDarkAccent = Color(0xFF34D399);
const kAccountDarkSurface = Color(0xFF18221D);
const kAccountDarkCard = Color(0xFF202B25);
const kAccountWarning = Color(0xFFF59E0B);
// Card corner radius (ChatGPT: 18–22px) and button radius (14px).
const kAccountCardRadius = 20.0;
const kAccountButtonRadius = 14.0;
// Account typography (ChatGPT scale, tab-local so the shared
// AppText scale — used by other tabs — stays untouched).
// Page title 26 Bold, card heading 16 Semibold. Body and secondary
// text keep the app's established sizes.
const kAccountPageTitle =
    TextStyle(fontSize: 26, fontWeight: FontWeight.w800);
const kAccountCardHeading =
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

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
    this.adService,
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

  /// Shared AdMob state (null in bare widget tests, in which case
  /// the Rewards screen keeps its honest no-ads notice).
  final AdService? adService;

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
              const SizedBox(height: 24),
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
          adService: widget.adService,
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
    // iPhone glass branch: appearance only — same sections, same
    // order, same taps. Android (and tests) take the Material path.
    final glass = iosGlassEnabled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 600;
        final brand = _brandHeader(glass);
        final profile = _profileCard(glass);
        final wallet = _walletCard(glass);
        final quickActions = _quickActionsCard(glass);
        final admin = _isAdmin ? _adminCard(glass) : null;
        final history = _previewCard(
          glass,
          _infoTile(
            icon: Icons.history,
            title: 'Transaction History',
            subtitle: _entries.isEmpty
                ? 'No transactions yet.'
                : '${_entries.length} transactions',
            onTap: _showTransactionHistory,
            glass: glass,
          ),
          listTheme: true,
        );
        final info = _sectionCard(
          glass: glass,
          icon: Icons.info_outline,
          title: 'Account Information',
          tiles: [
            _infoTile(
              icon: Icons.person_outline,
              title: 'Personal Information',
              subtitle: _signedIn
                  ? '${_profile?.displayName ?? _user!.email}\n${_user!.email}'
                  : 'Sign in to view',
              isThreeLine: _signedIn,
              onTap: _openProfile,
              glass: glass,
            ),
            _infoTile(
              icon: Icons.school_outlined,
              title: 'Student Information',
              subtitle: _studentInfoSummary(),
              onTap: _openProfile,
              glass: glass,
            ),
            _infoTile(
              icon: Icons.work_outlined,
              title: 'Employment Information',
              subtitle: _employmentInfoSummary(),
              onTap: _openProfile,
              glass: glass,
            ),
          ],
        );
        final preferences = _sectionCard(
          glass: glass,
          icon: Icons.settings_outlined,
          title: 'Preferences',
          tiles: [
            _infoTile(
              icon: Icons.notifications_outlined,
              title: 'Notification Settings',
              subtitle: _notificationStatusLabel(),
              onTap: _handleNotificationSettings,
              glass: glass,
            ),
            _infoTile(
              icon: Icons.brightness_6_outlined,
              title: 'Theme Settings',
              subtitle: _themeModeLabel(widget.themeMode),
              onTap: _pickTheme,
              glass: glass,
            ),
            _infoTile(
              icon: Icons.language,
              title: 'Language Settings',
              subtitle: 'English',
              onTap: () => _showInfoDialog(
                'Language',
                'EstudyanteGO is available in English only for now. '
                'Real translations are out of scope for this version.',
              ),
              glass: glass,
            ),
          ],
        );
        final security = _sectionCard(
          glass: glass,
          icon: Icons.shield_outlined,
          title: 'Security & Privacy',
          tiles: [
            if (_signedIn) ...[
              _infoTile(
                icon: Icons.account_circle_outlined,
                title: 'Session',
                subtitle: 'Signed in as ${_user!.email}\n'
                    'Email ${_user!.emailVerified ? 'verified' : 'not verified'}',
                isThreeLine: true,
                showChevron: false,
                glass: glass,
              ),
              _infoTile(
                icon: Icons.lock_outline,
                title: 'Change Password',
                subtitle: 'Send a reset link to your email',
                onTap: _changePassword,
                glass: glass,
              ),
              if (_user!.emailVerified)
                _infoTile(
                  icon: Icons.verified_outlined,
                  title: 'Account Verification',
                  subtitle: 'Your email is verified.',
                  showChevron: false,
                  glass: glass,
                )
              else
                _infoTile(
                  icon: Icons.verified_outlined,
                  title: 'Account Verification',
                  subtitle: 'Your email is not verified yet.',
                  onTap: _verifyEmail,
                  glass: glass,
                ),
            ] else
              _infoTile(
                icon: Icons.account_circle_outlined,
                title: 'Session',
                subtitle: 'No account signed in.',
                showChevron: false,
                glass: glass,
              ),
            _infoTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Settings',
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
              glass: glass,
            ),
          ],
        );
        final actions = _sectionCard(
          glass: glass,
          icon: Icons.grid_view_outlined,
          title: 'Account Actions',
          tiles: [
            _infoTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () => _showInfoDialog(
                'Help & Support',
                'EstudyanteGO v1.0.0. For account help, use password reset '
                'from the Security & Privacy section.',
              ),
              glass: glass,
            ),
            _infoTile(
              icon: Icons.info_outline,
              title: 'About EstudyanteGO',
              subtitle: 'Version 1.0.0',
              onTap: () => _showInfoDialog(
                'About EstudyanteGO',
                'EstudyanteGO — Northern PH commute at jeepney companion. Trip '
                'planner, LTFRB fare calculator, at student hub. '
                'Version 1.0.0 (com.estudyantego.app).',
              ),
              glass: glass,
            ),
            _infoTile(
              icon: Icons.description_outlined,
              title: 'Terms and Conditions',
              onTap: () => _showInfoDialog(
                'Terms and Conditions',
                'EstudyanteGO is a commute companion. Fares shown are '
                'LTFRB-based estimates and verified operator fares; '
                'community posts are user-shared and unverified unless '
                'marked otherwise.',
              ),
              glass: glass,
            ),
            _infoTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () => _showInfoDialog(
                'Privacy Policy',
                'Your Firebase account holds your email and sign-in '
                'state. Your profile, settings, and community posts stay '
                'on this device. The app does not sell or share your data.',
              ),
              glass: glass,
            ),
            if (_signedIn)
              _infoTile(
                icon: Icons.logout,
                title: 'Sign Out',
                iconColor: Theme.of(context).colorScheme.error,
                iconBackground: _isDark
                    ? const Color(0xFF3A1A1A)
                    : const Color(0xFFFCECEC),
                titleColor: Theme.of(context).colorScheme.error,
                showChevron: false,
                onTap: _signOut,
                glass: glass,
              ),
          ],
        );

        final footer = Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 5),
          child: Text(
            'ESTUDYANTEGO · VERSION 1.0.0',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.5,
              color: glass
                  ? Colors.white70
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );

        // ChatGPT spacing: 24px between sections.
        final sections = <Widget>[
          brand,
          const SizedBox(height: 24),
          profile,
          const SizedBox(height: 24),
          wallet,
          const SizedBox(height: 24),
          _subscriptionCard(glass),
          const SizedBox(height: 24),
          quickActions,
          const SizedBox(height: 24),
          history,
          const SizedBox(height: 24),
          if (twoColumns) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                Expanded(child: preferences),
              ],
            ),
            const SizedBox(height: 24),
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
            const SizedBox(height: 24),
            preferences,
            const SizedBox(height: 24),
            security,
            const SizedBox(height: 24),
            actions,
          ],
          if (admin != null) ...[
            const SizedBox(height: 24),
            admin,
          ],
          footer,
        ];

        // Full width on purpose: no narrow centered container. The
        // Account page CONTENT is single-column on phones; the shell
        // (sidebar on tablets) is unchanged.
        final scrollView = SingleChildScrollView(
          key: const Key('account-scroll-view'),
          child: Padding(
            // ChatGPT spacing: 20px horizontal screen padding.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections,
            ),
          ),
        );
        if (glass) {
          return IosGlassBackground(child: scrollView);
        }
        return scrollView;
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

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  /// Soft green tile behind a list-item icon (approved Account
  /// preview). Theme-aware: pale green on light, ChatGPT dark
  /// surface on dark, translucent white on the iPhone glass path.
  Widget _tileIcon(
    IconData icon, {
    Color? color,
    Color? background,
    bool glass = false,
  }) {
    final dark = _isDark;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: background ??
            (glass
                ? Colors.white.withValues(alpha: 0.12)
                : dark
                    ? kAccountDarkSurface
                    : const Color(0xFFEAF4ED)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        icon,
        size: 18,
        color: color ??
            (glass
                ? Colors.white
                : dark
                    ? kAccountDarkAccent
                    : Theme.of(context).colorScheme.primary),
      ),
    );
  }

  /// One Account list row in the approved preview style: soft icon
  /// tile, compact bold title, muted subtitle, chevron. Same taps as
  /// the rows it replaces — appearance only.
  Widget _infoTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool showChevron = true,
    bool isThreeLine = false,
    Color? titleColor,
    Color? iconColor,
    Color? iconBackground,
    bool glass = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: _tileIcon(
        icon,
        color: iconColor,
        background: iconBackground,
        glass: glass,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: glass
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
      isThreeLine: isThreeLine,
      trailing: showChevron
          ? Icon(
              Icons.chevron_right,
              size: 20,
              color: glass ? null : Theme.of(context).hintColor,
            )
          : null,
      onTap: onTap,
    );
  }

  /// Header (approved Account preview): ChatGPT-token gradient
  /// with the "My Account" headline and subtitle only. The brand
  /// row (E tile, EstudyanteGO wordmark, bell) was removed at the
  /// user's request; Notification Settings stays reachable from
  /// Preferences.
  Widget _brandHeader(bool glass) {
    final dark = _isDark;
    final onHeader =
        glass ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final muted = glass
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Account',
          style: kAccountPageTitle.copyWith(
            letterSpacing: -1.1,
            color: onHeader,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Manage your profile, preferences, and more.',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      ],
    );
    if (glass) {
      return GlassCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 17),
        child: content,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? const [kAccountDarkSurface, kAccountDarkCard]
              : const [
                  Colors.white,
                  Color(0xFFF5F8F6),
                  Color(0xFFE9F5ED),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kAccountCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 17),
        child: content,
      ),
    );
  }

  /// Profile card (approved Account preview): white card with the
  /// real photo or honest initials, name + email, Verified state,
  /// and Edit Profile. Signed-out state stays honest — "No account
  /// signed in", never a guest identity. Same taps as before.
  Widget _profileCard(bool glass) {
    final user = _user;
    final onCard =
        glass ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final mutedCard = glass
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final accent =
        glass ? Colors.white : Theme.of(context).colorScheme.primary;
    if (user == null) {
      // Signed out (or Firebase not configured): no guest identity, no
      // guest chip — just an honest signed-out state with a sign-in
      // action. When Firebase is not configured, the sign-in screen
      // explains that.
      final content = Row(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFD9F0E1), Color(0xFF9DCEAD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.person_outline,
              size: 28,
              color: kAccountEmerald,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No account signed in',
                  style: kAccountCardHeading.copyWith(color: onCard),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.authService.isConfigured
                      ? 'Sign in to see your profile, points, and settings.'
                      : 'Sign-in is not available in this build yet — '
                          'Firebase is not configured.',
                  style: TextStyle(fontSize: 11, color: mutedCard),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => widget.onSignInRequested?.call(),
            child: const Text('Sign In'),
          ),
        ],
      );
      return _previewCard(glass, content);
    }
    final profile = _profile;
    final photoPath = profile?.photoPath;
    final hasPhoto = photoPath != null && File(photoPath).existsSync();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFD9F0E1),
              backgroundImage: hasPhoto ? FileImage(File(photoPath)) : null,
              child: hasPhoto
                  ? null
                  : Text(
                      profile?.initials ??
                          _initialsOf(user.displayName ?? user.email),
                      style: const TextStyle(
                        color: kAccountEmerald,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.displayName ?? user.displayName ?? user.email,
                    style: kAccountCardHeading.copyWith(color: onCard),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email,
                    style: TextStyle(fontSize: 11, color: mutedCard),
                  ),
                  const SizedBox(height: 8),
                  if (user.emailVerified)
                    Row(
                      children: [
                        Icon(Icons.verified, color: accent, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Verified',
                          style: TextStyle(fontSize: 12, color: onCard),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      style: glass
                          ? OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                            )
                          : OutlinedButton.styleFrom(
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
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: glass
                ? OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  )
                : null,
            onPressed: () => widget.onEditProfile?.call(),
            child: const Text('Edit Profile'),
          ),
        ),
      ],
    );
    return _previewCard(glass, content);
  }

  /// Shared card wrapper for the preview-styled cards: frosted
  /// glass on iPhone, theme surface with a soft border + 20dp
  /// corners on Material (light and dark).
  Widget _previewCard(bool glass, Widget child, {bool listTheme = false}) {
    if (glass) {
      final content = listTheme ? GlassListTheme(child: child) : child;
      return GlassCard(
        padding: const EdgeInsets.all(16),
        child: content,
      );
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAccountCardRadius),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
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

  Widget _walletCard(bool glass) {
    // Same inner content on both paths; only the wrapper changes.
    // Preview style: 130deg emerald gradient, POINTS WALLET header,
    // big balance, Total Earned + Credits side by side (plain
    // numbers, no peso sign — formatMinorUnits never adds one), and
    // a full-width white Earn Points button.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'Points Wallet',
              style: TextStyle(
                color: Color(0xFFD9F1E1),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '$_balance points',
          key: const ValueKey('points-balance'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            _walletStat(
              Icons.emoji_events_outlined,
              'Total Earned',
              '$_totalEarned',
            ),
            const SizedBox(width: 28),
            _walletStat(
              Icons.monetization_on_outlined,
              'Credits',
              formatMinorUnits(_creditsBalanceUnits),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _walletRemote
              ? 'Your points from the 7-Day Sign-in, saved to your '
                  'account. They follow you across devices.'
              : 'This is your account wallet. Student Hub sign-in points '
                  'are tracked separately in the Student tab.',
          style: AppText.label.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 17),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kAccountEmerald,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kAccountButtonRadius),
              ),
            ),
            onPressed: () => widget.onViewStudent?.call(),
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text(
              'Earn Points',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
    if (glass) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        child: content,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kAccountEmerald, kAccountLightAccent, kAccountEmeraldAccent],
          stops: [0, 0.65, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(kAccountCardRadius)),
        boxShadow: [
          BoxShadow(
            color: kAccountEmerald.withValues(alpha: 0.17),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  /// One wallet stat (icon + label over a bold value), as in the
  /// approved preview. Values are the real controller balances
  /// (0 when no backend is attached) — never invented.
  Widget _walletStat(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFD9F1E1)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFD9F1E1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
  Widget _subscriptionCard(bool glass) {
    // Preview style: pale-yellow crown tile, "Subscription Member"
    // + "Your current membership plan", green plan pill, chevron.
    // The pill shows the REAL current plan (Free): there is no
    // payment provider, so no paid plan can ever be active — the
    // preview's STANDARD tag is example data, not the user's plan.
    final dark = _isDark;
    final tileColor = glass
        ? Colors.white.withValues(alpha: 0.12)
        : dark
            ? const Color(0xFF3A2E14)
            : const Color(0xFFFFF4D9);
    final crownColor = glass
        ? Colors.white
        : dark
            ? kAccountWarning
            : const Color(0xFFB45309);
    final titleColor = glass ? Colors.white : null;
    final subtitleColor = glass
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final chevronColor = glass ? Colors.white : null;
    final tagBackground = glass
        ? Colors.white.withValues(alpha: 0.15)
        : dark
            ? kAccountDarkSurface
            : const Color(0xFFE0F4E6);
    final tagColor = glass
        ? Colors.white
        : dark
            ? kAccountDarkAccent
            : const Color(0xFF176238);
    final inkWell = InkWell(
      key: const Key('subscription-member-card'),
      borderRadius: BorderRadius.circular(kAccountCardRadius),
      onTap: () => setState(() => _showingMembership = true),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: CrownIcon(size: 24, color: crownColor),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subscription Member',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Your current membership plan',
                    style: TextStyle(fontSize: 11, color: subtitleColor),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: tagBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Free Plan',
                style: TextStyle(
                  color: tagColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: chevronColor),
          ],
        ),
      ),
    );
    if (glass) {
      return GlassCard(child: inkWell);
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAccountCardRadius),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: inkWell,
    );
  }

  /// Quick Actions (approved preview): "Quick Actions" + "Explore
  /// shortcuts" title row above four bordered tiles. Same four
  /// actions, same taps as before.
  Widget _quickActionsCard(bool glass) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 9, 5, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Quick Actions',
                  style: kAccountCardHeading.copyWith(
                    color: glass ? Colors.white : null,
                  ),
                ),
              ),
              Text(
                'Explore shortcuts',
                style: TextStyle(
                  fontSize: 11,
                  color: glass
                      ? Colors.white70
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: [
            _quickTile(
              Icons.person_outline,
              'My Profile',
              _openProfile,
              glass,
            ),
            _quickTile(
              Icons.badge_outlined,
              'My Student ID',
              _openStudentId,
              glass,
            ),
            _quickTile(
              Icons.history,
              'Transactions',
              _showTransactionHistory,
              glass,
            ),
            _quickTile(
              Icons.card_giftcard_outlined,
              'Rewards',
              _openRewards,
              glass,
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickTile(
      IconData icon, String label, VoidCallback onTap, bool glass) {
    return Material(
      color: glass
          ? Colors.white.withValues(alpha: 0.12)
          : Theme.of(context).cardColor,
      elevation: glass ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAccountCardRadius),
        side: BorderSide(
          color: glass
              ? Colors.white.withValues(alpha: 0.35)
              : Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: glass
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                label,
                textAlign: TextAlign.center,
                // Guard: the wide test font wraps labels to 3 lines and
                // overflows the fixed grid cell on narrow phones. On a
                // real phone (Roboto) labels fit in 1–2 lines, so this
                // cap never clips visible text there.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: glass ? Colors.white : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminCard(bool glass) {
    // Admin-only section: visible only to allowlisted admin accounts
    // (admin_access.dart). The actions jump to the Communities tab,
    // where the gated admin screens live — no duplicated post state.
    // Both existing tiles are kept; the preview shows only the LGU
    // tile, but Post approvals is a real admin function.
    final dark = _isDark;
    return _sectionCard(
      glass: glass,
      icon: Icons.star_outline,
      title: 'Admin Access',
      titleTrailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: glass
              ? Colors.white.withValues(alpha: 0.15)
              : dark
                  ? kAccountDarkSurface
                  : const Color(0xFFDFF5E6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outlined,
              size: 11,
              color: glass
                  ? Colors.white
                  : dark
                      ? kAccountDarkAccent
                      : const Color(0xFF176238),
            ),
            const SizedBox(width: 4),
            Text(
              'RESTRICTED',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: glass
                    ? Colors.white
                    : dark
                        ? kAccountDarkAccent
                        : const Color(0xFF176238),
              ),
            ),
          ],
        ),
      ),
      surfaceColor: glass
          ? null
          : dark
              ? kAccountDarkCard
              : const Color(0xFFF0FAF3),
      tiles: [
        _infoTile(
          icon: Icons.verified_outlined,
          title: 'Post approvals',
          subtitle: 'Review community submissions',
          onTap: () => widget.onViewCommunities?.call(),
          glass: glass,
        ),
        _infoTile(
          icon: Icons.account_balance_outlined,
          title: 'LGU directory',
          subtitle: 'Manage LGU directory entries',
          onTap: () => widget.onViewCommunities?.call(),
          glass: glass,
        ),
      ],
    );
  }

  /// Grouped card (approved preview): icon + title header, rows
  /// separated by hairline dividers. Theme-aware surface; the admin
  /// group passes its own green-tinted surface.
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> tiles,
    Widget titleTrailing = const SizedBox.shrink(),
    Color? surfaceColor,
    bool glass = false,
  }) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: glass
                ? Colors.white
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: kAccountCardHeading,
            ),
          ),
          titleTrailing,
        ],
      ),
    );
    final separated = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) separated.add(const Divider(height: 1));
      separated.add(tiles[i]);
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        ...separated,
        const SizedBox(height: 6),
      ],
    );
    if (glass) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GlassListTheme(child: content),
      );
    }
    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAccountCardRadius),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }
}
