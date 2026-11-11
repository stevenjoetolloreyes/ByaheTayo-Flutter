// Sign-in and create-account screens, driven by [AuthService].
//
// SPLIT (Nov 10): the old single AuthScreen (one screen, two modes
// toggled in place) is now TWO separate pages, so the startup flow
// is 9 steps: 1 Splash, 2–5 Onboarding, 6 Create Account,
// 7 Sign In, 8 Profile Setup, 9 Student tab. The cross-links
// between the two pages NAVIGATE (via the gate callbacks
// [SignInScreen.onCreateAccountRequested] /
// [CreateAccountScreen.onSignInRequested]) — they never toggle a
// mode, because there is no mode anymore.
//
// REDESIGN (Nov 2): Modern Minimalist entry theme, Android-first.
// Both pages share one shell ([_AuthShell]) and one design system.
// The header carries a back button (only when the gate supplies
// [onBack] — the first-launch path, where Back returns to the
// welcome state) and the Light/Dark theme toggle (only when the gate
// supplies [onThemeModeChanged]). Forgot password is a dialog that
// sends the Firebase reset email. Email/Password logic is unchanged.
// The form is flat on the themed background (no card, no gradient,
// no decorative shapes) with rounded inputs, per the spec's mockups.
//
// MINECRAFT THEME (Nov 11): the full blocky Minecraft treatment
// from the approved sign-in preview — grass hero with the current
// E logo as-is (white block + dirt strip), Baloo 2 headings,
// blocky buttons/cards (3px ink borders, hard shadows), a Press
// Start 2P pixel divider label, Nunito body, and Minecraft tap
// animations + synthesized sounds (submit = level-up arpeggio,
// other taps = click) via the existing sound engine. Visual-only:
// every value, state, and tap still works exactly as before. The
// step indicator is NOT reintroduced (it was removed Nov 11).
// Size notes (existing sizes kept, never shrunk): the page title
// stays 26sp (the real app's existing displaySmall size, not the
// preview's 20sp) and button labels stay 16sp (the entry spec's
// button size, not the preview's 15sp). The divider label is the
// theme's 10sp pixel accent. The shell keeps the 52dp entry CTA
// height (the Minecraft theme's Material buttons default to 40dp),
// and text buttons use grass green in both modes (the theme's
// deep-leaves text button is unreadable on the dark page).
//
// STRICT GOOGLE RULE (never weaken it):
// - Sign In Google is LOGIN ONLY: after Google authentication, the
//   screen looks up the EstudyanteGO profile for the Firebase UID in
//   ProfileStore. A profile means login proceeds (normal gate flow).
//   When the local profile is missing, the gate checks Firestore
//   (`student_profiles`, doc ID = UID) via [profileRepository]
//   BEFORE rejecting: a remote profile means login proceeds too
//   (the normal post-auth restore merges it into the local store),
//   so a returning user on a fresh install / cleared data / new
//   device is not locked out. No profile in EITHER store means
//   immediate sign-out + [noAccountFoundMessage] + a Create Account
//   button. Google sign-in NEVER auto-registers. The lookup is by
//   UID only — never by email — so a profile under a different UID
//   (a different Google account) still correctly says "No account
//   found" for this UID.
// - When no repository is supplied (Firebase unconfigured), the
//   gate falls back to the local-only check. When the Firestore
//   fetch itself fails (e.g. offline), the gate shows a retry-able
//   error instead of treating the failure as "no account" — and it
//   does NOT sign the user out, so one more tap retries.
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
import '../minecraft_tap_animation.dart';
import '../minecraft_theme.dart';
import '../profile_repository.dart';
import 'auth_service.dart';
import 'entry_theme.dart';
import 'onboarding_state.dart';
import 'splash_sound.dart';

/// Shown when Google Sign In succeeds but no EstudyanteGO profile
/// exists for the Firebase UID. Exact string (the strict rule requires
/// it verbatim, and tests assert it).
const noAccountFoundMessage =
    'No account found. Please create an account first.';

Future<ProfileStore> _profileStore() async {
  final prefs = await SharedPreferences.getInstance();
  return ProfileStore(prefs);
}

/// Blocky 48px frame for the header icon buttons (back + theme
/// toggle): surface fill, 2.5px ink border, 12px corners — the
/// Minecraft icon-chip treatment. The child's own key, tooltip,
/// and onPressed are untouched.
class _BlockyIconButton extends StatelessWidget {
  const _BlockyIconButton({required this.child, required this.isDark});

  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return MinecraftTapAnimation(
      sound: MinecraftSoundKind.click,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color:
              isDark ? MinecraftColors.darkElevated : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? MinecraftColors.darkBorder
                : MinecraftColors.border,
            width: 2.5,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Shared entry shell for the two auth pages: header (back + theme
/// toggle), grass hero branding, title, subtitle, then the page's
/// own [child] form content.
class _AuthShell extends StatelessWidget {
  const _AuthShell({
    required this.themeMode,
    this.onThemeModeChanged,
    this.onBack,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback? onBack;

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = entryEffectiveBrightness(themeMode, context);
    final colors = entryColorsFor(brightness);
    final isDark = brightness == Brightness.dark;
    final onThemeModeChanged = this.onThemeModeChanged;
    final onBack = this.onBack;
    // Minecraft theme for the auth pages, with the entry spec's
    // 52dp CTA height kept (the theme's Material buttons default
    // to 40dp) and grass text buttons (readable on the dark page
    // too). The outlined button's border and label follow the
    // brightness so they stay visible in dark mode.
    final outlineFg = isDark
        ? MinecraftColors.grassGreen
        : MinecraftColors.deepLeaves;
    final theme = minecraftThemeData(brightness).copyWith(
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MinecraftColors.grassGreen,
          textStyle: MinecraftText.button(
            color: MinecraftColors.grassGreen,
            fontSize: 16,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MinecraftColors.grassGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              MinecraftColors.grassGreen.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(52),
          shape: MinecraftShapes.buttonShape,
          textStyle: MinecraftText.button(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: outlineFg,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(
            color: isDark
                ? MinecraftColors.darkBorder
                : MinecraftColors.border,
            width: MinecraftShapes.buttonBorderWidth,
          ),
          shape: MinecraftShapes.buttonShape,
          textStyle: MinecraftText.button(color: outlineFg, fontSize: 16),
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: entryOverlayStyle(brightness),
      child: Theme(
        data: theme,
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
                        _BlockyIconButton(
                          isDark: isDark,
                          child: IconButton(
                            key: const Key('auth-back'),
                            tooltip: 'Back',
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                      const Spacer(),
                      if (onThemeModeChanged != null)
                        _BlockyIconButton(
                          isDark: isDark,
                          child: ThemeModeToggle(
                            mode: themeMode,
                            onModeChanged: onThemeModeChanged,
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  // Grass hero: the Minecraft header — grass
                  // gradient, the current E logo as-is in a white
                  // block with a dirt strip, Baloo 2 wordmark
                  // (white 'Estudyante', gold 'GO'), and the
                  // tagline in white. Kept compact (snug logo
                  // block, tight padding) so the submit button
                  // stays above the fold on a 600px viewport.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          MinecraftColors.grassBright,
                          MinecraftColors.grassMid,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        MinecraftShapes.cardRadius,
                      ),
                      border: MinecraftShapes.blockBorder,
                      boxShadow: const [MinecraftShapes.cardShadow],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 102,
                          height: 102,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              MinecraftShapes.cardRadius,
                            ),
                            border: MinecraftShapes.blockBorder,
                            boxShadow: const [MinecraftShapes.cardShadow],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              MinecraftShapes.cardRadius - 3,
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Image.asset(
                                      'assets/images/estudyantego_logo.png',
                                      width: 96,
                                      height: 96,
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 6,
                                  color: MinecraftColors.dirtBrown,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text.rich(
                            TextSpan(
                              style: MinecraftText.heading(
                                color: Colors.white,
                                fontSize: 28,
                              ),
                              children: [
                                const TextSpan(text: 'Estudyante'),
                                TextSpan(
                                  text: 'GO',
                                  style: TextStyle(
                                    color: MinecraftColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          'Your Student Companion',
                          style: MinecraftText.body(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: MinecraftText.heading(
                      color: colors.primaryText,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    subtitle,
                    style: MinecraftText.body(
                      color: colors.secondaryText,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google button shared by both pages: white, with the Google "G",
/// a 3px ink border, and 12px blocky corners.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: MinecraftColors.ink,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            MinecraftShapes.buttonRadius,
          ),
          side: const BorderSide(
            color: MinecraftColors.border,
            width: MinecraftShapes.buttonBorderWidth,
          ),
        ),
        elevation: 0,
      ),
      child: loading
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
                Flexible(
                  child: Text(
                    'Continue with Google',
                    style: MinecraftText.button(
                      color: MinecraftColors.ink,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
    );
    return MinecraftTapAnimation(
      sound: MinecraftSoundKind.click,
      enabled: enabled && !loading,
      child: button,
    );
  }
}

/// "OR SIGN IN WITH" / "OR SIGN UP WITH" divider, shared by both
/// pages. The label is the Press Start 2P pixel accent.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label, required this.colors});

  final String label;
  final EntryColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
          child: Text(
            label,
            style: MinecraftText.pixel(color: colors.secondaryText),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Step 7 of the 9-step startup flow: email/password sign-in plus
/// login-only Google sign-in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.service,
    required this.onSignedIn,
    required this.onCreateAccountRequested,
    this.profileRepository,
    this.themeMode = ThemeMode.dark,
    this.onThemeModeChanged,
    this.onBack,
  });

  final AuthService service;
  final ValueChanged<AuthUser> onSignedIn;

  /// The "Don't have an account? Create Account" link (and the
  /// no-account Create Account button) navigate to the Create
  /// Account page — the gate swaps the destination.
  final VoidCallback onCreateAccountRequested;

  /// Remote student-profile store, used ONLY as a fallback when the
  /// local profile is missing (see [_SignInScreenState
  /// ._handleGoogleSignIn]). The app passes the
  /// `isConfigured`-gated repository from main.dart
  /// (`FirestoreStudentProfileRepository` when Firebase is
  /// configured, null otherwise); null means the gate checks the
  /// local store only. Tests inject an in-memory fake here.
  final StudentProfileRepository? profileRepository;

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
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
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
    super.dispose();
  }

  String? _validate() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid email address.';
    }
    if (_passwordController.text.isEmpty) {
      return 'Enter your password.';
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
      final user = await widget.service.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      widget.onSignedIn(user);
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

  /// STRICT RULE — Sign In Google is LOGIN ONLY. The gate does not
  /// listen to authStateChanges (it moves only on the onSignedIn /
  /// onAccountCreated callbacks), so signing out here cannot strand
  /// the user on another screen: the gate stays on Sign In and this
  /// screen's message state survives.
  ///
  /// Firestore fallback (Nov 10, Feature 5): the local store is
  /// only a cache, so a missing local profile is NOT proof of no
  /// account — the profile may live in Firestore from another
  /// install or device. When the local lookup misses, the gate
  /// checks Firestore for this UID (doc ID = UID, never email)
  /// before rejecting. A remote profile proceeds to login (the
  /// normal post-auth restore merges it locally). No profile in
  /// either store signs out + shows [noAccountFoundMessage].
  /// A failed fetch is neither: it shows a retry-able error and
  /// leaves the user signed in, so one more tap retries.
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
        final repository = widget.profileRepository;
        if (repository != null) {
          try {
            final remote = await repository.fetchProfile(user.uid);
            if (!mounted) return;
            if (remote != null) {
              // Profile exists in Firestore (returning user, fresh
              // install / cleared data / new device): login
              // proceeds. The post-auth restore merges it locally.
              widget.onSignedIn(user);
              return;
            }
          } catch (_) {
            // A fetch failure is not "no account": show a
            // retry-able error and stay signed in, so the user can
            // tap again instead of being pushed to Create Account.
            if (mounted) {
              setState(
                () => _error = 'Something went wrong. Please try again.',
              );
            }
            return;
          }
        }
        // No profile locally AND none in Firestore (or no remote
        // store at all): never auto-register from Sign In — sign
        // out immediately and point at Create Account instead.
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
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.click,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ),
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.click,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send link'),
            ),
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
      TopPopup.show(
          context, message: 'Password reset link sent. Check your email.');
    } on AuthException catch (e) {
      if (mounted) {
        TopPopup.show(context, message: e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = entryEffectiveBrightness(widget.themeMode, context);
    final colors = entryColorsFor(brightness);
    return _AuthShell(
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      onBack: widget.onBack,
      title: 'Welcome Back',
      subtitle: 'Sign in to continue to EstudyanteGO.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_configured) ...[
            Container(
              padding: AppLayout.cardPadding,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(
                  MinecraftShapes.cardRadius,
                ),
                border: Border.all(color: colors.error, width: 2.5),
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
                      style: MinecraftText.body(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
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
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: Alignment.centerRight,
            child: MinecraftTapAnimation(
              sound: MinecraftSoundKind.click,
              enabled: _configured,
              child: TextButton(
                onPressed: _configured ? _forgotPassword : null,
                child: const Text('Forgot password?'),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              _error!,
              style: MinecraftText.body(color: colors.error),
            ),
          ],
          if (_noAccount) ...[
            const SizedBox(height: AppSpacing.s12),
            MinecraftTapAnimation(
              sound: MinecraftSoundKind.click,
              child: OutlinedButton(
                onPressed: widget.onCreateAccountRequested,
                child: const Text('Create Account'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.levelup,
            enabled: !_busy && _configured,
            child: FilledButton(
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
                        const Icon(Icons.login, size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Sign In',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          _OrDivider(label: 'OR SIGN IN WITH', colors: colors),
          const SizedBox(height: AppSpacing.s20),
          _GoogleButton(
            enabled: !_busy && _configured,
            loading: _googleLoading,
            onPressed: _handleGoogleSignIn,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'On Sign In, Google is login-only — no account, no entry.',
            textAlign: TextAlign.center,
            style: MinecraftText.body(
              color: colors.secondaryText,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.click,
            enabled: !_busy,
            child: TextButton(
              onPressed: _busy ? null : widget.onCreateAccountRequested,
              child: Text.rich(
                TextSpan(
                  style: MinecraftText.body(
                    color: colors.secondaryText,
                    fontSize: 15,
                  ),
                  children: [
                    const TextSpan(text: "Don't have an account? "),
                    TextSpan(
                      text: 'Create Account',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 6 of the 9-step startup flow: email/password registration
/// plus Google sign-up (the ONLY place Google creates an account).
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    required this.service,
    required this.onAccountCreated,
    required this.onSignedIn,
    required this.onSignInRequested,
    this.themeMode = ThemeMode.dark,
    this.onThemeModeChanged,
    this.onBack,
  });

  final AuthService service;

  /// Email/password registration: the account is unverified, so the
  /// gate routes to the email-verification screen.
  final ValueChanged<AuthUser> onAccountCreated;

  /// Google sign-up only: Google accounts are email-verified by
  /// construction, so the gate routes through the normal post-auth
  /// path (profile setup / dashboard) — NOT the email-verification
  /// screen, which exists only for email/password registrations.
  final ValueChanged<AuthUser> onSignedIn;

  /// The "Already have an account? Sign In" link navigates to the
  /// Sign In page — the gate swaps the destination.
  final VoidCallback onSignInRequested;

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
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;
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

  String? _validate() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid email address.';
    }
    if (_passwordController.text.isEmpty) {
      return 'Enter your password.';
    }
    if (_nameController.text.trim().isEmpty) {
      return 'Enter your full name.';
    }
    if (_passwordController.text.length < 6) {
      return 'Password must be at least 6 characters.';
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
    });
    try {
      final user = await widget.service.createAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
      if (!mounted) return;
      widget.onAccountCreated(user);
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

  @override
  Widget build(BuildContext context) {
    final brightness = entryEffectiveBrightness(widget.themeMode, context);
    final colors = entryColorsFor(brightness);
    return _AuthShell(
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      onBack: widget.onBack,
      title: 'Create Your Account',
      subtitle: 'Join EstudyanteGO and get started.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_configured) ...[
            Container(
              padding: AppLayout.cardPadding,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(
                  MinecraftShapes.cardRadius,
                ),
                border: Border.all(color: colors.error, width: 2.5),
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
                      style: MinecraftText.body(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
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
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              _error!,
              style: MinecraftText.body(color: colors.error),
            ),
          ],
          const SizedBox(height: 12),
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.levelup,
            enabled: !_busy && _configured,
            child: FilledButton(
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
                        const Icon(Icons.person_add_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Create Account',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          _OrDivider(label: 'OR SIGN UP WITH', colors: colors),
          const SizedBox(height: AppSpacing.s20),
          _GoogleButton(
            enabled: !_busy && _configured,
            loading: _googleLoading,
            onPressed: _handleGoogleSignUp,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Google here creates your account and profile.',
            textAlign: TextAlign.center,
            style: MinecraftText.body(
              color: colors.secondaryText,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.click,
            enabled: !_busy,
            child: TextButton(
              onPressed: _busy ? null : widget.onSignInRequested,
              child: Text.rich(
                TextSpan(
                  style: MinecraftText.body(
                    color: colors.secondaryText,
                    fontSize: 15,
                  ),
                  children: [
                    const TextSpan(text: 'Already have an account? '),
                    TextSpan(
                      text: 'Sign In',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
