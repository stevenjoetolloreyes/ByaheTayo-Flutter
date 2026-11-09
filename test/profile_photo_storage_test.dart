// Tests for the profile photo in the database: Firebase Storage
// upload, Firestore URL field, restore/merge rules, display
// priority, and failure handling.
//
// All Firebase calls go through fakes (no live Firebase). The one
// real-network test uses a local loopback HttpServer for the
// download cache.
import 'dart:io';

import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/profile_setup_screen.dart';
import 'package:estudyantego/features/profile_avatar.dart';
import 'package:estudyantego/features/profile_photo_storage.dart';
import 'package:estudyantego/features/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Existing repo image used as a stand-in profile photo.
///
/// NOTE (same rule as student_welcome_avatar_test.dart): async file
/// creation hangs the tester in this sandbox, so tests must never
/// create files — use a real PNG already in the repo instead.
const _localPhoto = 'assets/images/estudyantego_logo.png';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

const _remoteUrl = 'https://example.com/profile_photos/uid-1.jpg';
const _googleUrl = 'https://example.com/google-avatar.jpg';

/// In-memory [ProfilePhotoStorage]: records uploads/caches, returns
/// a fake URL or throws on demand.
class FakeProfilePhotoStorage implements ProfilePhotoStorage {
  final List<String> uploadedUids = [];
  final List<String> cachedUrls = [];

  /// URL returned by [uploadPhoto]; defaults to [_remoteUrl].
  String? uploadUrlToReturn;

  /// When true, [uploadPhoto] throws (offline / Storage disabled /
  /// rules unpublished).
  bool failUpload = false;

  /// Local path returned by [cacheRemotePhoto]; null means the
  /// download "failed" (or was never attempted).
  String? cachePathToReturn;

  @override
  Future<String> uploadPhoto(String uid, File file) async {
    if (failUpload) throw Exception('Simulated Storage failure.');
    uploadedUids.add(uid);
    return uploadUrlToReturn ?? _remoteUrl;
  }

  @override
  Future<String?> cacheRemotePhoto(
    String uid,
    String url, {
    Future<Directory> Function()? documentsDir,
  }) async {
    cachedUrls.add(url);
    return cachePathToReturn;
  }
}

/// In-memory [StudentProfileRepository] (same shape as the fake in
/// student_profile_sync_test.dart).
class FakeStudentProfileRepository implements StudentProfileRepository {
  final Map<String, StudentProfile> docs = {};

  @override
  Future<StudentProfile?> fetchProfile(String uid) async => docs[uid];

  @override
  Future<void> saveProfile(String uid, StudentProfile profile) async {
    docs[uid] = profile;
  }
}

Future<ProfileStore> _freshStore() async {
  final prefs = await SharedPreferences.getInstance();
  return ProfileStore(prefs);
}

UserProfile _localProfile({
  String? photoPath,
  String? profilePhotoUrl,
  bool photoUploadPending = false,
  String? photoUrl,
  String? school = 'University of Northern Philippines',
}) {
  return UserProfile(
    displayName: 'Steven Reyes',
    email: 'steven@example.com',
    photoPath: photoPath,
    profilePhotoUrl: profilePhotoUrl,
    photoUploadPending: photoUploadPending,
    photoUrl: photoUrl,
    school: school,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StudentProfile photo URL mapping', () {
    test('profilePhotoUrl round-trips through fromUserProfile/toDoc/fromDoc',
        () {
      final doc = StudentProfile.fromUserProfile(
        _localProfile(profilePhotoUrl: _remoteUrl),
      ).toDoc();
      expect(doc['profilePhotoUrl'], _remoteUrl);
      final restored = StudentProfile.fromDoc(doc);
      expect(restored?.profilePhotoUrl, _remoteUrl);
    });

    test('fromDoc treats an empty photo URL as missing', () {
      final profile = StudentProfile.fromDoc({'profilePhotoUrl': '  '});
      expect(profile?.profilePhotoUrl, isNull);
    });

    test('photoUploadPending is local-only: never in the remote doc',
        () {
      final doc = StudentProfile.fromUserProfile(
        _localProfile(
          profilePhotoUrl: _remoteUrl,
          photoUploadPending: true,
        ),
      ).toDoc();
      expect(doc.containsKey('photoUploadPending'), isFalse);
    });

    test('UserProfile JSON keeps the new fields (and old JSON reads)',
        () {
      final profile = _localProfile(
        profilePhotoUrl: _remoteUrl,
        photoUploadPending: true,
      );
      final roundTripped =
          UserProfile.fromJson(profile.toJson())!;
      expect(roundTripped.profilePhotoUrl, _remoteUrl);
      expect(roundTripped.photoUploadPending, isTrue);
      // JSON written before this feature has neither key.
      final legacy = UserProfile.fromJson({
        'displayName': 'Steven Reyes',
        'email': 'steven@example.com',
      })!;
      expect(legacy.profilePhotoUrl, isNull);
      expect(legacy.photoUploadPending, isFalse);
    });
  });

  group('mergeStudentInfo with a photo URL', () {
    test('non-empty remote URL wins when local has none', () {
      final merged = mergeStudentInfo(
        _localProfile(),
        const StudentProfile(profilePhotoUrl: _remoteUrl),
      );
      expect(merged.profilePhotoUrl, _remoteUrl);
    });

    test('local URL is kept when the remote field is empty', () {
      final merged = mergeStudentInfo(
        _localProfile(profilePhotoUrl: _remoteUrl),
        const StudentProfile(profilePhotoUrl: ''),
      );
      expect(merged.profilePhotoUrl, _remoteUrl);
    });

    test('photo file and pending flag are untouched by a merge', () async {
      const path = _localPhoto;
      final merged = mergeStudentInfo(
        _localProfile(
          photoPath: path,
          photoUploadPending: true,
          profilePhotoUrl: _remoteUrl,
        ),
        const StudentProfile(
          school: 'MMSU',
          profilePhotoUrl: 'https://example.com/new.jpg',
        ),
      );
      // URL merges like other remote fields; the local file and the
      // pending flag are local-only and survive untouched.
      expect(merged.profilePhotoUrl, 'https://example.com/new.jpg');
      expect(merged.photoPath, path);
      expect(merged.photoUploadPending, isTrue);
    });
  });

  group('resolveProfilePhotoImage priority', () {
    test('local file beats the remote URL and the Google avatar',
        () async {
      const path = _localPhoto;
      final image = resolveProfilePhotoImage(
        _localProfile(
          photoPath: path,
          profilePhotoUrl: _remoteUrl,
          photoUrl: _googleUrl,
        ),
      );
      expect(image, isA<FileImage>());
    });

    test('missing local file falls through to the remote URL', () async {
      final image = resolveProfilePhotoImage(
        _localProfile(
          photoPath: '/no/such/file.jpg',
          profilePhotoUrl: _remoteUrl,
          photoUrl: _googleUrl,
        ),
      );
      expect(image, isA<NetworkImage>());
      expect((image as NetworkImage).url, _remoteUrl);
    });

    test('Google avatar shows only when no custom photo exists', () {
      final image = resolveProfilePhotoImage(
        _localProfile(photoUrl: _googleUrl),
      );
      expect(image, isA<NetworkImage>());
      expect((image as NetworkImage).url, _googleUrl);
    });

    test('no photo at all resolves to null (initials show)', () {
      expect(resolveProfilePhotoImage(_localProfile()), isNull);
      expect(resolveProfilePhotoImage(null), isNull);
    });
  });

  group('restoreStudentProfile with a photo', () {
    test('fresh install + remote URL: URL restores, no local file yet',
        () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: 'University of Northern Philippines',
          profilePhotoUrl: _remoteUrl,
        );
      final storage = FakeProfilePhotoStorage();
      final store = await _freshStore();
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
        photoStorage: storage,
      );
      expect(outcome, ProfileRestoreOutcome.restored);
      final restored = store.loadProfile(_user.uid)!;
      expect(restored.profilePhotoUrl, _remoteUrl);
      // Cache was attempted (fake returns null = download failed);
      // the network URL still shows, and nothing was wiped.
      expect(storage.cachedUrls, [_remoteUrl]);
      expect(restored.photoPath, isNull);
    });

    test('fresh install + remote URL: successful cache sets the file',
        () async {
      const cachePath = _localPhoto;
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          profilePhotoUrl: _remoteUrl,
        );
      final storage = FakeProfilePhotoStorage()
        ..cachePathToReturn = cachePath;
      final store = await _freshStore();
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
        photoStorage: storage,
      );
      final restored = store.loadProfile(_user.uid)!;
      expect(restored.profilePhotoUrl, _remoteUrl);
      expect(restored.photoPath, cachePath);
    });

    test('pending local photo uploads on sign-in (backfill)', () async {
      const path = _localPhoto;
      final repo = FakeStudentProfileRepository();
      final storage = FakeProfilePhotoStorage();
      final store = await _freshStore();
      await store.saveProfile(
        _user.uid,
        _localProfile(
          photoPath: path,
          photoUploadPending: true,
          school: null,
        ),
      );
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
        photoStorage: storage,
      );
      expect(storage.uploadedUids, [_user.uid]);
      expect(outcome, ProfileRestoreOutcome.backfilled);
      expect(repo.docs[_user.uid]?.profilePhotoUrl, _remoteUrl);
      final saved = store.loadProfile(_user.uid)!;
      expect(saved.profilePhotoUrl, _remoteUrl);
      expect(saved.photoUploadPending, isFalse);
      expect(saved.photoPath, path);
    });

    test('old local photo with no URL migrates on sign-in', () async {
      // A photo saved before this feature: file exists, no URL,
      // pending flag false (old JSON). The next sign-in must still
      // upload it — otherwise Steven's existing photo would never
      // reach the database.
      const path = _localPhoto;
      final repo = FakeStudentProfileRepository();
      final storage = FakeProfilePhotoStorage();
      final store = await _freshStore();
      await store.saveProfile(
        _user.uid,
        _localProfile(photoPath: path, school: null),
      );
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
        photoStorage: storage,
      );
      expect(storage.uploadedUids, [_user.uid]);
      expect(repo.docs[_user.uid]?.profilePhotoUrl, _remoteUrl);
      expect(store.loadProfile(_user.uid)?.photoUploadPending, isFalse);
    });

    test('already-synced photo is NOT re-uploaded on sign-in', () async {
      const path = _localPhoto;
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          profilePhotoUrl: _remoteUrl,
        );
      final storage = FakeProfilePhotoStorage();
      final store = await _freshStore();
      await store.saveProfile(
        _user.uid,
        _localProfile(
          photoPath: path,
          profilePhotoUrl: _remoteUrl,
          school: null,
        ),
      );
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
        photoStorage: storage,
      );
      expect(storage.uploadedUids, isEmpty);
      expect(storage.cachedUrls, isEmpty);
    });

    test('upload failure keeps the local photo and stays pending',
        () async {
      const path = _localPhoto;
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: 'University of Northern Philippines',
        );
      final storage = FakeProfilePhotoStorage()..failUpload = true;
      final store = await _freshStore();
      await store.saveProfile(
        _user.uid,
        _localProfile(photoPath: path, photoUploadPending: true),
      );
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
        photoStorage: storage,
      );
      // The student info still restored; the photo just retries
      // next time. Local file intact, pending flag intact.
      expect(outcome, ProfileRestoreOutcome.restored);
      final saved = store.loadProfile(_user.uid)!;
      expect(saved.photoPath, path);
      expect(saved.photoUploadPending, isTrue);
      expect(saved.profilePhotoUrl, isNull);
      expect(repo.docs[_user.uid]?.profilePhotoUrl, isNull);
    });
  });

  group('ProfileSetupScreen save path with a photo', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: child));

    Future<void> tapSave(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      // Top popup (was a SnackBar): several short pumps let the
      // save finish over a few frames while keeping the popup up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('edit save uploads the photo and stores its URL',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      final repo = FakeStudentProfileRepository();
      final storage = FakeProfilePhotoStorage();
      const path = _localPhoto;
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          profileRepository: repo,
          photoStorage: storage,
          initial: _localProfile(
            photoPath: path,
            photoUploadPending: true,
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));
      await tapSave(tester);
      expect(storage.uploadedUids, [_user.uid]);
      expect(saved, isNotNull);
      expect(saved?.profilePhotoUrl, _remoteUrl);
      expect(saved?.photoUploadPending, isFalse);
      expect(repo.docs[_user.uid]?.profilePhotoUrl, _remoteUrl);
      // Local store carries the URL too.
      expect(store.loadProfile(_user.uid)?.profilePhotoUrl, _remoteUrl);
      expect(find.textContaining('could not upload'), findsNothing);
    });

    testWidgets('upload failure: local save succeeds, honest error, '
        'still completes, pending stays true', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      final repo = FakeStudentProfileRepository();
      final storage = FakeProfilePhotoStorage()..failUpload = true;
      const path = _localPhoto;
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          profileRepository: repo,
          photoStorage: storage,
          initial: _localProfile(
            photoPath: path,
            photoUploadPending: true,
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tapSave(tester);
      // Local save intact and the flow completes (never trapped).
      expect(saved, isNotNull);
      expect(saved?.photoUploadPending, isTrue);
      expect(saved?.photoPath, path);
      expect(store.loadProfile(_user.uid)?.photoPath, path);
      // The doc still saved (without a URL) — the photo retries
      // on the next sign-in, the student info is not held hostage.
      expect(repo.docs[_user.uid]?.school,
          'University of Northern Philippines');
      expect(repo.docs[_user.uid]?.profilePhotoUrl, isNull);
      expect(find.textContaining('could not upload'), findsOneWidget);
    });

    testWidgets('already-synced photo is not re-uploaded on save',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      final repo = FakeStudentProfileRepository();
      final storage = FakeProfilePhotoStorage();
      const path = _localPhoto;
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          profileRepository: repo,
          photoStorage: storage,
          initial: _localProfile(
            photoPath: path,
            profilePhotoUrl: _remoteUrl,
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(storage.uploadedUids, isEmpty);
      expect(saved?.profilePhotoUrl, _remoteUrl);
      expect(repo.docs[_user.uid]?.profilePhotoUrl, _remoteUrl);
    });

    testWidgets('null photo storage means local-only (no crash)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      final repo = FakeStudentProfileRepository();
      const path = _localPhoto;
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          profileRepository: repo,
          photoStorage: null,
          initial: _localProfile(
            photoPath: path,
            photoUploadPending: true,
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));
      await tapSave(tester);
      expect(saved, isNotNull);
      expect(saved?.photoUploadPending, isTrue);
      expect(find.textContaining('could not upload'), findsNothing);
    });
  });

  group('FirebaseProfilePhotoStorage.cacheRemotePhoto (real download)',
      () {
    test('downloads bytes to the documents path; 404 returns null',
        () async {
      // flutter_test replaces HttpClient with a mock that answers
      // 400 to everything, so the real download needs the real
      // client back for this test only, via a zone override.
      final bytes = File(_localPhoto).readAsBytesSync();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/photo.jpg') {
          request.response.headers.contentType =
              ContentType('image', 'jpeg');
          request.response.add(bytes);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      // Documents dir is the existing system temp dir (no
      // createTemp — async file creation hangs the tester here).
      final tmp = Directory.systemTemp;
      try {
        final storage = FirebaseProfilePhotoStorage();
        final url = 'http://127.0.0.1:${server.port}/photo.jpg';
        final path = await HttpOverrides.runWithHttpOverrides(
          () => storage.cacheRemotePhoto(
            'uid-1',
            url,
            documentsDir: () async => tmp,
          ),
          _RealHttpOverrides(),
        );
        expect(path, isNotNull);
        expect(path, endsWith('byahetayo_profile_uid-1.jpg'));
        expect(File(path!).readAsBytesSync(), bytes);
        final missing = await HttpOverrides.runWithHttpOverrides(
          () => storage.cacheRemotePhoto(
            'uid-1',
            'http://127.0.0.1:${server.port}/nope.jpg',
            documentsDir: () async => tmp,
          ),
          _RealHttpOverrides(),
        );
        expect(missing, isNull);
      } finally {
        await server.close(force: true);
        // Best-effort cleanup of the cached file (sync delete).
        try {
          File('${tmp.path}/byahetayo_profile_uid-1.jpg')
              .deleteSync();
        } catch (_) {}
      }
    });
  });
}

/// Restores the real [HttpClient] (flutter_test mocks it to answer
/// 400 to everything). Used by the one test that downloads real
/// bytes from a loopback server. No methods are overridden: simply
/// installing this class in the zone replaces the test binding's
/// mock with the base class's real client.
class _RealHttpOverrides extends HttpOverrides {}
