// Tests for fare / student-fare / direction editing (Nov 7, 2026):
// the override model + repositories, the effective student fare,
// and the admin-only edit flow in the Fares tab. Firestore is not
// touched here — the local repositories cover the same rules.
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = AuthUser(
  uid: 'admin-1',
  email: 'stevenjoereyes0625@gmail.com',
);
const _regular = AuthUser(uid: 'user-1', email: 'student@example.com');

CustomRoute _customRoute({
  String from = 'Cabugao',
  String to = 'Vigan Bus Terminal',
  String operator = 'Partas',
  String vehicle = 'Bus',
  double fare = 60,
  double? studentFare,
  List<String> viaHubs = const [],
}) {
  return CustomRoute(
    from: from,
    to: to,
    operator: operator,
    vehicle: vehicle,
    fare: fare,
    studentFare: studentFare,
    viaHubs: viaHubs,
  );
}

void main() {
  group('seededRouteKey', () {
    test('keys a route by From|To', () {
      expect(seededRouteKey('Cabugao', 'Vigan Bus Terminal'),
          'Cabugao|Vigan Bus Terminal');
    });
  });

  group('parseOptionalFare', () {
    test('blank means no override', () {
      final (blankValue, blankError) = parseOptionalFare('');
      expect(blankValue, isNull);
      expect(blankError, isNull);
      final (spaceValue, spaceError) = parseOptionalFare('   ');
      expect(spaceValue, isNull);
      expect(spaceError, isNull);
    });
    test('parses whole and decimal fares', () {
      final (whole, wholeError) = parseOptionalFare('60');
      expect(whole, 60);
      expect(wholeError, isNull);
      final (decimal, decimalError) = parseOptionalFare('48.50');
      expect(decimal, 48.5);
      expect(decimalError, isNull);
    });
    test('rejects zero, negative, and non-numeric input', () {
      expect(parseOptionalFare('0').$2, isNotNull);
      expect(parseOptionalFare('-5').$2, isNotNull);
      expect(parseOptionalFare('abc').$2, isNotNull);
    });
  });

  group('validateRouteFareOverride', () {
    test('an empty override is valid (reset)', () {
      expect(
        validateRouteFareOverride(
          const RouteFareOverride(routeKey: 'Cabugao|Vigan Bus Terminal'),
        ),
        isNull,
      );
    });
    test('rejects a zero fare or student fare', () {
      expect(
        validateRouteFareOverride(
          const RouteFareOverride(
            routeKey: 'Cabugao|Vigan Bus Terminal',
            fare: 0,
          ),
        ),
        isNotNull,
      );
      expect(
        validateRouteFareOverride(
          const RouteFareOverride(
            routeKey: 'Cabugao|Vigan Bus Terminal',
            studentFare: 0,
          ),
        ),
        isNotNull,
      );
    });
  });

  group('RouteFareOverride JSON round-trip', () {
    test('keeps fare, student fare, and via stops', () {
      const override = RouteFareOverride(
        routeKey: 'Cabugao|Vigan Bus Terminal',
        fare: 65,
        studentFare: 50,
        viaHubs: ['San Juan, Ilocos Sur'],
      );
      final restored = RouteFareOverride.fromJson(
        'Cabugao|Vigan Bus Terminal',
        override.toJson(),
      );
      expect(restored.routeKey, 'Cabugao|Vigan Bus Terminal');
      expect(restored.fare, 65);
      expect(restored.studentFare, 50);
      expect(restored.viaHubs, ['San Juan, Ilocos Sur']);
    });
    test('omits a null student fare', () {
      const override = RouteFareOverride(
        routeKey: 'Cabugao|Vigan Bus Terminal',
        fare: 65,
      );
      expect(override.toJson().containsKey('studentFare'), isFalse);
      final restored = RouteFareOverride.fromJson(
        'Cabugao|Vigan Bus Terminal',
        override.toJson(),
      );
      expect(restored.studentFare, isNull);
    });
  });

  group('PopularRoute effective student fare', () {
    test('derives 80% of the regular fare when unset', () {
      const route = PopularRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        vehicle: 'Bus',
        fare: 60,
      );
      expect(route.effectiveStudentFare, 48);
    });
    test('uses the admin-set student fare when present', () {
      const route = PopularRoute(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        vehicle: 'Bus',
        fare: 60,
        studentFare: 40,
      );
      expect(route.effectiveStudentFare, 40);
    });
    test('stays null when no fare is set', () {
      const route = PopularRoute(
        from: 'Vigan Bus Terminal',
        to: 'San Juan, Ilocos Sur',
        vehicle: 'Bus',
      );
      expect(route.effectiveStudentFare, isNull);
    });
  });

  group('PopularRoute.applyOverride', () {
    const seeded = PopularRoute(
      from: 'Cabugao',
      to: 'Vigan Bus Terminal',
      vehicle: 'Bus',
      fare: 60,
      fareLabel: 'Verified bus fare',
    );

    test('a null override leaves the route unchanged', () {
      final applied = seeded.applyOverride(null);
      expect(applied.fare, 60);
      expect(applied.fareLabel, 'Verified bus fare');
    });

    test('fare override replaces the fare and label', () {
      final applied = seeded.applyOverride(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          fare: 65,
        ),
      );
      expect(applied.fare, 65);
      expect(applied.fareLabel, 'Admin-set fare');
      // Blank student fare still derives 80% of the new fare.
      expect(applied.effectiveStudentFare, 52);
    });

    test('student fare override is used as-is', () {
      final applied = seeded.applyOverride(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          studentFare: 40,
        ),
      );
      expect(applied.fare, 60);
      expect(applied.fareLabel, 'Verified bus fare');
      expect(applied.effectiveStudentFare, 40);
    });

    test('via override replaces the direction', () {
      final applied = seeded.applyOverride(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          viaHubs: ['San Juan, Ilocos Sur'],
        ),
      );
      expect(applied.viaHubs, ['San Juan, Ilocos Sur']);
    });
  });

  group('CustomRoute student fare', () {
    test('JSON round-trip keeps the student fare', () {
      final route = _customRoute(studentFare: 45).copyWith(id: 'r1');
      final restored = CustomRoute.fromJson('r1', route.toJson());
      expect(restored.studentFare, 45);
      expect(restored.fare, 60);
    });
    test('popularRouteFromCustomRoute passes it through', () {
      final popular = popularRouteFromCustomRoute(
        _customRoute(studentFare: 45),
      );
      expect(popular.studentFare, 45);
      expect(popular.effectiveStudentFare, 45);
      expect(popular.customRouteId, isNull);
      final withId = popularRouteFromCustomRoute(
        _customRoute().copyWith(id: 'r1'),
      );
      expect(withId.customRouteId, 'r1');
    });
    test('validateCustomRouteObject rejects a zero student fare', () {
      expect(validateCustomRouteObject(_customRoute(studentFare: 0)),
          isNotNull);
      expect(validateCustomRouteObject(_customRoute(studentFare: 45)),
          isNull);
    });
  });

  group('LocalRouteFareOverrideRepository', () {
    late LocalRouteFareOverrideRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = LocalRouteFareOverrideRepository();
    });

    test('regular users cannot save or delete', () async {
      await expectLater(
        repo.save(
          const RouteFareOverride(
            routeKey: 'Cabugao|Vigan Bus Terminal',
            fare: 65,
          ),
          _regular,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.delete('Cabugao|Vigan Bus Terminal', _regular),
        throwsStateError,
      );
      expect(await repo.loadAll(), isEmpty);
    });

    test('admin save/load/delete round-trips and persists', () async {
      await repo.save(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          fare: 65,
          studentFare: 50,
          viaHubs: ['San Juan, Ilocos Sur'],
        ),
        _admin,
      );
      final loaded = await repo.loadAll();
      expect(loaded.length, 1);
      expect(loaded['Cabugao|Vigan Bus Terminal']!.fare, 65);
      expect(loaded['Cabugao|Vigan Bus Terminal']!.studentFare, 50);
      expect(loaded['Cabugao|Vigan Bus Terminal']!.viaHubs,
          ['San Juan, Ilocos Sur']);
      // A fresh repository instance reads the same cache.
      final again = await LocalRouteFareOverrideRepository().loadAll();
      expect(again.length, 1);
      await repo.delete('Cabugao|Vigan Bus Terminal', _admin);
      expect(await repo.loadAll(), isEmpty);
    });

    test('invalid overrides are rejected even for admins', () async {
      await expectLater(
        repo.save(
          const RouteFareOverride(
            routeKey: 'Cabugao|Vigan Bus Terminal',
            fare: 0,
          ),
          _admin,
        ),
        throwsArgumentError,
      );
      expect(await repo.loadAll(), isEmpty);
    });
  });

  group('Fares tab edit flow', () {
    late LocalCustomRouteRepository customRepo;
    late LocalRouteFareOverrideRepository overrideRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      customRepo = LocalCustomRouteRepository();
      overrideRepo = LocalRouteFareOverrideRepository();
    });

    Future<void> pumpTab(WidgetTester tester, AuthUser? user) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FaresTab(
              currentUser: user,
              customRouteRepository: customRepo,
              fareOverrideRepository: overrideRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The TextField whose label is [label].
    Finder fieldWithLabel(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(TextField),
        );

    Future<void> openEditSheet(
      WidgetTester tester,
      String cardText,
    ) async {
      await tester.ensureVisible(find.text(cardText));
      await tester.pumpAndSettle();
      await tester.tap(find.text(cardText));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit route'));
      await tester.pumpAndSettle();
    }

    /// The Save button sits at the bottom of the scrollable edit
    /// sheet — scroll it into view before tapping.
    Future<void> tapSave(WidgetTester tester) async {
      final saveButton = find.text('Save Changes');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
    }

    testWidgets('admin sees Edit route in the breakdown sheet',
        (tester) async {
      await pumpTab(tester, _admin);
      await tester.ensureVisible(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('Edit route'), findsOneWidget);
      // ₱48 three times: one row per discount group (Student, PWD,
      // Senior Citizen — same as the existing breakdown test).
      expect(find.text('₱48'), findsNWidgets(3));
    });

    testWidgets('non-admin sees no edit entry', (tester) async {
      await pumpTab(tester, _regular);
      await tester.ensureVisible(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('Edit route'), findsNothing);
    });

    testWidgets('edit sheet is pre-filled with the current fares',
        (tester) async {
      await pumpTab(tester, _admin);
      await openEditSheet(tester, 'Cabugao → Vigan Bus Terminal');
      expect(
        tester.widget<TextField>(fieldWithLabel('Fare (₱)')).controller?.text,
        '60',
      );
      // No student fare set yet: blank, so it derives 80%.
      expect(
        tester
            .widget<TextField>(fieldWithLabel('Student fare (₱)'))
            .controller
            ?.text,
        '',
      );
      // From/To are read-only for a built-in route.
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .onChanged,
        isNull,
      );
    });

    testWidgets('saving fare + student fare updates the card',
        (tester) async {
      await pumpTab(tester, _admin);
      await openEditSheet(tester, 'Cabugao → Vigan Bus Terminal');
      await tester.enterText(fieldWithLabel('Fare (₱)'), '70');
      await tester.enterText(fieldWithLabel('Student fare (₱)'), '50');
      await tapSave(tester);
      expect(find.text('Route updated.'), findsOneWidget);
      expect(find.text('₱70'), findsOneWidget);
      expect(find.text('₱50 student'), findsOneWidget);
      // The override is stored, keyed by From|To.
      final stored = await overrideRepo.loadAll();
      expect(stored['Cabugao|Vigan Bus Terminal']!.fare, 70);
      expect(stored['Cabugao|Vigan Bus Terminal']!.studentFare, 50);
    });

    testWidgets('blank student fare derives 80% of the new fare',
        (tester) async {
      await pumpTab(tester, _admin);
      await openEditSheet(tester, 'Cabugao → Vigan Bus Terminal');
      await tester.enterText(fieldWithLabel('Fare (₱)'), '70');
      await tapSave(tester);
      expect(find.text('₱70'), findsOneWidget);
      expect(find.text('₱56 student'), findsOneWidget);
    });

    testWidgets('a Fare not set route can be given a fare',
        (tester) async {
      await pumpTab(tester, _admin);
      await tester.ensureVisible(
        find.text('Vigan Bus Terminal → San Juan, Ilocos Sur'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vigan Bus Terminal → San Juan, Ilocos Sur'));
      await tester.pumpAndSettle();
      expect(find.text('Fare not set'), findsWidgets);
      await tester.tap(find.text('Edit route'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(fieldWithLabel('Fare (₱)')).controller?.text,
        '',
      );
      await tester.enterText(fieldWithLabel('Fare (₱)'), '45');
      await tapSave(tester);
      expect(find.text('₱45'), findsOneWidget);
      expect(find.text('₱36 student'), findsOneWidget);
    });

    testWidgets('direction edit saves the via stops in order',
        (tester) async {
      await pumpTab(tester, _admin);
      await openEditSheet(tester, 'Cabugao → Vigan Bus Terminal');
      final viaChip = find.widgetWithText(
        FilterChip,
        'San Juan, Ilocos Sur',
      );
      await tester.ensureVisible(viaChip);
      await tester.tap(viaChip);
      await tester.pump();
      await tapSave(tester);
      final stored = await overrideRepo.loadAll();
      expect(
        stored['Cabugao|Vigan Bus Terminal']!.viaHubs,
        ['San Juan, Ilocos Sur'],
      );
      // The breakdown sheet lists the via stop along the way.
      await tester.ensureVisible(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('San Juan, Ilocos Sur'), findsOneWidget);
    });

    testWidgets('admin-added route edits and deletes from its sheet',
        (tester) async {
      final created = await customRepo.create(
        _customRoute(
          from: 'Sinait',
          to: 'Vigan Bus Terminal',
          studentFare: 45,
        ),
        _admin,
      );
      expect(created.id, isNotNull);
      await pumpTab(tester, _admin);
      await openEditSheet(tester, 'Sinait → Vigan Bus Terminal');
      // Pre-filled with the admin's own student fare.
      expect(
        tester
            .widget<TextField>(fieldWithLabel('Student fare (₱)'))
            .controller
            ?.text,
        '45',
      );
      await tester.enterText(fieldWithLabel('Fare (₱) *'), '65');
      await tapSave(tester);
      expect(find.text('₱65'), findsOneWidget);
      expect(find.text('₱45 student'), findsOneWidget);
      // Let the 'Route updated.' snackbar expire first: a second
      // snackbar queues behind it, and the queue only advances
      // once the first one dismisses (4 s).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // Delete it from the same sheet.
      await openEditSheet(tester, 'Sinait → Vigan Bus Terminal');
      final deleteButton = find.text('Delete route');
      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('Delete this route?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Route deleted.'), findsOneWidget);
      expect(find.text('Sinait → Vigan Bus Terminal'), findsNothing);
      expect(await customRepo.loadAll(), isEmpty);
    });
  });
}
