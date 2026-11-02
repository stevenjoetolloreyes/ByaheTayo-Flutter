// Tests for server-side student profile persistence + restoration.
//
// Covers the user's cases with fakes only (no live Firebase):
//   A. save persists to remote
//   B. logout/login restores all fields
//   C. all fields restored incl. school/program/year
//   D. cleared app data + login restores (fresh local store)
//   E. uninstall/reinstall + login restores (fresh local store, same UID)
//   F. same profile restored, no duplicate document
// plus: remote-empty never blanks local, remote-missing keeps local,
// network failure never blocks login, backfill uploads local-only
// profiles, and the profile-setup save path writes remote (with an
// honest error + intact local data when the remote write fails).
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/profile_setup_screen.dart';
import 'package:estudyantego/features/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

const _school = 'University of Northern Philippines';
const _program = 'BSIT – Bachelor of Science in Information Technology';
const _year = '3rd Year';

/// In-memory [StudentProfileRepository]: one document per UID, so a
/// second save for the same UID overwrites (never duplicates).
class FakeStudentProfileRepository implements StudentProfileRepository {
  final Map<String, StudentProfile> docs = {};
  int saveCount = 0;

  /// When true, [fetchProfile] throws, simulating a network failure.
  bool failFetch = false;

  /// When true, [saveProfile] throws, simulating a Firestore failure
  /// (e.g. rules not yet published).
  bool failSave = false;

  @override
  Future<StudentProfile?> fetchProfile(String uid) async {
    if (failFetch) throw Exception('Simulated network failure.');
    return docs[uid];
  }

  @override
  Future<void> saveProfile(String uid, StudentProfile profile) async {
    if (failSave) throw Exception('Simulated Firestore failure.');
    docs[uid] = profile;
    saveCount++;
  }
}

Future<ProfileStore> _freshStore() async {
  final prefs = await SharedPreferences.getInstance();
  return ProfileStore(prefs);
}

UserProfile _localProfile({
  String? school = _school,
  String? program = _program,
  String? year = _year,
}) {
  return UserProfile(
    displayName: 'Steven Reyes',
    email: 'steven@example.com',
    school: school,
    program: program,
    year: year,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('mergeStudentInfo', () {
    test('non-empty remote values overwrite local values', () {
      final merged = mergeStudentInfo(
        _localProfile(),
        const StudentProfile(
          school: 'MMSU',
          program: 'BSCS',
          yearLevel: '2nd Year',
        ),
      );
      expect(merged.school, 'MMSU');
      expect(merged.program, 'BSCS');
      expect(merged.year, '2nd Year');
    });

    test('empty or missing remote fields never blank local values', () {
      final merged = mergeStudentInfo(
        _localProfile(),
        const StudentProfile(school: '', program: null, yearLevel: '  '),
      );
      expect(merged.school, _school);
      expect(merged.program, _program);
      expect(merged.year, _year);
    });

    test('untouched fields (name, email, employment) survive a merge', () {
      final merged = mergeStudentInfo(
        _localProfile().copyWith(jobTitle: 'Cashier', company: 'Shop'),
        const StudentProfile(school: 'MMSU'),
      );
      expect(merged.displayName, 'Steven Reyes');
      expect(merged.email, 'steven@example.com');
      expect(merged.jobTitle, 'Cashier');
      expect(merged.company, 'Shop');
    });
  });

  group('restoreStudentProfile', () {
    test('B/C: logout/login restores all fields incl. school/program/year',
        () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: _school,
          program: _program,
          yearLevel: _year,
        );
      final store = await _freshStore();
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.restored);
      final restored = store.loadProfile(_user.uid);
      expect(restored?.school, _school);
      expect(restored?.program, _program);
      expect(restored?.year, _year);
      // Contract key written on restore (School Calendar reads it).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(profileSchoolKey), _school);
      // Restored profile counts as setup completed: no setup screen.
      expect(store.isProfileSetupDone(_user.uid), isTrue);
    });

    test('D: cleared app data + login restores from remote', () async {
      // Prefs start empty (cleared data): no local profile, no flag.
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: _school,
          program: _program,
          yearLevel: _year,
        );
      final store = await _freshStore();
      expect(store.loadProfile(_user.uid), isNull);
      expect(store.isProfileSetupDone(_user.uid), isFalse);
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.restored);
      final restored = store.loadProfile(_user.uid);
      expect(restored?.school, _school);
      expect(restored?.program, _program);
      expect(restored?.year, _year);
      // Name/email come from Firebase Auth, not the remote doc.
      expect(restored?.displayName, 'Steven Reyes');
      expect(restored?.email, 'steven@example.com');
      expect(store.isProfileSetupDone(_user.uid), isTrue);
    });

    test('E: reinstall + login with the same UID restores', () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: _school,
          program: _program,
          yearLevel: _year,
        );
      // A reinstall is a fresh local store for the same UID.
      final store = await _freshStore();
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      final restored = store.loadProfile(_user.uid);
      expect(restored?.school, _school);
      expect(restored?.program, _program);
      expect(restored?.year, _year);
    });

    test('F: repeated saves keep exactly one document per UID', () async {
      final repo = FakeStudentProfileRepository();
      await repo.saveProfile(
        _user.uid,
        const StudentProfile(
          school: _school,
          program: _program,
          yearLevel: _year,
        ),
      );
      await repo.saveProfile(
        _user.uid,
        const StudentProfile(
          school: 'MMSU',
          program: _program,
          yearLevel: '4th Year',
        ),
      );
      expect(repo.docs.length, 1);
      expect(repo.docs[_user.uid]?.school, 'MMSU');
      expect(repo.docs[_user.uid]?.yearLevel, '4th Year');
      expect(repo.saveCount, 2);
    });

    test('remote-missing + local student info backfills once', () async {
      final repo = FakeStudentProfileRepository();
      final store = await _freshStore();
      await store.saveProfile(_user.uid, _localProfile());
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.backfilled);
      expect(repo.docs[_user.uid]?.school, _school);
      expect(repo.docs[_user.uid]?.program, _program);
      expect(repo.docs[_user.uid]?.yearLevel, _year);
      // Local data unchanged by the backfill.
      expect(store.loadProfile(_user.uid)?.school, _school);
    });

    test('remote-missing + no local student info creates nothing', () async {
      final repo = FakeStudentProfileRepository();
      final store = await _freshStore();
      await store.saveProfile(
        _user.uid,
        _localProfile(school: null, program: null, year: null),
      );
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.localOnly);
      expect(repo.docs, isEmpty);
    });

    test('network failure keeps local data and never blocks login',
        () async {
      final repo = FakeStudentProfileRepository()..failFetch = true;
      final store = await _freshStore();
      await store.saveProfile(_user.uid, _localProfile());
      // Must not throw: login proceeds with local data.
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.localOnly);
      expect(store.loadProfile(_user.uid)?.school, _school);
      expect(store.loadProfile(_user.uid)?.program, _program);
      expect(store.loadProfile(_user.uid)?.year, _year);
    });

    test('backfill failure keeps local data and never throws', () async {
      final repo = FakeStudentProfileRepository()..failSave = true;
      final store = await _freshStore();
      await store.saveProfile(_user.uid, _localProfile());
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.localOnly);
      expect(store.loadProfile(_user.uid)?.school, _school);
      expect(repo.docs, isEmpty);
    });

    test('null repository leaves local data untouched', () async {
      final store = await _freshStore();
      await store.saveProfile(_user.uid, _localProfile());
      final outcome = await restoreStudentProfile(
        store: store,
        repository: null,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.localOnly);
      expect(store.loadProfile(_user.uid)?.school, _school);
    });
  });

  group('StudentProfile doc mapping', () {
    test('A: save persists school/program/year to the remote doc',
        () async {
      final repo = FakeStudentProfileRepository();
      await repo.saveProfile(
        _user.uid,
        const StudentProfile(
          school: _school,
          program: _program,
          yearLevel: _year,
        ),
      );
      final doc = repo.docs[_user.uid];
      expect(doc?.school, _school);
      expect(doc?.program, _program);
      expect(doc?.yearLevel, _year);
    });

    test('fromDoc treats empty strings as missing fields', () {
      final profile = StudentProfile.fromDoc({
        'school': '',
        'program': '  ',
        'yearLevel': null,
      });
      expect(profile?.school, isNull);
      expect(profile?.program, isNull);
      expect(profile?.yearLevel, isNull);
      expect(profile?.hasStudentInfo, isFalse);
    });

    test('fromDoc returns null for a null document', () {
      expect(StudentProfile.fromDoc(null), isNull);
    });
  });

  group('ProfileSetupScreen save path', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: child));

    Future<void> tapSave(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
    }

    testWidgets('edit save writes the remote document', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      final repo = FakeStudentProfileRepository();
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          profileRepository: repo,
          initial: _localProfile(),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(saved, isNotNull);
      expect(repo.docs[_user.uid]?.school, _school);
      expect(repo.docs[_user.uid]?.program, _program);
      expect(repo.docs[_user.uid]?.yearLevel, _year);
      // Local save still happened (contract key written).
      expect(prefs.getString(profileSchoolKey), _school);
    });

    testWidgets(
        'remote save failure shows an honest error but keeps local data '
        'and still completes', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      final repo = FakeStudentProfileRepository()..failSave = true;
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          profileRepository: repo,
          initial: _localProfile(),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tapSave(tester);
      // Local data intact and the flow completes (never trapped).
      expect(saved, isNotNull);
      expect(store.loadProfile(_user.uid)?.school, _school);
      expect(prefs.getString(profileSchoolKey), _school);
      expect(repo.docs, isEmpty);
      // Honest error surfaced.
      expect(find.textContaining('could not sync'), findsOneWidget);
    });

    testWidgets('no repository means the old local-only save path',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          initial: _localProfile(),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(saved, isNotNull);
      expect(store.loadProfile(_user.uid)?.school, _school);
      expect(find.textContaining('could not sync'), findsNothing);
    });
  });
}
