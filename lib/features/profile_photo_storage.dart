// Firebase Storage upload for the user's own profile photo.
//
// The profile photo used to be local-only: the picked file is copied
// into the app documents folder and only its path is stored. After a
// reinstall or clear-data the photo was gone — Firestore never stored
// it. This file owns the remote side:
//
//   Storage path: `profile_photos/<uid>.jpg` (one file per user —
//     a new pick overwrites the old one; the download URL is
//     re-fetched after every upload and stored in Firestore
//     `student_profiles/<uid>.profilePhotoUrl`, see
//     profile_repository.dart).
//   Display priority (see profile_avatar.dart): local file →
//     uploaded remote URL → Google avatar URL → initials.
//
// The upload is best-effort by design: it must never block the
// local save, and a failure is retried on the next save / sign-in
// (see `photoUploadPending` on [UserProfile]). Storage may not even
// be enabled in the Firebase project yet — the app keeps working
// locally and says so honestly.
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Storage path for a user's profile photo (one file per user).
String profilePhotoStoragePath(String uid) => 'profile_photos/$uid.jpg';

/// Local documents path the picked photo is copied to (the same path
/// the profile setup screen has always used).
String localProfilePhotoPath(String documentsDir, String uid) =>
    '$documentsDir/byahetayo_profile_$uid.jpg';

/// Uploads / caches profile photos. Tests use a fake; production
/// uses [FirebaseProfilePhotoStorage].
abstract class ProfilePhotoStorage {
  /// Uploads [file] to `profile_photos/<uid>.jpg` and returns its
  /// download URL. Throws on failure (offline, Storage not enabled,
  /// rules unpublished) — callers treat that as "try again later",
  /// never as a reason to blank local data.
  Future<String> uploadPhoto(String uid, File file);

  /// Downloads the photo at [url] into the app documents folder as
  /// `byahetayo_profile_<uid>.jpg` and returns its local path, or
  /// null when the download fails. Best-effort only: a null result
  /// just means the network image is shown instead.
  ///
  /// [documentsDir] overrides where the file is written (tests pass
  /// a temp dir; production uses the app documents folder).
  Future<String?> cacheRemotePhoto(
    String uid,
    String url, {
    Future<Directory> Function()? documentsDir,
  });
}

/// Firebase implementation of [ProfilePhotoStorage].
class FirebaseProfilePhotoStorage implements ProfilePhotoStorage {
  const FirebaseProfilePhotoStorage();

  FirebaseStorage get _storage => FirebaseStorage.instance;

  @override
  Future<String> uploadPhoto(String uid, File file) async {
    final ref = _storage.ref(profilePhotoStoragePath(uid));
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  @override
  Future<String?> cacheRemotePhoto(
    String uid,
    String url, {
    Future<Directory> Function()? documentsDir,
  }) async {
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) return null;
        final bytes = await response.fold<List<int>>(
          <int>[],
          (previous, element) => previous..addAll(element),
        );
        if (bytes.isEmpty) return null;
        final docs = await (documentsDir?.call() ??
            getApplicationDocumentsDirectory());
        final target = File(localProfilePhotoPath(docs.path, uid));
        await target.writeAsBytes(bytes, flush: true);
        return target.path;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// User-facing message for a profile-photo upload failure. Storage
/// errors surface their message (e.g. permission-denied while the
/// rules are unpublished); anything else falls back to a generic
/// honest line. Mirrors `studentProfileSyncErrorMessage`.
String profilePhotoUploadErrorMessage(Object error) {
  if (error is FirebaseException) {
    final message = error.message;
    if (message != null && message.trim().isNotEmpty) return message.trim();
    return 'Storage error (${error.code}).';
  }
  return 'Could not reach photo storage.';
}
