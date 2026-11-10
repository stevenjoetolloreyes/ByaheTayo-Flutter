// Google Sign-In / Sign-Up strict-rule tests (fakes only — no real
// Google sign-in, no Firebase, no network).
//
// Covered (per the strict rule):
// - Sign In Google with an existing EstudyanteGO profile succeeds.
// - Sign In Google without a profile signs out immediately, shows the
//   exact "No account found..." message, and offers Create Account.
// - Sign In Google canceled shows an honest message and signs nothing
//   out.
// - Sign Up Google with a new UID creates the UID-keyed profile
//   (UID, full name, email, photo).
// - Sign Up Google with an existing UID reuses the profile (no
//   duplicate, no overwrite).
import 'dart:convert';

import 'package:estudyantego/features/onboarding/auth_screen.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService fake;
  AuthUser? signedInUser;
  AuthUser? createdUser;
  var createAccountRequested = false;
  var signInRequested = false;

  /// Pumps the auth page for [signIn]: SignInScreen for sign-in,
  /// CreateAccountScreen for create-account. The two pages are
  /// separate routes now (Nov 10 split); cross-page links fire the
  /// gate callbacks instead of toggling a mode in place.
  Future<void> pumpAuth(WidgetTester tester, {required bool signIn}) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: signIn
            ? SignInScreen(
                service: fake,
                onSignedIn: (user) => signedInUser = user,
                onCreateAccountRequested: () => createAccountRequested = true,
              )
            : CreateAccountScreen(
                service: fake,
                onAccountCreated: (user) => createdUser = user,
                onSignedIn: (user) => signedInUser = user,
                onSignInRequested: () => signInRequested = true,
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveProfile(String uid, UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profileDataKey(uid), jsonEncode(profile.toJson()));
  }

  Future<UserProfile?> readProfile(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ProfileStore(prefs);
    return store.loadProfile(uid);
  }

  setUp(() {
    fake = FakeAuthService();
    signedInUser = null;
    createdUser = null;
    createAccountRequested = false;
    signInRequested = false;
    SharedPreferences.setMockInitialValues({});
  });

  AuthUser googleUser({
    required String uid,
    String name = 'Ana Santos',
    String email = 'ana@example.com',
    String? photoUrl,
  }) =>
      AuthUser(
        uid: uid,
        email: email,
        displayName: name,
        emailVerified: true,
        photoUrl: photoUrl,
      );

  testWidgets('Google Sign In with existing profile succeeds',
      (tester) async {
    await saveProfile(
      'google-uid-1',
      const UserProfile(displayName: 'Ana Santos', email: 'ana@example.com'),
    );
    fake.googleUser = googleUser(uid: 'google-uid-1');
    await pumpAuth(tester, signIn: true);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(signedInUser, isNotNull);
    expect(signedInUser!.uid, 'google-uid-1');
    expect(fake.signOutCount, 0);
    expect(find.text(noAccountFoundMessage), findsNothing);
  });

  testWidgets('Google Sign In without profile signs out and shows message',
      (tester) async {
    fake.googleUser = googleUser(uid: 'google-unknown-uid');
    await pumpAuth(tester, signIn: true);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(signedInUser, isNull);
    expect(fake.signOutCount, 1);
    expect(find.text(noAccountFoundMessage), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    // The no-account button navigates to the Create Account page
    // (separate page since the Nov 10 split); the gate swaps the
    // destination, so here we assert the request fires and the
    // Create Account page renders its title.
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(createAccountRequested, isTrue);
    await pumpAuth(tester, signIn: false);
    expect(find.text('Create Your Account'), findsOneWidget);
  });

  testWidgets('Google Sign In canceled shows honest message, no sign-out',
      (tester) async {
    fake.googleCanceled = true;
    await pumpAuth(tester, signIn: true);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(signedInUser, isNull);
    expect(fake.signOutCount, 0);
    expect(find.text('Google sign-in was canceled.'), findsOneWidget);
  });

  testWidgets('Google Sign Up with new UID creates UID-keyed profile',
      (tester) async {
    fake.googleUser = googleUser(
      uid: 'google-new-1',
      photoUrl: 'https://example.com/photo.jpg',
    );
    await pumpAuth(tester, signIn: false);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(signedInUser, isNotNull);
    expect(signedInUser!.uid, 'google-new-1');
    final profile = await readProfile('google-new-1');
    expect(profile, isNotNull);
    expect(profile!.displayName, 'Ana Santos');
    expect(profile.email, 'ana@example.com');
    expect(profile.photoUrl, 'https://example.com/photo.jpg');
    expect(createdUser, isNull);
  });

  testWidgets('Google Sign Up with existing UID reuses profile, no duplicate',
      (tester) async {
    await saveProfile(
      'google-uid-9',
      const UserProfile(
        displayName: 'Original Name',
        email: 'ana@example.com',
      ),
    );
    fake.googleUser = googleUser(uid: 'google-uid-9', name: 'New Name');
    await pumpAuth(tester, signIn: false);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(signedInUser, isNotNull);
    final profile = await readProfile('google-uid-9');
    expect(profile, isNotNull);
    expect(profile!.displayName, 'Original Name');
  });

  testWidgets('Google button exists on both Sign In and Create Account',
      (tester) async {
    await pumpAuth(tester, signIn: true);
    expect(find.text('Continue with Google'), findsOneWidget);
    // The cross-link navigates to the Create Account page (separate
    // page since the Nov 10 split); the gate swaps the destination,
    // so here we assert the request fires and the Create Account
    // page renders its Google button.
    await tester.tap(find.text("Don't have an account? Create Account"));
    await tester.pumpAndSettle();
    expect(createAccountRequested, isTrue);
    await pumpAuth(tester, signIn: false);
    expect(find.text('Create Your Account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    // And back the other way.
    await tester.tap(find.text('Already have an account? Sign In'));
    await tester.pumpAndSettle();
    expect(signInRequested, isTrue);
  });
}
