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
//     profilePhotoUrl (nullable string — the Firebase Storage
//     download URL of the user's own uploaded photo), updatedAt
//     (server timestamp), plan (string: 'free' / 'standard' / 'pro',
//     ADMIN-ASSIGNED ONLY — see [StudentProfile.plan]).
//   Never stored here: passwords, tokens, secrets, photo BYTES.
//     The photo itself lives in Firebase Storage
//     (`profile_photos/<uid>.jpg`, see profile_photo_storage.dart);
//     only its download URL is stored here.
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
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'profile_photo_storage.dart';
import 'subscription_membership.dart';

/// Firestore collection for student profiles.
const studentProfilesCollection = 'student_profiles';

/// The student-information half of a [UserProfile]: the fields that
/// used to be local-only, plus the uploaded photo URL. Display name /
/// email live in Firebase Auth and are intentionally NOT duplicated
/// here. The local photo FILE ([UserProfile.photoPath]) and the
/// pending-upload flag are local-only and are never sent here.
class StudentProfile {
  const StudentProfile({
    this.school,
    this.program,
    this.yearLevel,
    this.profilePhotoUrl,
    this.plan = SubscriptionPlanId.free,
  });

  final String? school;
  final String? program;
  final String? yearLevel;

  /// Download URL of the user's uploaded photo (Firebase Storage
  /// `profile_photos/<uid>.jpg`). Null until the first successful
  /// upload. The Google avatar ([UserProfile.photoUrl]) is a
  /// different field and is never stored here.
  final String? profilePhotoUrl;

  /// Subscription plan, READ-ONLY from the app's side. The admin
  /// (Steven) assigns it by setting the `plan` field on the user's
  /// `student_profiles` document in the Firebase Console — the app
  /// never writes it ([toDoc] deliberately omits it, so a backfill
  /// or photo-upload save can never create, change, or clear it).
  /// Missing or unknown values parse to [SubscriptionPlanId.free]
  /// via [parseSubscriptionPlanId]; a plan is never invented.
  final SubscriptionPlanId plan;

  bool get hasStudentInfo =>
      (school ?? '').trim().isNotEmpty ||
      (program ?? '').trim().isNotEmpty ||
      (yearLevel ?? '').trim().isNotEmpty;

  /// Builds the remote profile from a local [UserProfile] (used by
  /// the save path and by backfill). The plan is deliberately NOT
  /// copied here: the app never writes the plan, and [toDoc] omits
  /// it, so a save can never overwrite the admin-assigned value.
  static StudentProfile fromUserProfile(UserProfile profile) {
    return StudentProfile(
      school: profile.school,
      program: profile.program,
      yearLevel: profile.year,
      profilePhotoUrl: profile.profilePhotoUrl,
    );
  }

  Map<String, dynamic> toDoc() {
    // NOTE: no 'plan' key — the plan is admin-assigned in the
    // Firebase Console and the app must never write it. Every save
    // (backfill, photo-upload sync) goes through here, so omitting
    // it here guarantees the app can never create, change, or
    // clear a user's plan.
    return {
      'school': school,
      'program': program,
      'yearLevel': yearLevel,
      'profilePhotoUrl': profilePhotoUrl,
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
      profilePhotoUrl: stringOrNull(data['profilePhotoUrl']),
      plan: parseSubscriptionPlanId(data['plan']),
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
/// fields keep the local value. Display name, email, employment
/// info, the local photo file, and the pending-upload flag are
/// untouched (they are not remote fields). The uploaded photo URL
/// merges like the other remote fields: a non-empty remote URL wins
/// (it is always the newest successful upload); the local FILE still
/// wins at display time (see profile_avatar.dart), and a pending
/// local pick is re-uploaded by [_syncPhotoOnRestore] right after
/// this merge, so an older remote URL can never permanently shadow a
/// newer local photo.
///
/// The plan is the ONE exception to the "non-empty remote wins"
/// rule: the remote plan ALWAYS wins, even when it is `free`
/// (missing field → `free`). The plan is admin-assigned, never
/// user-edited, so the local value is only a cache of the remote
/// one — there is no local value to protect, and an admin who
/// clears the field (or never set it) means the user is Free.
UserProfile mergeStudentInfo(UserProfile local, StudentProfile remote) {
  String? pick(String? remoteValue, String? localValue) {
    final trimmed = (remoteValue ?? '').trim();
    return trimmed.isNotEmpty ? remoteValue : localValue;
  }

  return local.copyWith(
    school: pick(remote.school, local.school),
    program: pick(remote.program, local.program),
    year: pick(remote.yearLevel, local.year),
    profilePhotoUrl: pick(remote.profilePhotoUrl, local.profilePhotoUrl),
    plan: remote.plan,
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
///    fresh profile built from Firebase Auth when local is empty).
/// 3. If it does not exist but local student info does: upload the
///    local student info once (backfill for pre-fix, local-only
///    users) so the next install restores it.
/// 4. Photo sync ([_syncPhotoOnRestore]): a local photo that never
///    uploaded (or an old local photo that predates this feature)
///    is uploaded now; a missing local file with a remote URL is
///    cached for offline use. A photo failure never changes the
///    outcome of steps 1–3 and never wipes local data.
/// 5. Save the merged profile locally (which writes the flat
///    `byahetayo_profile_school` key too). A successful restore
///    marks profile setup done; a backfill leaves the flag as-is.
Future<ProfileRestoreOutcome> restoreStudentProfile({
  required ProfileStore store,
  required StudentProfileRepository? repository,
  required AuthUser user,
  ProfilePhotoStorage photoStorage = const FirebaseProfilePhotoStorage(),
}) async {
  if (repository == null) return ProfileRestoreOutcome.localOnly;
  try {
    final remote = await repository.fetchProfile(user.uid);
    final local = store.loadProfile(user.uid);
    UserProfile? working;
    var outcome = ProfileRestoreOutcome.localOnly;
    if (remote != null) {
      final base = local ??
          UserProfile(
            displayName: user.displayName ?? user.email.split('@').first,
            email: user.email,
          );
      working = mergeStudentInfo(base, remote);
      outcome = ProfileRestoreOutcome.restored;
    } else if (local != null && local.hasStudentInfo) {
      await repository.saveProfile(
        user.uid,
        StudentProfile.fromUserProfile(local),
      );
      working = local;
      outcome = ProfileRestoreOutcome.backfilled;
    } else {
      working = local;
    }
    if (working != null) {
      final synced = await _syncPhotoOnRestore(
        repository: repository,
        user: user,
        profile: working,
        photoStorage: photoStorage,
      );
      working = synced.profile;
      // A photo upload that created the remote document upgrades a
      // would-be `localOnly` to `backfilled` (local data reached the
      // server). It never downgrades `restored` / `backfilled`.
      if (synced.uploadedToRemote &&
          outcome == ProfileRestoreOutcome.localOnly) {
        outcome = ProfileRestoreOutcome.backfilled;
      }
      await store.saveProfile(user.uid, working);
      if (remote != null) {
        await store.markProfileSetupDone(user.uid);
      }
    }
    return outcome;
  } catch (_) {
    return ProfileRestoreOutcome.localOnly;
  }
}

/// Result of the photo half of a restore: the (possibly updated)
/// profile, plus whether a photo upload created/updated the remote
/// document.
class _PhotoSyncResult {
  const _PhotoSyncResult(this.profile, {this.uploadedToRemote = false});

  final UserProfile profile;
  final bool uploadedToRemote;
}

/// Photo half of [restoreStudentProfile]. Never throws and never
/// wipes local data — every step is guarded, and a failure just
/// leaves the photo exactly as it was (the next sign-in retries).
///
/// Local-vs-remote rule: the local FILE always wins at display time
/// (see profile_avatar.dart), so the only question here is whether
/// the server has the matching URL yet. An upload is attempted when
/// a local photo file exists and EITHER the upload is still pending
/// (picked while offline, or an earlier upload failed) OR no remote
/// URL is stored yet (an old local photo that predates this
/// feature — the migration case). A successful upload writes the
/// fresh URL to the remote document immediately.
Future<_PhotoSyncResult> _syncPhotoOnRestore({
  required StudentProfileRepository repository,
  required AuthUser user,
  required UserProfile profile,
  required ProfilePhotoStorage photoStorage,
}) async {
  var working = profile;
  var uploaded = false;
  try {
    final photoPath = working.photoPath;
    final hasLocalFile =
        photoPath != null && File(photoPath).existsSync();
    final remoteUrl = (working.profilePhotoUrl ?? '').trim();
    if (hasLocalFile &&
        (working.photoUploadPending || remoteUrl.isEmpty)) {
      try {
        final url =
            await photoStorage.uploadPhoto(user.uid, File(photoPath));
        // Only clear the pending flag AFTER the remote document
        // confirms the new URL: if this save throws, the local
        // profile keeps pending=true and the next sign-in retries
        // (otherwise the URL would live only locally, marked synced,
        // and never reach the server).
        final uploadedProfile = working.copyWith(
          profilePhotoUrl: url,
          photoUploadPending: false,
        );
        await repository.saveProfile(
          user.uid,
          StudentProfile.fromUserProfile(uploadedProfile),
        );
        working = uploadedProfile;
        uploaded = true;
      } catch (_) {
        // Still pending — local photo stays, next sign-in retries.
        // (The flag stays true, so the next save / sign-in retries.)
      }
    } else if (!hasLocalFile && remoteUrl.isNotEmpty) {
      // No local file, but the server has a photo: show it from the
      // network (the display falls back to the URL) and
      // opportunistically cache it for offline use.
      try {
        final cached =
            await photoStorage.cacheRemotePhoto(user.uid, remoteUrl);
        if (cached != null) {
          working = working.copyWith(photoPath: cached);
        }
      } catch (_) {
        // Cache is best-effort; the network image still shows.
      }
    }
  } catch (_) {
    // Photo sync never blocks login or wipes local data.
  }
  return _PhotoSyncResult(working, uploadedToRemote: uploaded);
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
