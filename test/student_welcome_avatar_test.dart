// Widget tests for the Student Hub welcome card avatar.
//
// The welcome card shows the EXACT SAME photo the Account Profile
// shows: UserProfile.photoPath (the local file picked in profile
// setup / Edit Profile), read fresh on every build from the same
// profile object the shell passes to both tabs. No second copy of
// the image exists anywhere. When there is no stored photo, the
// default person-icon avatar shows and the green card is unchanged.
//
// NOTE: the "photo" files below are real PNGs already in the repo
// (no file is created by these tests — async file creation hangs
// the tester in this sandbox, so tests must never create files).
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Existing repo images used as stand-in profile photos.
const _photoA = 'assets/images/estudyantego_logo.png';
const _photoB = 'assets/images/google_g_logo.png';

UserProfile _profileWithPhoto(String photoPath) => UserProfile(
      displayName: 'Steven',
      email: 'steven@example.com',
      photoPath: photoPath,
    );

const _noPhotoProfile = UserProfile(
  displayName: 'Steven',
  email: 'steven@example.com',
);

Future<void> _pumpHeader(WidgetTester tester, UserProfile? profile) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: studentHeader(
          greetingName: 'Good Morning',
          onBell: () {},
          profile: profile,
        ),
      ),
    ),
  );
}

CircleAvatar _welcomeAvatar(WidgetTester tester) {
  // The welcome card avatar is the first CircleAvatar in the header
  // (the bell is an IconButton, not an avatar).
  return tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
}

void main() {
  testWidgets('welcome card shows the Account Profile photo file',
      (tester) async {
    await _pumpHeader(tester, _profileWithPhoto(_photoA));

    final avatar = _welcomeAvatar(tester);
    expect(avatar.radius, 26);
    final image = avatar.backgroundImage;
    expect(image, isA<FileImage>());
    expect((image as FileImage).file.path, _photoA);
    expect(avatar.child, isNull);
  });

  testWidgets('welcome card shows the default avatar with no photo',
      (tester) async {
    await _pumpHeader(tester, null);
    var avatar = _welcomeAvatar(tester);
    expect(avatar.backgroundImage, isNull);
    expect(avatar.child, isA<Icon>());
    expect((avatar.child as Icon).icon, Icons.person);

    // A profile without a stored photo behaves the same.
    await _pumpHeader(tester, _noPhotoProfile);
    avatar = _welcomeAvatar(tester);
    expect(avatar.backgroundImage, isNull);
    expect((avatar.child as Icon).icon, Icons.person);

    // A stored path whose file is gone also falls back to default
    // (same rule as the Account Profile header).
    await _pumpHeader(
        tester, _profileWithPhoto('/definitely/not/a/real/photo.png'));
    avatar = _welcomeAvatar(tester);
    expect(avatar.backgroundImage, isNull);
    expect((avatar.child as Icon).icon, Icons.person);
  });

  testWidgets('welcome card reflects a photo change on rebuild',
      (tester) async {
    await _pumpHeader(tester, _profileWithPhoto(_photoA));
    expect(
        (_welcomeAvatar(tester).backgroundImage as FileImage).file.path,
        _photoA);

    // Rebuild with a different profile object: the new photo shows,
    // never a stale copy of the old one.
    await _pumpHeader(tester, _profileWithPhoto(_photoB));
    expect(
        (_welcomeAvatar(tester).backgroundImage as FileImage).file.path,
        _photoB);

    // Removing the photo returns to the default avatar.
    await _pumpHeader(tester, _noPhotoProfile);
    expect(_welcomeAvatar(tester).backgroundImage, isNull);
  });

  testWidgets('green welcome card design is unchanged', (tester) async {
    await _pumpHeader(tester, _profileWithPhoto(_photoA));

    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient;
    expect(gradient.colors, [kStudentEmerald, kStudentEmeraldAccent]);
    expect(decoration.borderRadius,
        const BorderRadius.all(Radius.circular(20)));
    expect(container.padding, const EdgeInsets.all(20));
    expect(find.text('Student Hub'), findsOneWidget);
    expect(find.text('Your school commute, in one place.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('StudentTab passes its profile into the welcome card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentTab(profile: _profileWithPhoto(_photoA)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final avatar = _welcomeAvatar(tester);
    final image = avatar.backgroundImage;
    expect(image, isA<FileImage>());
    expect((image as FileImage).file.path, _photoA);
  });
}
