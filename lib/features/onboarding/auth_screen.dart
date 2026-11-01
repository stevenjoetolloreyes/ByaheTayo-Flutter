// Sign-in / create-account screen, driven by [AuthService].
//
// REDESIGN (Nov 2): premium dark emerald Material 3, Android-first.
// Both variants share one file and one design system; modes switch in
// place (no separate routes). Neither variant has an AppBar: the
// branding sits directly below the status bar and the Android system
// status bar stays visible. Forgot password is a dialog that sends
// the Firebase reset email. Email/Password logic is unchanged.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
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
  });

  final AuthService service;
  final AuthMode initialMode;
  final ValueChanged<AuthUser> onSignedIn;
  final ValueChanged<AuthUser> onAccountCreated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Spec palette (design reference).
  static const _bg = Color(0xFF121619);
  static const _card = Color(0xFF1C2229);
  static const _fieldFill = Color(0xFF252C34);
  static const _emerald = Color(0xFF00A86B);
  static const _mint = Color(0xFF20D69B);
  static const _muted = Color(0xFF9AA7B4);
  static const _errorRed = Color(0xFFFF8A80);

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
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid email address.')),
        );
      }
      return;
    }
    try {
      await widget.service.sendPasswordReset(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset link sent. Check your email.'),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  ThemeData get _darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _emerald,
          secondary: _mint,
          surface: _card,
          error: _errorRed,
        ),
      );

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _muted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _emerald, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _mode == AuthMode.createAccount;
    return Theme(
      data: _darkTheme,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _WavesPainter()),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Branding, directly below the status bar.
                    Center(
                      child: Image.asset(
                        'assets/images/estudyantego_logo.png',
                        width: 128,
                        height: 128,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          children: [
                            TextSpan(text: 'Estudyante'),
                            TextSpan(
                              text: 'GO',
                              style: TextStyle(color: _emerald),
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 28, height: 2, color: _emerald),
                        const Flexible(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Your Student Companion',
                                style: TextStyle(fontSize: 14, color: _muted),
                              ),
                            ),
                          ),
                        ),
                        Container(width: 28, height: 2, color: _emerald),
                      ],
                    ),
                    const SizedBox(height: 28),
                    // Form card.
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isCreate ? 'Create your account' : 'Welcome back',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isCreate
                                ? 'Join EstudyanteGO and get started.'
                                : 'Sign in to continue to EstudyanteGO.',
                            style: const TextStyle(
                              fontSize: 14,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (!_configured) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3D1A1A),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, color: _errorRed),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Firebase is not configured yet, so '
                                      'sign-in is unavailable in this build. '
                                      'Add google-services.json to enable it.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (isCreate) ...[
                            TextField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDecoration(
                                label: 'Full name',
                                icon: Icons.person_outline,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(
                              label: 'Email',
                              icon: Icons.email_outlined,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(
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
                                  color: _muted,
                                ),
                              ),
                            ),
                          ),
                          if (!isCreate) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    _configured ? _forgotPassword : null,
                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(color: _mint),
                                ),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: _errorRed),
                            ),
                          ],
                          if (_noAccount) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  _switchMode(AuthMode.createAccount),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _mint,
                                side: const BorderSide(color: _mint),
                                minimumSize: const Size.fromHeight(48),
                                shape: const StadiumBorder(),
                              ),
                              child: const Text('Create an account'),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed:
                                (_busy || !_configured) ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: _mint,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _mint.withValues(alpha: 0.4),
                              minimumSize: const Size.fromHeight(52),
                              shape: const StadiumBorder(),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
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
                                          isCreate
                                              ? 'Create account'
                                              : 'Sign in',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 20),
                          const Row(
                            children: [
                              Expanded(
                                child: Divider(color: Colors.white24),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: Colors.white24),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: (_busy || !_configured)
                                ? null
                                : (isCreate
                                    ? _handleGoogleSignUp
                                    : _handleGoogleSignIn),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _bg,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.5),
                              minimumSize: const Size.fromHeight(52),
                              shape: const StadiumBorder(),
                              elevation: 0,
                            ),
                            child: _googleLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _bg,
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
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 16),
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _muted,
                                ),
                                children: [
                                  TextSpan(
                                    text: isCreate
                                        ? 'Already have an account? '
                                        : "Don't have an account? ",
                                  ),
                                  TextSpan(
                                    text: isCreate ? 'Sign in' : 'Create one',
                                    style: const TextStyle(
                                      color: _mint,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle emerald decorative waves behind the sign-in content. Built
/// shapes only — no images, no emoji. Static and deterministic so
/// widget tests stay stable.
class _WavesPainter extends CustomPainter {
  const _WavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final topPath = Path()
      ..moveTo(size.width * 0.55, -20)
      ..quadraticBezierTo(
        size.width * 0.95,
        size.height * 0.08,
        size.width + 20,
        size.height * 0.02,
      )
      ..quadraticBezierTo(
        size.width * 0.9,
        size.height * 0.16,
        size.width * 0.6,
        size.height * 0.14,
      )
      ..close();
    canvas.drawPath(
      topPath,
      Paint()..color = _AuthScreenState._emerald.withValues(alpha: 0.12),
    );

    final bottomPath = Path()
      ..moveTo(-20, size.height * 0.92)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.86,
        size.width * 0.6,
        size.height * 0.93,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.99,
        size.width + 20,
        size.height * 0.92,
      )
      ..lineTo(size.width + 20, size.height + 20)
      ..lineTo(-20, size.height + 20)
      ..close();
    canvas.drawPath(
      bottomPath,
      Paint()..color = _AuthScreenState._emerald.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
