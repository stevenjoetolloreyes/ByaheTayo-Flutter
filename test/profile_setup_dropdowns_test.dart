// Tests for the Edit Profile / Profile Setup student dropdowns:
// searchable School, searchable Program / course, Year level.
//
// All behavior goes through the real ProfileStore over mocked
// SharedPreferences — no Firebase config is ever required.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/profile_setup_screen.dart';
import 'package:estudyantego/features/onboarding/student_info_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Finder _fieldByLabel(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == label,
    );

String _fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_fieldByLabel(label)).controller?.text ?? '';

Future<void> _tapField(WidgetTester tester, String label) async {
  await tester.ensureVisible(_fieldByLabel(label));
  await tester.pumpAndSettle();
  await tester.tap(_fieldByLabel(label));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('dropdown-search')), query);
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save changes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

Future<(ProfileStore, UserProfile?)> _pumpEdit(
  WidgetTester tester, {
  UserProfile? initial,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final store = ProfileStore(prefs);
  UserProfile? saved;
  await tester.pumpWidget(_wrap(
    ProfileSetupScreen(
      user: _user,
      store: store,
      initial: initial,
      isEdit: true,
      onSaved: (profile) => saved = profile,
    ),
  ));
  await tester.pumpAndSettle();
  return (store, saved);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('student info data', () {
    test('school list has no duplicates and includes UNP', () {
      expect(
        philippineSchools,
        contains('University of Northern Philippines'),
      );
      expect(
        philippineSchools.toSet().length,
        philippineSchools.length,
      );
    });

    test('canonicalSchool matches case-insensitively, null otherwise', () {
      expect(
        canonicalSchool('university of northern philippines'),
        'University of Northern Philippines',
      );
      expect(canonicalSchool('  University of Northern Philippines  '),
          'University of Northern Philippines');
      expect(canonicalSchool('Not A Real School'), isNull);
      expect(canonicalSchool(''), isNull);
    });

    test('matchProgram matches display, abbreviation, and full name', () {
      expect(
        matchProgram('BSIT – Bachelor of Science in Information Technology')
            ?.abbreviation,
        'BSIT',
      );
      expect(matchProgram('bscs')?.abbreviation, 'BSCS');
      expect(
        matchProgram('Bachelor of Science in Criminology')?.abbreviation,
        'BSCRIM',
      );
      expect(matchProgram('Diploma in Computer Technology'), isNull);
      expect(matchProgram(''), isNull);
    });

    test('program list has no duplicate abbreviations', () {
      final abbrs = philippinePrograms.map((p) => p.abbreviation).toList();
      expect(abbrs.toSet().length, abbrs.length);
    });

    test('yearLevels are exactly the six specified levels', () {
      expect(yearLevels, [
        '1st Year',
        '2nd Year',
        '3rd Year',
        '4th Year',
        '5th Year',
        'Graduate / Postgraduate',
      ]);
    });

    test('normalizeYearLevel maps legacy variants, null otherwise', () {
      expect(normalizeYearLevel('Year 3'), '3rd Year');
      expect(normalizeYearLevel('1'), '1st Year');
      expect(normalizeYearLevel('Fourth Year'), '4th Year');
      expect(normalizeYearLevel('masters'), 'Graduate / Postgraduate');
      expect(normalizeYearLevel('Something Else'), isNull);
      expect(normalizeYearLevel(''), isNull);
    });
  });

  group('ProfileSetupScreen student dropdowns', () {
    testWidgets('school search filters and selection saves via contract key',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'School');
      await _search(tester, 'northern');
      expect(find.text('University of Northern Philippines'),
          findsOneWidget);
      expect(find.text('Adamson University'), findsNothing);
      await tester.tap(find.text('University of Northern Philippines'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'School'),
          'University of Northern Philippines');
      await _tapSave(tester);

      expect(saved?.school, 'University of Northern Philippines');
      expect(
        prefs.getString('byahetayo_profile_school'),
        'University of Northern Philippines',
      );
      expect(
        store.loadProfile('uid-1')?.school,
        'University of Northern Philippines',
      );
    });

    testWidgets('school selection without search saves as well',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'School');
      // No search: select the first visible listed entry.
      await tester.tap(find.text('Adamson University'));
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(saved?.school, 'Adamson University');
      expect(
        prefs.getString('byahetayo_profile_school'),
        'Adamson University',
      );
    });

    testWidgets('manual school entry saves free text',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'School');
      await tester.tap(find.text(manualSchoolOption));
      await tester.pumpAndSettle();
      await tester.enterText(
        _fieldByLabel('Enter university / college'),
        'Test University of Example',
      );
      await _tapSave(tester);

      expect(saved?.school, 'Test University of Example');
      expect(
        prefs.getString('byahetayo_profile_school'),
        'Test University of Example',
      );
    });

    testWidgets('manual school matching a listed school is canonicalized',
        (WidgetTester tester) async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'School');
      await tester.tap(find.text(manualSchoolOption));
      await tester.pumpAndSettle();
      await tester.enterText(
        _fieldByLabel('Enter university / college'),
        'university of northern philippines',
      );
      await _tapSave(tester);

      expect(saved?.school, 'University of Northern Philippines');
    });

    testWidgets('program selection saves abbreviation + full name',
        (WidgetTester tester) async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'Program / course');
      await tester
          .tap(find.text('BSIT – Bachelor of Science in Information Technology'));
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(
        saved?.program,
        'BSIT – Bachelor of Science in Information Technology',
      );
    });

    testWidgets('program manual entry saves free text',
        (WidgetTester tester) async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'Program / course');
      await tester.tap(find.text(manualProgramOption));
      await tester.pumpAndSettle();
      await tester.enterText(
        _fieldByLabel('Enter program / course'),
        'Diploma in Computer Technology',
      );
      await _tapSave(tester);

      expect(saved?.program, 'Diploma in Computer Technology');
    });

    testWidgets('year dropdown saves the selected level',
        (WidgetTester tester) async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2nd Year'));
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(saved?.year, '2nd Year');
    });

    testWidgets('prefill maps listed school, abbreviation program, year',
        (WidgetTester tester) async {
      await _pumpEdit(
        tester,
        initial: const UserProfile(
          displayName: 'Steven Reyes',
          email: 'steven@example.com',
          school: 'University of Northern Philippines',
          program: 'BSCS',
          year: '3rd Year',
        ),
      );
      expect(_fieldText(tester, 'School'),
          'University of Northern Philippines');
      expect(_fieldText(tester, 'Program / course'),
          'BSCS – Bachelor of Science in Computer Science');
      expect(find.text('3rd Year'), findsOneWidget);
    });

    testWidgets('prefill sends unlisted values to the manual fields',
        (WidgetTester tester) async {
      await _pumpEdit(
        tester,
        initial: const UserProfile(
          displayName: 'Steven Reyes',
          email: 'steven@example.com',
          school: 'Test University of Example',
          program: 'Diploma in Computer Technology',
        ),
      );
      expect(_fieldText(tester, 'Enter university / college'),
          'Test University of Example');
      expect(_fieldText(tester, 'Enter program / course'),
          'Diploma in Computer Technology');
    });

    testWidgets('clearing the school empties the contract key',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          initial: const UserProfile(
            displayName: 'Steven Reyes',
            email: 'steven@example.com',
            school: 'University of Northern Philippines',
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'School'), '');
      await _tapSave(tester);

      expect(saved?.school, isNull);
      expect(prefs.getString('byahetayo_profile_school'), '');
    });

    testWidgets('legacy year is preserved until the user picks a level',
        (WidgetTester tester) async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          initial: const UserProfile(
            displayName: 'Steven Reyes',
            email: 'steven@example.com',
            year: 'Something Else',
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Something Else'), findsOneWidget);
      await _tapSave(tester);
      expect(saved?.year, 'Something Else');
    });

    testWidgets('picking a year replaces the legacy year',
        (WidgetTester tester) async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          initial: const UserProfile(
            displayName: 'Steven Reyes',
            email: 'steven@example.com',
            year: 'Something Else',
          ),
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4th Year'));
      await tester.pumpAndSettle();
      await _tapSave(tester);
      expect(saved?.year, '4th Year');
    });

    testWidgets('saved selections reload after a fresh store (re-login)',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = ProfileStore(prefs);
      UserProfile? saved;
      await tester.pumpWidget(_wrap(
        ProfileSetupScreen(
          user: _user,
          store: store,
          isEdit: true,
          onSaved: (profile) => saved = profile,
        ),
      ));
      await tester.pumpAndSettle();
      await _tapField(tester, 'School');
      await _search(tester, 'northern');
      await tester.tap(find.text('University of Northern Philippines'));
      await tester.pumpAndSettle();
      await _tapField(tester, 'Program / course');
      await tester
          .tap(find.text('BSIT – Bachelor of Science in Information Technology'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1st Year'));
      await tester.pumpAndSettle();
      await _tapSave(tester);

      expect(saved, isNotNull);
      final reloaded = ProfileStore(prefs).loadProfile('uid-1');
      expect(reloaded?.school, 'University of Northern Philippines');
      expect(reloaded?.program,
          'BSIT – Bachelor of Science in Information Technology');
      expect(reloaded?.year, '1st Year');
      expect(prefs.getString('byahetayo_profile_school'),
          'University of Northern Philippines');
    });
  });
}
