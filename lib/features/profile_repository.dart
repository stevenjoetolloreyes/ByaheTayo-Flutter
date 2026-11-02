// Server-side student profile persistence — Firestore.
//
// PROBLEM THIS FIXES: student information (school, program, year
// level) used to live ONLY in ProfileStore (UID-keyed
// SharedPreferences). After a reinstall or a clear-data, profile
// setup reappeared with empty School / Program / Year fields — the
// full name and email survived only because they come from Firebase
// Auth, not from the local store.
//
// This file owns the remote side, mirroring the existing
// community_post_repository.dart pattern (repository abstraction +
// Firestore implementation + in-memory fake in tests):
//
//   Collection: `student_profiles`
//   Document ID: the authenticated Firebase UID (ONE document per
//     user — this is what guarantees no duplicates: every save for a
//     UID overwrites that UID's document, never creates a second one).
//   Fields: school, program, yearLevel (all nullable strings),
//     updatedAt (server timestamp).
//   Never stored here: passwords, tokens, secrets, photos.
//
// LOCAL STORE ROLE CHANGE: ProfileStore stays, but only as an offline
// cache. Every explicit save writes local AND remote; every
// authenticated start restores remote INTO local (per-field merge
// below). Login is never blocked by a profile-fetch failure.
//
// MERGE RULE (spec): only non-empty remote values overwrite local
// values. An empty or missing remote field must NEVER blank a
// non-empty local value. After the first successful sync, remote is
// the source of truth on login — but a remote write that failed (e.g.
// offline) leaves the local value intact, and the next authenticated
// start backfills it (see [restoreStudentProfile]).
//
// COMPLETION RULE (preserves the existing gate): the gate keys off
// the `byahetayo_profile_setup_done_<uid>` flag, not off individual
// fields — student info is optional on the setup screen, so a user
// who deliberately left it empty must not be trapped in setup
// forever. A remote document proves setup was completed on some
// install, so a successful restore marks the flag done and the gate
// proceeds to the dashboard. When no remote document exists, the
// setup screen shows with whatever local data exists (possibly
// empty) — never a blank screen while a fetch is still pending: the
// splash covers the fetch, and failures fall back to local data.
//
// CONTRACT KEY (critical, preserved exactly): every save AND every
// restore goes through ProfileStore.saveProfile, which writes the
// flat key `byahetayo_profile_school` on every call (empty writes
// ''). The School Calendar reads exactly that key.
import 'package:cloud_firestore/cloud_firestore.dart';

import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';

/// Firestore collection for student profiles.
const studentProfilesCollection = 'student_profiles';

/// The student-information half of a [UserProfile]: the three fields
/// that used to be local-only. Display name / email live in Firebase
/// Auth and are intentionally NOT duplicated here.
class StudentProfile {
  const StudentProfile({this.school, this.program, this.yearLevel});

  final String? school;
  final String? program;
  final String? yearLevel;

  bool get hasStudentInfo =>
      (school ?? '').trim().isNotEmpty ||
      (program ?? '').trim().isNotEmpty ||
      (yearLevel ?? '').trim().isNotEmpty;

  /// Builds the remote profile from a local [UserProfile] (used by
  /// the save path and by backfill).
  static StudentProfile fromUserProfile(UserProfile profile) {
    return StudentProfile(
      school: profile.school,
      program: profile.program,
      yearLevel: profile.year,
    );
  }

  Map<String, dynamic> toDoc() {
    return {
      'school': school,
      'program': program,
      'yearLevel': yearLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static StudentProfile? fromDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    String? stringOrNull(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    return StudentProfile(
      school: stringOrNull(data['school']),
      program: stringOrNull(data['program']),
      yearLevel: stringOrNull(data['yearLevel']),
    );
  }
}

/// Remote student-profile storage. Tests use an in-memory fake;
/// production uses [FirestoreStudentProfileRepository].
abstract class StudentProfileRepository {
  /// The remote profile for [uid], or null when no document exists.
  /// Throws on Firestore errors — callers decide how to surface them
  /// (the restore path swallows them; the save path shows them).
  Future<StudentProfile?> fetchProfile(String uid);

  /// Overwrites the [uid] document with [profile] (full set, not
  /// merge — so a locally cleared field actually clears remotely
  /// instead of resurrecting the old value).
  Future<void> saveProfile(String uid, StudentProfile profile);
}

/// Firestore implementation of [StudentProfileRepository].
class FirestoreStudentProfileRepository implements StudentProfileRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection(studentProfilesCollection).doc(uid);

  @override
  Future<StudentProfile?> fetchProfile(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists) return null;
    return StudentProfile.fromDoc(snap.data());
  }

  @override
  Future<void> saveProfile(String uid, StudentProfile profile) async {
    await _doc(uid).set(profile.toDoc());
  }
}

/// Per-field merge of a remote profile into a local [UserProfile]:
/// only non-empty remote values overwrite; empty or missing remote
/// fields keep the local value. Display name, email, photo, and
/// employment info are untouched (they are not remote fields).
UserProfile mergeStudentInfo(UserProfile local, StudentProfile remote) {
  String? pick(String? remoteValue, String? localValue) {
    final trimmed = (remoteValue ?? '').trim();
    return trimmed.isNotEmpty ? remoteValue : localValue;
  }

  return local.copyWith(
    school: pick(remote.school, local.school),
    program: pick(remote.program, local.program),
    year: pick(remote.yearLevel, local.year),
  );
}

/// What [restoreStudentProfile] did. Login proceeds in every case —
/// the outcome only describes where the data came from.
enum ProfileRestoreOutcome {
  /// A remote document existed: it was merged into the local store
  /// and the profile-setup flag was marked done.
  restored,

  /// No remote document existed, but local student info did: it was
  /// uploaded once so the next install restores it.
  backfilled,

  /// No repository, no remote document and nothing to backfill, or
  /// the fetch failed: local data is untouched, login proceeds.
  localOnly,
}

/// Restores the server-side student profile into the local store on
/// authenticated start / login. NEVER throws: any failure (not
/// configured, signed out, network, missing database, unpublished
/// rules) leaves local data untouched and returns
/// [ProfileRestoreOutcome.localOnly], so login is never blocked by a
/// profile-fetch failure.
///
/// Order:
/// 1. Fetch the remote document for [user.uid].
/// 2. If it exists: per-field merge into the local profile (or a
///    fresh profile built from Firebase Auth when local is empty),
///    save locally (which writes the flat `byahetayo_profile_school`
///    key too), and mark profile setup done.
/// 3. If it does not exist but local student info does: upload the
///    local student info once (backfill for pre-fix, local-only
///    users) so the next install restores it. Local data is
///    unchanged and the setup flag is left as-is.
/// 4. Otherwise: do nothing.
Future<ProfileRestoreOutcome> restoreStudentProfile({
  required ProfileStore store,
  required StudentProfileRepository? repository,
  required AuthUser user,
}) async {
  if (repository == null) return ProfileRestoreOutcome.localOnly;
  try {
    final remote = await repository.fetchProfile(user.uid);
    if (remote != null) {
      final local = store.loadProfile(user.uid);
      final base = local ??
          UserProfile(
            displayName: user.displayName ?? user.email.split('@').first,
            email: user.email,
          );
      final merged = mergeStudentInfo(base, remote);
      await store.saveProfile(user.uid, merged);
      await store.markProfileSetupDone(user.uid);
      return ProfileRestoreOutcome.restored;
    }
    final local = store.loadProfile(user.uid);
    if (local != null && local.hasStudentInfo) {
      await repository.saveProfile(
        user.uid,
        StudentProfile.fromUserProfile(local),
      );
      return ProfileRestoreOutcome.backfilled;
    }
    return ProfileRestoreOutcome.localOnly;
  } catch (_) {
    return ProfileRestoreOutcome.localOnly;
  }
}

/// User-facing message for a student-profile sync failure. Firestore
/// errors surface their message (e.g. permission-denied while the
/// rules are unpublished); anything else falls back to a generic
/// honest line.
String studentProfileSyncErrorMessage(Object error) {
  if (error is FirebaseException) {
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message.trim();
    return 'Firestore error (${error.code}).';
  }
  return 'Could not reach the profile database.';
}
