// Tests for the admin-assigned subscription plan read path (Builder 1).
//
// Covers:
//   - plan parsing: missing/invalid/non-string values fall back to free;
//     'standard'/'pro' parse; matching is case-insensitive and trims.
//   - plan -> storage-limit mapping: free 2 GB, standard 12 GB,
//     pro 30 GB in bytes, read from the plan constants (never a second
//     hardcoded copy), and the storageGB constants still carry 2/12/30.
//   - Firestore read: StudentProfile.fromDoc parses the admin-set
//     `plan` field; the app NEVER writes it (toDoc has no 'plan' key
//     and fromUserProfile never carries it).
//   - restore: the remote plan reaches the local profile on sign-in /
//     startup (including cleared app data), and the remote plan always
//     wins over the cached local one.
//
// Fakes only — no live Firebase is touched.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/profile_repository.dart';
import 'package:estudyantego/features/subscription_membership.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

const _gib = 1024 * 1024 * 1024;

/// In-memory [StudentProfileRepository]: one document per UID.
class FakeStudentProfileRepository implements StudentProfileRepository {
  final Map<String, StudentProfile> docs = {};

  /// When true, [fetchProfile] throws, simulating a network failure.
  bool failFetch = false;

  @override
  Future<StudentProfile?> fetchProfile(String uid) async {
    if (failFetch) throw Exception('Simulated network failure.');
    return docs[uid];
  }

  @override
  Future<void> saveProfile(String uid, StudentProfile profile) async {
    docs[uid] = profile;
  }
}

UserProfile _localProfile({SubscriptionPlanId plan = SubscriptionPlanId.free}) {
  return UserProfile(
    displayName: 'Steven Reyes',
    email: 'steven@example.com',
    school: 'University of Northern Philippines',
    program: 'BSIT',
    year: '1st Year',
    plan: plan,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('parseSubscriptionPlanId', () {
    test('missing (null) parses to free', () {
      expect(parseSubscriptionPlanId(null), SubscriptionPlanId.free);
    });

    test('non-string values parse to free', () {
      expect(parseSubscriptionPlanId(2), SubscriptionPlanId.free);
      expect(parseSubscriptionPlanId(true), SubscriptionPlanId.free);
      expect(
        parseSubscriptionPlanId(['pro']),
        SubscriptionPlanId.free,
      );
    });

    test('free / standard / pro parse', () {
      expect(parseSubscriptionPlanId('free'), SubscriptionPlanId.free);
      expect(
        parseSubscriptionPlanId('standard'),
        SubscriptionPlanId.standard,
      );
      expect(parseSubscriptionPlanId('pro'), SubscriptionPlanId.pro);
    });

    test('matching is case-insensitive and trims whitespace', () {
      expect(
        parseSubscriptionPlanId('Standard'),
        SubscriptionPlanId.standard,
      );
      expect(parseSubscriptionPlanId('PRO'), SubscriptionPlanId.pro);
      expect(parseSubscriptionPlanId('  pro  '), SubscriptionPlanId.pro);
      expect(parseSubscriptionPlanId('Free'), SubscriptionPlanId.free);
    });

    test('unknown values parse to free — a plan is never invented', () {
      expect(parseSubscriptionPlanId('premium'), SubscriptionPlanId.free);
      expect(parseSubscriptionPlanId('gold'), SubscriptionPlanId.free);
      expect(parseSubscriptionPlanId(''), SubscriptionPlanId.free);
      expect(parseSubscriptionPlanId('  '), SubscriptionPlanId.free);
      expect(parseSubscriptionPlanId('enterprise'), SubscriptionPlanId.free);
    });
  });

  group('subscriptionStorageLimitBytes (shared source of truth)', () {
    test('free = 2 GB in bytes', () {
      expect(
        subscriptionStorageLimitBytes(SubscriptionPlanId.free),
        2 * _gib,
      );
    });

    test('standard = 12 GB in bytes', () {
      expect(
        subscriptionStorageLimitBytes(SubscriptionPlanId.standard),
        12 * _gib,
      );
    });

    test('pro = 30 GB in bytes', () {
      expect(
        subscriptionStorageLimitBytes(SubscriptionPlanId.pro),
        30 * _gib,
      );
    });

    test('limits come from the plan constants, not a second copy', () {
      for (final id in SubscriptionPlanId.values) {
        final plan = subscriptionPlanForId(id);
        expect(
          subscriptionStorageLimitBytes(id),
          plan.storageGB * _gib,
        );
        expect(subscriptionStorageLimitBytes(id), plan.storageBytes);
      }
    });

    test('storageGB constants still carry 2 / 12 / 30', () {
      expect(
        subscriptionPlanForId(SubscriptionPlanId.free).storageGB,
        2,
      );
      expect(
        subscriptionPlanForId(SubscriptionPlanId.standard).storageGB,
        12,
      );
      expect(
        subscriptionPlanForId(SubscriptionPlanId.pro).storageGB,
        30,
      );
    });

    test('subscriptionPlanForId returns the matching plan', () {
      expect(
        subscriptionPlanForId(SubscriptionPlanId.pro).name,
        'Pro',
      );
      expect(
        subscriptionPlanForId(SubscriptionPlanId.standard).name,
        'Standard',
      );
    });
  });

  group('StudentProfile doc mapping (plan read path)', () {
    test('fromDoc parses an admin-set plan', () {
      expect(
        StudentProfile.fromDoc({'plan': 'standard'})?.plan,
        SubscriptionPlanId.standard,
      );
      expect(
        StudentProfile.fromDoc({'plan': 'pro'})?.plan,
        SubscriptionPlanId.pro,
      );
    });

    test('fromDoc defaults a missing plan to free', () {
      expect(
        StudentProfile.fromDoc({'school': 'UNP'})?.plan,
        SubscriptionPlanId.free,
      );
      expect(StudentProfile.fromDoc({})?.plan, SubscriptionPlanId.free);
    });

    test('fromDoc defaults an invalid plan to free', () {
      expect(
        StudentProfile.fromDoc({'plan': 'premium'})?.plan,
        SubscriptionPlanId.free,
      );
      expect(
        StudentProfile.fromDoc({'plan': 99})?.plan,
        SubscriptionPlanId.free,
      );
      expect(
        StudentProfile.fromDoc({'plan': 'PRO'})?.plan,
        SubscriptionPlanId.pro,
      );
    });

    test('fromDoc returns null for a null document', () {
      expect(StudentProfile.fromDoc(null), isNull);
    });

    test('toDoc NEVER writes the plan field (admin-only)', () {
      const profile = StudentProfile(
        school: 'UNP',
        plan: SubscriptionPlanId.pro,
      );
      final doc = profile.toDoc();
      expect(doc.containsKey('plan'), isFalse);
      // The other fields still write as before.
      expect(doc['school'], 'UNP');
      expect(doc.containsKey('updatedAt'), isTrue);
    });

    test('fromUserProfile never carries the plan into a save', () {
      final remote = StudentProfile.fromUserProfile(
        _localProfile(plan: SubscriptionPlanId.pro),
      );
      // Even a locally cached Pro profile saves without a plan, so
      // a backfill or photo-upload save can never overwrite the
      // admin-assigned value (or create one).
      expect(remote.plan, SubscriptionPlanId.free);
      expect(remote.toDoc().containsKey('plan'), isFalse);
    });
  });

  group('mergeStudentInfo (plan)', () {
    test('remote plan wins over the cached local plan', () {
      final merged = mergeStudentInfo(
        _localProfile(plan: SubscriptionPlanId.free),
        const StudentProfile(plan: SubscriptionPlanId.pro),
      );
      expect(merged.plan, SubscriptionPlanId.pro);
    });

    test('remote free (missing field) downgrades a cached paid plan', () {
      // The admin clearing the field means the user is Free again.
      final merged = mergeStudentInfo(
        _localProfile(plan: SubscriptionPlanId.pro),
        const StudentProfile(),
      );
      expect(merged.plan, SubscriptionPlanId.free);
    });

    test('other fields still merge by the non-empty-remote-wins rule', () {
      final merged = mergeStudentInfo(
        _localProfile(plan: SubscriptionPlanId.free),
        const StudentProfile(
          school: 'MMSU',
          plan: SubscriptionPlanId.standard,
        ),
      );
      expect(merged.school, 'MMSU');
      expect(merged.program, 'BSIT');
      expect(merged.year, '1st Year');
      expect(merged.plan, SubscriptionPlanId.standard);
    });
  });

  group('restoreStudentProfile (plan)', () {
    test('remote Pro plan restores into the local profile on sign-in',
        () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: 'University of Northern Philippines',
          plan: SubscriptionPlanId.pro,
        );
      final store = ProfileStore(await SharedPreferences.getInstance());
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.restored);
      expect(store.loadProfile(_user.uid)?.plan, SubscriptionPlanId.pro);
      expect(
        subscriptionStorageLimitBytes(
          store.loadProfile(_user.uid)!.plan,
        ),
        30 * _gib,
      );
    });

    test('cleared app data + login restores the plan from remote', () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          plan: SubscriptionPlanId.standard,
        );
      final store = ProfileStore(await SharedPreferences.getInstance());
      expect(store.loadProfile(_user.uid), isNull);
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(
        store.loadProfile(_user.uid)?.plan,
        SubscriptionPlanId.standard,
      );
    });

    test('remote doc without a plan restores as free', () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = const StudentProfile(
          school: 'University of Northern Philippines',
        );
      final store = ProfileStore(await SharedPreferences.getInstance());
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(store.loadProfile(_user.uid)?.plan, SubscriptionPlanId.free);
    });

    test('remote doc with an invalid plan restores as free', () async {
      final repo = FakeStudentProfileRepository()
        ..docs[_user.uid] = StudentProfile.fromDoc({
          'school': 'University of Northern Philippines',
          'plan': 'premium',
        })!;
      final store = ProfileStore(await SharedPreferences.getInstance());
      await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(store.loadProfile(_user.uid)?.plan, SubscriptionPlanId.free);
    });

    test('network failure keeps the cached local plan', () async {
      final repo = FakeStudentProfileRepository()..failFetch = true;
      final store = ProfileStore(await SharedPreferences.getInstance());
      await store.saveProfile(
        _user.uid,
        _localProfile(plan: SubscriptionPlanId.standard),
      );
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.localOnly);
      expect(
        store.loadProfile(_user.uid)?.plan,
        SubscriptionPlanId.standard,
      );
    });

    test('backfill never writes a plan to the remote doc', () async {
      final repo = FakeStudentProfileRepository();
      final store = ProfileStore(await SharedPreferences.getInstance());
      await store.saveProfile(
        _user.uid,
        _localProfile(plan: SubscriptionPlanId.pro),
      );
      final outcome = await restoreStudentProfile(
        store: store,
        repository: repo,
        user: _user,
      );
      expect(outcome, ProfileRestoreOutcome.backfilled);
      // A document was created by the backfill, but its written
      // fields carry no plan (toDoc omits it).
      expect(
        repo.docs[_user.uid]?.toDoc().containsKey('plan'),
        isFalse,
      );
      // The cached local plan is untouched by the backfill.
      expect(store.loadProfile(_user.uid)?.plan, SubscriptionPlanId.pro);
    });
  });

  group('UserProfile plan persistence (local cache)', () {
    test('plan survives a toJson / fromJson round-trip', () {
      final restored = UserProfile.fromJson(
        _localProfile(plan: SubscriptionPlanId.pro).toJson(),
      );
      expect(restored?.plan, SubscriptionPlanId.pro);
    });

    test('profiles written before the plan field read back as free', () {
      final json = _localProfile().toJson()..remove('plan');
      expect(
        UserProfile.fromJson(json)?.plan,
        SubscriptionPlanId.free,
      );
    });

    test('plan defaults to free on a fresh profile', () {
      const profile = UserProfile(
        displayName: 'Steven Reyes',
        email: 'steven@example.com',
      );
      expect(profile.plan, SubscriptionPlanId.free);
    });
  });
}
