// Firebase Auth implementation of [AuthService].
//
// Guard rule: when [isConfigured] is false, NO method touches
// `FirebaseAuth.instance` (which would throw without initialization).
// Every method either returns a safe value or throws
// [AuthNotConfiguredException], so the app never crashes on a device
// built before google-services.json was supplied.
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({required this.isConfigured});

  @override
  final bool isConfigured;

  fb.FirebaseAuth get _auth => fb.FirebaseAuth.instance;

  void _requireConfigured() {
    if (!isConfigured) throw const AuthNotConfiguredException();
  }

  static AuthUser _fromFirebase(fb.User user) {
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      emailVerified: user.emailVerified,
    );
  }

  @override
  AuthUser? get currentUser {
    if (!isConfigured) return null;
    try {
      final user = _auth.currentUser;
      return user == null ? null : _fromFirebase(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AuthUser?> get authStateChanges {
    if (!isConfigured) return Stream<AuthUser?>.value(null);
    return _auth
        .authStateChanges()
        .map((user) => user == null ? null : _fromFirebase(user));
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _requireConfigured();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException('Sign-in failed. Please try again.');
      }
      return _fromFirebase(user);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _requireConfigured();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException('Account creation failed. Please try again.');
      }
      await user.updateDisplayName(displayName);
      await user.reload();
      final fresh = _auth.currentUser;
      return fresh == null ? _fromFirebase(user) : _fromFirebase(fresh);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    _requireConfigured();
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    _requireConfigured();
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('No user is signed in.');
    }
    try {
      await user.sendEmailVerification();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
  }

  @override
  Future<AuthUser?> reloadUser() async {
    _requireConfigured();
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    final fresh = _auth.currentUser;
    return fresh == null ? null : _fromFirebase(fresh);
  }

  @override
  Future<void> signOut() async {
    _requireConfigured();
    await _auth.signOut();
    // Best-effort Google session cleanup so the next Google tap shows
    // the account chooser again. Skipped when Google was never
    // initialized (its methods require initialize() first).
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase sign-out already happened; ignore Google cleanup
        // failures.
      }
    }
  }

  /// True once [GoogleSignIn.instance.initialize] has completed.
  /// initialize() must be called exactly once per process; the flag
  /// keeps later Google taps from re-initializing (undefined behavior
  /// per the plugin docs). It stays false when initialize throws, so
  /// the next tap retries.
  static bool _googleInitialized = false;

  /// Makes sure Google Sign-In is initialized, exactly once per
  /// process (see [_googleInitialized]). Public so the Google
  /// Calendar sync (Feature 4) can authorize the calendar scope
  /// through the same already-initialized instance — calling
  /// initialize() a second time from the sync would be undefined
  /// behavior. This only initializes the plugin; it never signs
  /// anyone in and never touches Firebase Auth.
  static Future<void> ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  }

  Future<void> _ensureGoogleInitialized() => ensureGoogleInitialized();

  /// Shared Google flow for login and signup: native account chooser,
  /// Firebase credential sign-in. Returns null ONLY when the user
  /// canceled. The login-vs-signup rule lives at the call site (the
  /// auth screen checks/creates the EstudyanteGO profile); this
  /// method never touches ProfileStore.
  Future<AuthUser?> _googleAuth() async {
    _requireConfigured();
    try {
      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthException(
          'Google sign-in did not return an ID token.',
        );
      }
      final credential = fb.GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw const AuthException('Google sign-in failed. Please try again.');
      }
      return _fromFirebase(user);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const AuthException('Google sign-in failed. Please try again.');
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
  }

  @override
  Future<AuthUser?> signInWithGoogle() => _googleAuth();

  @override
  Future<AuthUser?> signUpWithGoogle() => _googleAuth();

  /// Friendly, generic messages. Sign-in failures deliberately do not say
  /// whether the email exists.
  static String _messageForCode(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in.';
      case 'account-exists-with-different-credential':
        return 'This email is already registered with a different sign-in method. Try signing in with email and password.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a bit and try again.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled for this app yet.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
