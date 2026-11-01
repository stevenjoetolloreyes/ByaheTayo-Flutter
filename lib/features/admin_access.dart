// Admin access for EstudyanteGO (user rule, Nov 1).
//
// ONLY these two emails are admins. The check compares the
// AUTHENTICATED Firebase user's email (FirebaseAuth currentUser.email,
// lowercased) against this allowlist — never an editable profile field
// (profile text is user-editable, so checking it would be a spoofing
// hole), and no UI toggle or setting can grant admin.
//
// Every other signed-in user is a regular user: they can sign in and
// use the app normally. This allowlist gates admin-only surfaces only;
// it is NOT a sign-in blocklist.
import 'onboarding/auth_service.dart';

/// The complete admin allowlist. Do not extend it from UI or settings.
const adminEmails = <String>{
  'stevenjoereyes0625@gmail.com',
  'stevenjoereyes23@gmail.com',
};

/// True when [email] is on the admin allowlist (case-insensitive).
bool isAdminEmail(String? email) {
  if (email == null) return false;
  return adminEmails.contains(email.trim().toLowerCase());
}

/// True when [user] is signed in with an admin email. Takes the
/// authenticated [AuthUser] only — never a [UserProfile], whose fields
/// the user can edit.
bool isAdminUser(AuthUser? user) => isAdminEmail(user?.email);
