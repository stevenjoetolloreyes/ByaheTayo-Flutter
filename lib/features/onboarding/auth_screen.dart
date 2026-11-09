// Sign-in / create-account screen, driven by [AuthService].
//
// REDESIGN (Nov 2): Modern Minimalist entry theme, Android-first.
// Both variants share one file and one design system; modes switch in
// place (no separate routes). The header carries a back button (only
// when the gate supplies [onBack] — the first-launch path, where Back
// returns to the welcome state) and the Light/Dark theme toggle (only
// when the gate supplies [onThemeModeChanged]). Forgot password is a
// dialog that sends the Firebase reset email. Email/Password logic is
// unchanged. The form is flat on the themed background (no card, no
// gradient, no decorative shapes) with rounded inputs, per the spec's
// mockups.
//
// STRICT GOOGLE RULE (never weaken it):
// - Sign In Google is LOGIN ONLY: after Google authentication, the
//   screen looks up the EstudyanteGO profile for the Firebase UID in
//   ProfileStore. A profile means login proceeds (normal gate flow).
//   No profile means immediate sign-out + [noAccountFoundMessage] +
//   a Create Account button. Google sign-in NEVER auto-registers.
// - Create Account Google is SIGN-UP: it creates the Firebase account
//   (when new) and the UID-keyed EstudyanteGO profile, reusing an
//   existing profile instead of duplicating it.
// When the service reports Firebase as not configured, the form shows
// a clear banner and all submit buttons stay disabled — the app never
// crashes and never fakes a sign-in.
import 'package:flutter/material.dart';
import '../top_popup.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_layout.dart';
import 'auth_service.dart';
import 'entry_theme.dart';
import 'onboarding_state.dart';

/// Shown when Google Sign In succeeds but no EstudyanteGO profile
/// exists for the Firebase UID. Exact string (the strict rule requires
/// it verbatim, and tests assert it).
const noAccountFoundMessage =
    'No account found. Please create an account first.';

enum AuthMode { signIn, createAccount }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.service,
    this.initialMode = AuthMode.signIn,
    required this.onSignedIn,
    required this.onAccountCreated,
    this.themeMode = ThemeMode.dark,
    this.onThemeModeChanged,
    this.onBack,
  });

  final AuthService service;
  final AuthMode initialMode;
  final ValueChanged<AuthUser> onSignedIn;
  final ValueChanged<AuthUser> onAccountCreated;

  /// Selected theme, from the app shell.
  final ThemeMode themeMode;

  /// When non-null, the header shows the Light/Dark toggle.
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// When non-null, the header shows a back button that invokes it.
  /// Null hides the button entirely (never a dead button): the gate
  /// supplies it only on the first-launch path, where Back returns to
  /// the welcome state.
  final VoidCallback? onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode = widget.initialMode;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;
  bool _noAccount = false;
  String? _error;

  bool get _configured => widget.service.isConfigured;
  bool get _busy => _loading || _googleLoading;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _noAccount = false;
    });
  }

  String? _validate() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid email address.';
    }
    if (_passwordController.text.isEmpty) {
      return 'Enter your password.';
    }
    if (_mode == AuthMode.createAccount) {
      if (_nameController.text.trim().isEmpty) {
        return 'Enter your full name.';
      }
      if (_passwordController.text.length < 6) {
        return 'Password must be at least 6 characters.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _noAccount = false;
    });
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_mode == AuthMode.signIn) {
        final user =
            await widget.service.signIn(email: email, password: password);
        if (!mounted) return;
        widget.onSignedIn(user);
      } else {
        final user = await widget.service.createAccount(
          email: email,
          password: password,
          displayName: _nameController.text.trim(),
        );
        if (!mounted) return;
        widget.onAccountCreated(user);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ProfileStore> _profileStore() async {
    final prefs = await SharedPreferences.getInstance();
    return ProfileStore(prefs);
  }

  /// STRICT RULE — Sign In Google is LOGIN ONLY. The gate does not
  /// listen to authStateChanges (it moves only on the onSignedIn /
  /// onAccountCreated callbacks), so signing out here cannot strand
  /// the user on another screen: the gate stays on Sign In and this
  /// screen's message state survives.
  Future<void> _handleGoogleSignIn() async {
    if (!_configured || _busy) return;
    setState(() {
      _googleLoading = true;
      _error = null;
      _noAccount = false;
    });
    try {
      final user = await widget.service.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        setState(() => _error = 'Google sign-in was canceled.');
        return;
      }
      final store = await _profileStore();
      if (!mounted) return;
      final profile = store.loadProfile(user.uid);
      if (profile == null) {
        // Never auto-register from Sign In: sign out immediately and
        // point at Create Account instead.
        await widget.service.signOut();
        if (!mounted) return;
        setState(() {
          _error = noAccountFoundMessage;
          _noAccount = true;
        });
        return;
      }
      widget.onSignedIn(user);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  /// STRICT RULE — Create Account Google is SIGN-UP. Creates the
  /// UID-keyed EstudyanteGO profile when none exists; reuses the
  /// existing profile otherwise (never a duplicate). Google accounts
  /// are email-verified by construction, so the normal post-auth
  /// router (onSignedIn) is correct here — NOT the email-verification
  /// screen, which exists only for email/password registrations. The
  /// gate's profile-setup step still runs afterwards (it collects
  /// optional school/employment info and refines this same record).
  Future<void> _handleGoogleSignUp() async {
    if (!_configured || _busy) return;
    setState(() {
      _googleLoading = true;
      _error = null;
      _noAccount = false;
    });
    try {
      final user = await widget.service.signUpWithGoogle();
      if (!mounted) return;
      if (user == null) {
        setState(() => _error = 'Google sign-in was canceled.');
        return;
      }
      final store = await _profileStore();
      if (!mounted) return;
      final existing = store.loadProfile(user.uid);
      if (existing == null) {
        await store.saveProfile(
          user.uid,
          UserProfile(
            displayName: user.displayName ?? user.email.split('@').first,
            email: user.email,
            photoUrl: user.photoUrl,
          ),
        );
        if (!mounted) return;
      }
      widget.onSignedIn(user);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot password?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email and we will send you a password reset link.',
            ),
            const SizedBox(height: AppSpacing.s16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (send != true || !mounted) return;
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        TopPopup.show(context, message: 'Enter a valid email address.');
      }
      return;
    }
    try {
      await widget.service.sendPasswordReset(email: email);
      if (!mounted) return;
      TopPopup.show(context, message: 'Password reset link sent. Check your email.');
    } on AuthException catch (e) {
      if (mounted) {
        TopPopup.show(context, message: e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _mode == AuthMode.createAccount;
    final brightness = entryEffectiveBrightness(widget.themeMode, context);
    final colors = entryColorsFor(brightness);
    final onThemeModeChanged = widget.onThemeModeChanged;
    final onBack = widget.onBack;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: entryOverlayStyle(brightness),
      child: Theme(
        data: entryThemeData(brightness),
        child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: back (first-launch path only) + theme
                  // toggle. Either may be absent; never a dead button.
                  Row(
                    children: [
                      if (onBack != null)
                        IconButton(
                          key: const Key('auth-back'),
                          tooltip: 'Back',
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back),
                        )
                      else
                        const SizedBox(width: 48),
                      const Spacer(),
                      if (onThemeModeChanged != null)
                        ThemeModeToggle(
                          mode: widget.themeMode,
                          onModeChanged: onThemeModeChanged,
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  // Branding.
                  Center(
                    child: Image.asset(
                      'assets/images/estudyantego_logo.png',
                      width: 96,
                      height: 96,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          style: AppText.displayMedium.copyWith(color: colors.primaryText),
                          children: [
                            const TextSpan(text: 'Estudyante'),
                            TextSpan(
                              text: 'GO',
                              style: TextStyle(color: colors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Center(
                    child: Text(
                      'Your Student Companion',
                      style: AppText.label.copyWith(color: colors.secondaryText),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    isCreate ? 'Create Your Account' : 'Welcome Back',
                    style: AppText.displaySmall.copyWith(color: colors.primaryText),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    isCreate
                        ? 'Join EstudyanteGO and get started.'
                        : 'Sign in to continue to EstudyanteGO.',
                    style: AppText.bodySmall.copyWith(color: colors.secondaryText),
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  if (!_configured) ...[
                    Container(
                      padding: AppLayout.cardPadding,
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: colors.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Firebase is not configured yet, so '
                              'sign-in is unavailable in this build. '
                              'Add google-services.json to enable it.',
                              style: TextStyle(color: colors.primaryText),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                  if (isCreate) ...[
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: entryInputDecoration(
                        label: 'Full name',
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: entryInputDecoration(
                      label: 'Email',
                      icon: Icons.email_outlined,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: entryInputDecoration(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (!isCreate) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _configured ? _forgotPassword : null,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      _error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                  if (_noAccount) ...[
                    const SizedBox(height: AppSpacing.s12),
                    OutlinedButton(
                      onPressed: () => _switchMode(AuthMode.createAccount),
                      child: const Text('Create Account'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s16),
                  FilledButton(
                    onPressed: (_busy || !_configured) ? null : _submit,
                    child: _loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCreate
                                    ? Icons.person_add_outlined
                                    : Icons.login,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  isCreate ? 'Create Account' : 'Sign In',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                        child: Text(
                          'OR',
                          style: AppText.captionSemiBold.copyWith(color: colors.secondaryText),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  ElevatedButton(
                    onPressed: (_busy || !_configured)
                        ? null
                        : (isCreate
                            ? _handleGoogleSignUp
                            : _handleGoogleSignIn),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF17211D),
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.5),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _googleLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF17211D),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/google_g_logo.png',
                                width: 24,
                                height: 24,
                              ),
                              const SizedBox(width: 12),
                              const Flexible(
                                child: Text(
                                  'Continue with Google',
                                  style: AppText.button,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _switchMode(
                              isCreate
                                  ? AuthMode.signIn
                                  : AuthMode.createAccount,
                            ),
                    child: Text.rich(
                      TextSpan(
                        style: AppText.bodySmall.copyWith(color: colors.secondaryText),
                        children: [
                          TextSpan(
                            text: isCreate
                                ? 'Already have an account? '
                                : "Don't have an account? ",
                          ),
                          TextSpan(
                            text: isCreate ? 'Sign In' : 'Create Account',
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
