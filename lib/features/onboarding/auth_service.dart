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
/// [code] is the raw Firebase error code when one is known
/// ('wrong-password', 'invalid-credential', 'too-many-requests',
/// ...), so callers that record failures (Login History) can label
/// the reason honestly without parsing the user-facing message.
/// Null when there is no Firebase code (generic failures).
class AuthException implements Exception {
  const AuthException(this.message, {this.code});

  final String message;
  final String? code;

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

  /// Sign-in methods for the current user (provider IDs, e.g.
  /// 'password' or 'google.com'). Empty when signed out. Used by
  /// the My Data delete flow to offer the right re-authentication
  /// step — a password account re-auths with its password, a Google
  /// account with a fresh Google sign-in.
  Future<List<String>> signInMethods();

  /// Re-authenticates the current user with their account password.
  /// Throws [AuthException] on a wrong password. Required
  /// immediately before [deleteCurrentUser]: Firebase only deletes
  /// a user whose sign-in is recent.
  Future<void> reauthenticateWithPassword({required String password});

  /// Re-authenticates the current user with a fresh Google sign-in
  /// (account chooser). Throws [AuthException] when the flow is
  /// canceled or the Google account does not match the signed-in
  /// user. Required immediately before [deleteCurrentUser] for
  /// Google accounts.
  Future<void> reauthenticateWithGoogle();

  /// Deletes the currently signed-in Firebase user, permanently.
  /// The caller must have re-authenticated immediately before
  /// ([reauthenticateWithPassword] / [reauthenticateWithGoogle]);
  /// otherwise Firebase throws requires-recent-login and this
  /// reports it as an [AuthException] asking to sign in again.
  /// Callers delete the user's Firestore documents, Storage files
  /// and local data FIRST — this is the last step.
  Future<void> deleteCurrentUser();

  Future<void> signOut();
}
