// Authentication abstraction for EstudyanteGO.
//
// The app talks to auth ONLY through [AuthService]. The production
// implementation ([FirebaseAuthService]) delegates to Firebase Auth, and
// tests use a fake. This keeps every screen testable without a real
// Firebase project, and keeps the app usable before Firebase is
// configured: when [AuthService.isConfigured] is false, every method
// either returns a safe empty value or throws [AuthNotConfiguredException]
// without ever touching the Firebase SDK.

/// A signed-in user, as the app sees them. Only the fields the UI needs.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.emailVerified = false,
  });

  final String uid;
  final String email;
  final String? displayName;

  /// Google profile photo URL (null for email/password accounts).
  final String? photoUrl;
  final bool emailVerified;

  AuthUser copyWith({
    bool? emailVerified,
    String? displayName,
    String? photoUrl,
  }) {
    return AuthUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
}

/// A user-facing auth failure. [message] is safe to show in the UI.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Thrown when auth is used before Firebase is configured (no
/// google-services.json yet). Screens catch this and show the
/// "not configured" state instead of crashing.
class AuthNotConfiguredException extends AuthException {
  const AuthNotConfiguredException()
      : super(
          'Firebase is not configured yet. Add google-services.json to '
          'enable sign-in.',
        );
}

/// The auth contract every screen depends on.
abstract class AuthService {
  /// False until Firebase has been successfully initialized. When false,
  /// the app skips auth gating (legacy dashboard behavior) and auth
  /// screens show the not-configured state.
  bool get isConfigured;

  /// The currently signed-in user, or null. Never throws.
  AuthUser? get currentUser;

  /// Emits the current user whenever the sign-in state changes.
  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> signIn({
    required String email,
    required String password,
  });

  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  });

  /// Sends the Firebase password-reset email.
  Future<void> sendPasswordReset({required String email});

  /// Sends the Firebase email-verification email to the current user.
  Future<void> sendEmailVerification();

  /// Reloads the current user from Firebase (picks up a verified email)
  /// and returns the fresh user, or null when signed out.
  Future<AuthUser?> reloadUser();

  /// Google sign-in for LOGIN ONLY. Returns the Firebase user, or null
  /// when the user canceled the Google flow. The caller (Sign In
  /// screen) must verify an EstudyanteGO profile exists for the UID
  /// and sign out immediately when it does not — this method alone
  /// never creates a profile.
  Future<AuthUser?> signInWithGoogle();

  /// Google sign-up. Same Firebase flow as [signInWithGoogle] (Google
  /// creates the Firebase account when new); the caller (Create
  /// Account screen) creates the UID-keyed EstudyanteGO profile from
  /// the returned user and reuses an existing profile instead of
  /// duplicating it.
  Future<AuthUser?> signUpWithGoogle();

  Future<void> signOut();
}
