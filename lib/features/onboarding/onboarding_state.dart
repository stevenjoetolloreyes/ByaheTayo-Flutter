// First-time / profile state for EstudyanteGO onboarding.
//
// ADDITIVE ONLY: every key here is new. No existing SharedPreferences
// key is read with a new meaning or overwritten. Profiles live in the
// existing on-device SharedPreferences store, keyed by Firebase UID.
// There is no backend profile store in this pass.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../subscription_membership.dart';
import 'auth_service.dart';

/// True once the user finished (or skipped) onboarding. Onboarding is
/// shown only when this is false — i.e. on first install.
const onboardingDoneKey = 'byahetayo_onboarding_done';

/// True once the notification-permission prompt has been shown (either
/// choice). The prompt is shown at most once per install.
const notificationPromptShownKey = 'byahetayo_notification_prompt_shown';

/// True once profile setup completed for this Firebase user.
String profileSetupDoneKey(String uid) =>
    'byahetayo_profile_setup_done_$uid';

/// JSON-encoded [UserProfile] for this Firebase user.
String profileDataKey(String uid) => 'byahetayo_profile_$uid';

/// CONTRACT KEY — the student's school as a plain String, free text.
/// The School Calendar (built separately) reads EXACTLY this key to
/// decide which built-in school calendar to show; it never reads the
/// per-UID profile JSON for the school. [ProfileStore.saveProfile]
/// writes this key on every save, so the Profile Setup field and the
/// Account page's Student Information section always show the same
/// value. Empty string means "no school set" (valid: the calendar
/// then shows a prompt to set it in Account, plus nationwide
/// holidays). No school names are ever seeded or pre-filled here.
const profileSchoolKey = 'byahetayo_profile_school';

/// Calendar-side rule (informational here; the calendar applies it):
/// the value counts as University of Northern Philippines when the
/// trimmed, lowercased value contains 'unp' or equals
/// 'university of northern philippines'. Any other value (or empty)
/// means "no built-in school calendar" — nationwide holidays plus
/// user-added events only.
bool isUniversityOfNorthernPhilippines(String? school) {
  final normalized = (school ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('unp') ||
      normalized == 'university of northern philippines';
}

/// On-device profile. Student and employment info are optional and stay
/// empty when the user skips them — never invented.
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.email,
    this.photoPath,
    this.photoUrl,
    this.profilePhotoUrl,
    this.photoUploadPending = false,
    this.school,
    this.program,
    this.year,
    this.jobTitle,
    this.company,
    this.plan = SubscriptionPlanId.free,
  });

  final String displayName;
  final String email;
  final String? photoPath;

  /// Google profile photo URL (null unless set by Google sign-up).
  final String? photoUrl;

  /// Download URL of the user's own uploaded photo (Firebase
  /// Storage `profile_photos/<uid>.jpg`, stored in Firestore
  /// `student_profiles/<uid>.profilePhotoUrl`). Null until the user
  /// picks a photo and it uploads successfully. This is SEPARATE
  /// from [photoUrl] on purpose: a Google re-sign-in must never
  /// overwrite the custom photo, and a custom photo must override
  /// the Google avatar (see profile_avatar.dart).
  final String? profilePhotoUrl;

  /// True when a local photo exists that has NOT been uploaded yet
  /// (picked while offline, or an earlier upload failed). Local-only
  /// bookkeeping — never sent to Firestore. The save path and the
  /// restore path retry the upload while this is true; a successful
  /// upload clears it. Without this flag, a photo picked offline
  /// with an older remote URL would never be retried.
  final bool photoUploadPending;
  final String? school;
  final String? program;
  final String? year;
  final String? jobTitle;
  final String? company;

  /// Subscription plan, READ-ONLY from the app's side: a cached copy
  /// of the admin-assigned `plan` field on the user's Firestore
  /// `student_profiles` document (see profile_repository.dart). It
  /// is set only by the restore path ([mergeStudentInfo]) and never
  /// by any user-facing flow — no screen in the app changes it.
  /// Defaults to [SubscriptionPlanId.free]; a plan is never invented.
  final SubscriptionPlanId plan;

  bool get hasStudentInfo =>
      (school ?? '').trim().isNotEmpty ||
      (program ?? '').trim().isNotEmpty ||
      (year ?? '').trim().isNotEmpty;

  bool get hasEmploymentInfo =>
      (jobTitle ?? '').trim().isNotEmpty ||
      (company ?? '').trim().isNotEmpty;

  /// Honest initials placeholder (never a fake photo).
  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  UserProfile copyWith({
    String? displayName,
    String? email,
    String? photoPath,
    String? photoUrl,
    String? profilePhotoUrl,
    bool? photoUploadPending,
    String? school,
    String? program,
    String? year,
    String? jobTitle,
    String? company,
    SubscriptionPlanId? plan,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoPath: photoPath ?? this.photoPath,
      photoUrl: photoUrl ?? this.photoUrl,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      photoUploadPending: photoUploadPending ?? this.photoUploadPending,
      school: school ?? this.school,
      program: program ?? this.program,
      year: year ?? this.year,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      plan: plan ?? this.plan,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'email': email,
      'photoPath': photoPath,
      'photoUrl': photoUrl,
      'profilePhotoUrl': profilePhotoUrl,
      'photoUploadPending': photoUploadPending,
      'school': school,
      'program': program,
      'year': year,
      'jobTitle': jobTitle,
      'company': company,
      'plan': plan.name,
    };
  }

  static UserProfile? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final name = json['displayName'];
    final email = json['email'];
    if (name is! String || email is! String) return null;
    return UserProfile(
      displayName: name,
      email: email,
      photoPath: json['photoPath'] as String?,
      photoUrl: json['photoUrl'] as String?,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      photoUploadPending: json['photoUploadPending'] as bool? ?? false,
      school: json['school'] as String?,
      program: json['program'] as String?,
      year: json['year'] as String?,
      jobTitle: json['jobTitle'] as String?,
      company: json['company'] as String?,
      plan: parseSubscriptionPlanId(json['plan']),
    );
  }
}

/// Reads/writes profiles and onboarding flags in SharedPreferences.
class ProfileStore {
  ProfileStore(this._prefs);

  final SharedPreferences _prefs;

  bool get onboardingDone => _prefs.getBool(onboardingDoneKey) ?? false;

  Future<void> markOnboardingDone() =>
      _prefs.setBool(onboardingDoneKey, true);

  bool get notificationPromptShown =>
      _prefs.getBool(notificationPromptShownKey) ?? false;

  Future<void> markNotificationPromptShown() =>
      _prefs.setBool(notificationPromptShownKey, true);

  UserProfile? loadProfile(String uid) {
    final raw = _prefs.getString(profileDataKey(uid));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final profile = UserProfile.fromJson(decoded);
      if (profile == null) return null;
      // The flat contract key is the source of truth for the school:
      // when present it wins over a stale school inside the JSON, so
      // Profile Setup and Account can never disagree. Absent means
      // "written before the contract key existed" — keep the JSON
      // value (it gets migrated to the flat key on the next save).
      final flatSchool = _prefs.getString(profileSchoolKey);
      if (flatSchool == null) return profile;
      return UserProfile(
        displayName: profile.displayName,
        email: profile.email,
        photoPath: profile.photoPath,
        photoUrl: profile.photoUrl,
        profilePhotoUrl: profile.profilePhotoUrl,
        photoUploadPending: profile.photoUploadPending,
        school: flatSchool.isEmpty ? null : flatSchool,
        program: profile.program,
        year: profile.year,
        jobTitle: profile.jobTitle,
        company: profile.company,
        plan: profile.plan,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(String uid, UserProfile profile) async {
    await _prefs.setString(profileDataKey(uid), jsonEncode(profile.toJson()));
    // Keep the calendar contract key in sync on every save (create
    // and edit alike). Empty school clears it — an empty field is
    // valid and means "no school set".
    await _prefs.setString(profileSchoolKey, profile.school ?? '');
  }

  bool isProfileSetupDone(String uid) =>
      _prefs.getBool(profileSetupDoneKey(uid)) ?? false;

  Future<void> markProfileSetupDone(String uid) =>
      _prefs.setBool(profileSetupDoneKey(uid), true);

  /// Removes every local trace of [uid]'s profile: the stored JSON,
  /// the setup-done flag, and the flat school contract key (which is
  /// not UID-scoped — it always holds this user's school). Used by
  /// the My Data account-deletion flow. App settings (theme,
  /// sidebar, notification prefs) are untouched.
  Future<void> clearProfile(String uid) async {
    await _prefs.remove(profileDataKey(uid));
    await _prefs.remove(profileSetupDoneKey(uid));
    await _prefs.remove(profileSchoolKey);
  }
}

/// Where the app should go next. Pure function of its inputs so tests
/// can cover every branch without widgets.
///
/// Order matters: onboarding first (first install only), then — only
/// when Firebase is configured — sign-in, email verification, and
/// profile setup. When Firebase is NOT configured, the app falls back
/// to the dashboard (legacy behavior) so it stays usable before
/// google-services.json is supplied.
enum AppStartDestination {
  onboarding,
  signIn,
  createAccount,
  verifyEmail,
  profileSetup,
  dashboard
}

AppStartDestination resolveStartDestination({
  required bool firebaseConfigured,
  required bool onboardingDone,
  required AuthUser? user,
  required bool profileSetupDone,
}) {
  if (!onboardingDone) return AppStartDestination.onboarding;
  if (!firebaseConfigured) return AppStartDestination.dashboard;
  if (user == null) return AppStartDestination.signIn;
  if (!user.emailVerified) return AppStartDestination.verifyEmail;
  if (!profileSetupDone) return AppStartDestination.profileSetup;
  return AppStartDestination.dashboard;
}
