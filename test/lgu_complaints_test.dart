import 'package:estudyantego/features/communities_tab.dart';
import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/lgu_complaints.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

FareComplaint _complaint({
  String reference = 'BT-20261101-0001',
  String from = 'Cabugao',
  String to = 'Vigan City',
  String vehicle = 'Modern Jeepney',
  double reportedFare = 60,
  double? expectedFare,
  String location = 'Cabugao',
  String description = 'Charged double the usual fare.',
  String? photoBase64,
  String complainantName = '',
  String complainantContact = '',
  bool includePersonalInfo = false,
  ComplaintStatus status = ComplaintStatus.prepared,
}) {
  return FareComplaint(
    reference: reference,
    from: from,
    to: to,
    vehicle: vehicle,
    reportedFare: reportedFare,
    expectedFare: expectedFare,
    dateTime: DateTime(2026, 11, 1, 9, 30),
    location: location,
    description: description,
    photoBase64: photoBase64,
    complainantName: complainantName,
    complainantContact: complainantContact,
    includePersonalInfo: includePersonalInfo,
    status: status,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('complaint reference numbers', () {
    test('format is BT-YYYYMMDD-NNNN', () {
      final ref = generateComplaintReference(DateTime(2026, 11, 1), []);
      expect(ref, 'BT-20261101-0001');
      expect(
        RegExp(r'^BT-\d{8}-\d{4}$').hasMatch(ref),
        isTrue,
      );
    });

    test('sequence increments within the same day', () {
      final ref = generateComplaintReference(
        DateTime(2026, 11, 1),
        ['BT-20261101-0001', 'BT-20261101-0002'],
      );
      expect(ref, 'BT-20261101-0003');
    });

    test('sequence restarts on a new day', () {
      final ref = generateComplaintReference(
        DateTime(2026, 11, 2),
        ['BT-20261101-0009'],
      );
      expect(ref, 'BT-20261102-0001');
    });

    test('malformed existing references are ignored', () {
      final ref = generateComplaintReference(
        DateTime(2026, 11, 1),
        ['garbage', 'BT-20261101-XXXX'],
      );
      expect(ref, 'BT-20261101-0001');
    });
  });

  group('complaint message formatting', () {
    test('includes route, vehicle, fare, date, location, description', () {
      final message = formatComplaintMessage(_complaint());
      expect(message, contains('BT-20261101-0001'));
      expect(message, contains('Cabugao → Vigan City'));
      expect(message, contains('Modern Jeepney'));
      expect(message, contains('₱60'));
      expect(message, contains('2026-11-01 09:30'));
      expect(message, contains('Charged double the usual fare.'));
    });

    test('expected fare line appears only when given', () {
      expect(
        formatComplaintMessage(_complaint()),
        isNot(contains('Expected fare')),
      );
      expect(
        formatComplaintMessage(_complaint(expectedFare: 40)),
        contains('Expected fare: ₱40'),
      );
    });

    test('personal info omitted without consent, included with it', () {
      final without = formatComplaintMessage(
        _complaint(complainantName: 'Juan', complainantContact: '0917'),
      );
      expect(without, isNot(contains('Juan')));
      final withConsent = formatComplaintMessage(
        _complaint(
          complainantName: 'Juan',
          complainantContact: '0917',
          includePersonalInfo: true,
        ),
      );
      expect(withConsent, contains('Reported by: Juan · 0917'));
    });

    test('photo note appears only when evidence attached', () {
      expect(
        formatComplaintMessage(_complaint()),
        isNot(contains('Photo evidence')),
      );
      expect(
        formatComplaintMessage(_complaint(photoBase64: 'aGVsbG8=')),
        contains('attach it to your message'),
      );
    });

    test('LGU line appears when an LGU is matched', () {
      final message = formatComplaintMessage(
        _complaint(),
        lgu: seedLguEntries.first,
      );
      expect(message, contains('City Government of Vigan (Vigan City)'));
    });
  });

  group('complaint form validation', () {
    test('each missing required field is blocked', () {
      expect(
        complaintFormError(
          from: '',
          to: 'Vigan City',
          vehicle: 'Jeepney',
          reportedFareText: '60',
          description: 'Too high.',
        ),
        isNotNull,
      );
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: '',
          vehicle: 'Jeepney',
          reportedFareText: '60',
          description: 'Too high.',
        ),
        isNotNull,
      );
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: 'Vigan City',
          vehicle: '',
          reportedFareText: '60',
          description: 'Too high.',
        ),
        isNotNull,
      );
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: 'Vigan City',
          vehicle: 'Jeepney',
          reportedFareText: '0',
          description: 'Too high.',
        ),
        isNotNull,
      );
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: 'Vigan City',
          vehicle: 'Jeepney',
          reportedFareText: 'abc',
          description: 'Too high.',
        ),
        isNotNull,
      );
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: 'Vigan City',
          vehicle: 'Jeepney',
          reportedFareText: '60',
          description: '',
        ),
        isNotNull,
      );
    });

    test('invalid expected fare is blocked, valid form passes', () {
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: 'Vigan City',
          vehicle: 'Jeepney',
          reportedFareText: '60',
          description: 'Too high.',
          expectedFareText: '0',
        ),
        isNotNull,
      );
      expect(
        complaintFormError(
          from: 'Cabugao',
          to: 'Vigan City',
          vehicle: 'Jeepney',
          reportedFareText: '60',
          description: 'Too high.',
          expectedFareText: '40',
        ),
        isNull,
      );
    });
  });

  group('complaint status transitions', () {
    test('new complaint starts Prepared', () {
      expect(_complaint().status, ComplaintStatus.prepared);
      expect(_complaint().submittedAt, isNull);
    });

    test('explicit confirmation marks Submitted with a timestamp', () {
      final now = DateTime(2026, 11, 1, 10, 0);
      final submitted = markComplaintSent(_complaint(), now);
      expect(submitted.status, ComplaintStatus.submitted);
      expect(submitted.submittedAt, now);
    });

    test('marking an already-submitted complaint is a no-op', () {
      final submitted = markComplaintSent(
        _complaint(status: ComplaintStatus.submitted),
        DateTime(2026, 11, 1, 10, 0),
      );
      expect(submitted.status, ComplaintStatus.submitted);
      expect(submitted.submittedAt, isNull);
    });
  });

  group('LGU directory', () {
    test('seed contains only verified Vigan City, no Cabugao', () {
      expect(seedLguEntries.length, 1);
      final vigan = seedLguEntries.first;
      expect(vigan.municipality, 'Vigan City');
      expect(
        vigan.facebookUrl,
        'https://www.facebook.com/ViganCityPH',
      );
      expect(vigan.verified, isTrue);
      expect(vigan.hasVerifiedPage, isTrue);
      expect(
        findLguForMunicipality(seedLguEntries, 'Cabugao'),
        isNull,
      );
    });

    test('matching is case-insensitive and location-only', () {
      expect(
        findLguForMunicipality(seedLguEntries, 'vigan city')?.municipality,
        'Vigan City',
      );
      // Free-text From/To must NOT match on their own: only the
      // Location municipality is passed in, so a Cabugao-located
      // route to Vigan City has no page.
      expect(
        findLguForMunicipality(seedLguEntries, 'Cabugao'),
        isNull,
      );
    });

    test('unverified entry never counts as a verified page', () {
      const draft = LguEntry(
        id: 'x',
        municipality: 'Testville',
        lguName: 'Testville LGU',
        facebookUrl: 'https://www.facebook.com/testville',
      );
      expect(draft.hasVerifiedPage, isFalse);
    });

    test('entry validation: required fields, URL shape, verified needs URL',
      () {
      expect(
        lguEntryError(
          municipality: '',
          lguName: 'X',
          facebookUrl: '',
          verified: false,
        ),
        isNotNull,
      );
      expect(
        lguEntryError(
          municipality: 'X',
          lguName: '',
          facebookUrl: '',
          verified: false,
        ),
        isNotNull,
      );
      expect(
        lguEntryError(
          municipality: 'X',
          lguName: 'X LGU',
          facebookUrl: 'facebook.com/x',
          verified: false,
        ),
        isNotNull,
      );
      expect(
        lguEntryError(
          municipality: 'X',
          lguName: 'X LGU',
          facebookUrl: '',
          verified: true,
        ),
        isNotNull,
      );
      expect(
        lguEntryError(
          municipality: 'X',
          lguName: 'X LGU',
          facebookUrl: 'https://www.facebook.com/x',
          verified: true,
        ),
        isNull,
      );
    });
  });

  testWidgets('directory loads seed when nothing stored, stored wins',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var prefs = await SharedPreferences.getInstance();
    var entries = await loadLguEntries(prefs);
    expect(entries.length, 1);
    expect(entries.first.municipality, 'Vigan City');

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await saveLguEntries(prefs, []);
    entries = await loadLguEntries(prefs);
    expect(entries, isEmpty);
  });

  testWidgets('complaints persist and load back with status and photo',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final complaint = _complaint(
      photoBase64: 'aGVsbG8=',
      status: ComplaintStatus.submitted,
    );
    await saveFareComplaints(prefs, [complaint]);
    final loaded = await loadFareComplaints(prefs);
    expect(loaded.length, 1);
    expect(loaded.first.reference, 'BT-20261101-0001');
    expect(loaded.first.photoBase64, 'aGVsbG8=');
    expect(loaded.first.status, ComplaintStatus.submitted);
    expect(loaded.first.dateTime, DateTime(2026, 11, 1, 9, 30));
  });

  testWidgets(
      'report flow: Cabugao post shows honest empty state, saves '
      'Prepared, confirm dialog marks Submitted', (tester) async {
    // Seed flag set so the sample post does not add a second
    // 'Report Overpriced Fare' button to this flow test.
    SharedPreferences.setMockInitialValues({samplePostSeededKey: true});
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = AuthUser(uid: 'u1', email: 'user@example.com');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunitiesTab(
            onViewOnMap: () {},
            currentUser: user,
            postRepository: FakePostRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Create a Cabugao-located post (default hub is Cabugao).
    await tester.tap(find.text('Share info'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Cabugao');
    await tester.enterText(fields.at(1), 'Vigan City');
    await tester.tap(find.text('Traditional Jeepney'));
    await tester.pumpAndSettle();
    // Field order: From, To, per-vehicle fare, hours, operator.
    await tester.enterText(fields.at(2), '60');
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    expect(find.text('Cabugao → Vigan City'), findsWidgets);

    // Open the report flow.
    await tester.tap(find.text('Report Overpriced Fare'));
    await tester.pumpAndSettle();
    expect(find.text('Report Overpriced Fare'), findsWidgets);
    // Cabugao has no verified page: honest empty state, no Open button.
    expect(
      find.textContaining('No verified LGU Facebook page found for Cabugao'),
      findsOneWidget,
    );
    expect(find.textContaining('Open '), findsNothing);

    // Saving without a description is blocked.
    await tester.tap(find.text('Save complaint'));
    await tester.pump();
    expect(find.text('Describe what happened.'), findsOneWidget);

    // Fill the description and save: detail sheet, status Prepared.
    final descriptionField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Complaint description *',
    );
    await tester.enterText(descriptionField, 'Charged double the fare.');
    await tester.tap(find.text('Save complaint'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Overpriced Fare Complaint'), findsOneWidget);
    // Twice: the detail chip plus the list card behind the sheet.
    expect(find.text('Prepared'), findsWidgets);
    expect(find.text('Mark as sent'), findsOneWidget);

    // Confirm dialog: Yes marks Submitted with a timestamp.
    await tester.tap(find.text('Mark as sent'));
    await tester.pumpAndSettle();
    expect(find.text('Did you send it?'), findsOneWidget);
    await tester.tap(find.text('Yes, I sent it'));
    await tester.pumpAndSettle();
    // Twice: the detail chip plus the list card behind the sheet.
    expect(find.text('Submitted'), findsWidgets);
    expect(find.textContaining('Marked sent on'), findsOneWidget);

    // Close the detail sheet: the complaint card shows Submitted.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('My fare complaints'), findsOneWidget);
    expect(find.textContaining(RegExp(r'BT-\d{8}-\d{4}')), findsWidgets);
    expect(find.text('Submitted'), findsWidgets);
  });
}
