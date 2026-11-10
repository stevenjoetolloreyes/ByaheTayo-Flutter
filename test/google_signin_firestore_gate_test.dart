// Google Sign-In gate — Firestore fallback tests (Feature 5, Nov 10).
//
// The gate used to check ONLY the local ProfileStore: a returning
// user on a fresh install / cleared data / new device got
// "No account found" even though their profile existed in Firestore
// (`student_profiles`, doc ID = UID). The gate now checks Firestore
// for that UID when the local profile is missing, before rejecting.
//
// Covered (fakes only — no real Google sign-in, no Firebase):
// (a) local missing + Firestore profile exists -> login proceeds,
//     no sign-out, and the local store is NOT written here (the
//     normal post-auth restore does that merge).
// (b) local missing + Firestore missing -> sign out + the exact
//     "No account found..." message + Create Account button.
// (c) local exists -> login proceeds and Firestore is never queried.
// (d) Firestore fetch error -> retry-able error shown, NO
//     "No account found", NO sign-out (one more tap retries).
// (e) Firestore has a profile under a DIFFERENT UID -> "No account
//     found" for this UID (lookup is by UID only, never by email).
import 'package:estudyantego/features/onboarding/auth_screen.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

/// In-memory [StudentProfileRepository]: one document per UID.
class FakeGateProfileRepository implements StudentProfileRepository {
  final Map<String, StudentProfile> docs = {};
  int fetchCount = 0;
  final List<String> fetchedUids = [];

  /// When true, [fetchProfile] throws, simulating a network failure.
  bool failFetch = false;

  @override
  Future<StudentProfile?> fetchProfile(String uid) async {
    fetchCount++;
    fetchedUids.add(uid);
    if (failFetch) throw Exception('Simulated network failure.');
    return docs[uid];
  }

  @override
  Future<void> saveProfile(String uid, StudentProfile profile) async {
    docs[uid] = profile;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService fake;
  late FakeGateProfileRepository repo;
  AuthUser? signedInUser;
  var createAccountRequested = false;

  Future<void> pumpSignIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          service: fake,
          onSignedIn: (user) => signedInUser = user,
          onCreateAccountRequested: () => createAccountRequested = true,
          profileRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    fake = FakeAuthService();
    repo = FakeGateProfileRepository();
    signedInUser = null;
    createAccountRequested = false;
    SharedPreferences.setMockInitialValues({});
  });

  AuthUser googleUser({required String uid, String email = 'ana@example.com'}) =>
      AuthUser(
        uid: uid,
        email: email,
        displayName: 'Ana Santos',
        emailVerified: true,
      );

  testWidgets(
      '(a) local missing + Firestore profile exists -> login proceeds',
      (tester) async {
    // No local profile saved: fresh install / cleared data.
    repo.docs['google-uid-1'] = const StudentProfile(
      school: 'University of Northern Philippines',
      program: 'BSIT',
      yearLevel: '1st Year',
    );
    fake.googleUser = googleUser(uid: 'google-uid-1');
    await pumpSignIn(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(signedInUser, isNotNull);
    expect(signedInUser!.uid, 'google-uid-1');
    expect(fake.signOutCount, 0);
    expect(find.text(noAccountFoundMessage), findsNothing);
    expect(repo.fetchedUids, ['google-uid-1']);
  });

  testWidgets(
      '(b) local missing + Firestore missing -> sign out + No account found',
      (tester) async {
    fake.googleUser = googleUser(uid: 'google-unknown-uid');
    await pumpSignIn(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(signedInUser, isNull);
    expect(fake.signOutCount, 1);
    expect(find.text(noAccountFoundMessage), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(createAccountRequested, isTrue);
  });

  testWidgets('(c) local exists -> login proceeds, Firestore never queried',
      (tester) async {
    // Local profile present: the gate must not touch Firestore at all.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      profileDataKey('google-uid-1'),
      '{"displayName":"Ana Santos","email":"ana@example.com"}',
    );
    repo.docs['google-uid-1'] = const StudentProfile(school: 'UNP');
    fake.googleUser = googleUser(uid: 'google-uid-1');
    await pumpSignIn(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(signedInUser, isNotNull);
    expect(signedInUser!.uid, 'google-uid-1');
    expect(fake.signOutCount, 0);
    expect(repo.fetchCount, 0);
  });

  testWidgets(
      '(d) Firestore fetch error -> retry-able error, no sign-out, '
      'no "No account found"', (tester) async {
    repo.failFetch = true;
    fake.googleUser = googleUser(uid: 'google-uid-1');
    await pumpSignIn(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(signedInUser, isNull);
    expect(fake.signOutCount, 0);
    expect(find.text('Something went wrong. Please try again.'),
        findsOneWidget);
    expect(find.text(noAccountFoundMessage), findsNothing);
    expect(find.text('Create Account'), findsNothing);
  });

  testWidgets(
      '(e) profile under a DIFFERENT UID -> "No account found" for this UID',
      (tester) async {
    // The profile belongs to another Google account (another UID).
    // The gate looks up by UID only — never by email — so this UID
    // must still be rejected.
    repo.docs['other-uid'] = const StudentProfile(school: 'UNP');
    fake.googleUser = googleUser(uid: 'google-uid-1');
    await pumpSignIn(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(signedInUser, isNull);
    expect(fake.signOutCount, 1);
    expect(find.text(noAccountFoundMessage), findsOneWidget);
    expect(repo.fetchedUids, ['google-uid-1']);
  });
}
