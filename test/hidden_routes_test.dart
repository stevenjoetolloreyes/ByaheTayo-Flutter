// Tests for Remove routes (Nov 8, 2026): hide (seeded) vs delete
// (admin-added), the Hidden routes restore sheet, and the
// admin-only entry points in the route card + breakdown sheet.
// Firestore is not touched here — the local repository covers the
// same rules.
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/hidden_routes.dart';
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HiddenRoute model', () {
    test('toJson/fromJson round-trip keeps the key + author', () {
      const hidden = HiddenRoute(
        routeKey: 'Cabugao|Vigan Bus Terminal',
        authorUid: 'admin-1',
        authorEmail: 'stevenjoereyes0625@gmail.com',
        updatedAt: null,
      );
      final restored = HiddenRoute.fromJson('', hidden.toJson());
      expect(restored.routeKey, 'Cabugao|Vigan Bus Terminal');
      expect(restored.authorUid, 'admin-1');
      expect(restored.authorEmail, 'stevenjoereyes0625@gmail.com');
    });

    test('fromJson falls back to the document id', () {
      final restored = HiddenRoute.fromJson('Sinait|Cabugao', {});
      expect(restored.routeKey, 'Sinait|Cabugao');
    });

    test('validateHiddenRouteKey rejects an empty key', () {
      expect(validateHiddenRouteKey(''), isNotNull);
      expect(validateHiddenRouteKey('Cabugao|Vigan Bus Terminal'), isNull);
    });
  });

  group('LocalHiddenRouteRepository', () {
    late LocalHiddenRouteRepository repo;

    setUp(() {
      repo = LocalHiddenRouteRepository();
    });

    test('hide then loadAll returns the key', () async {
      await repo.hide('Cabugao|Vigan Bus Terminal', _admin);
      expect(
        await repo.loadAll(),
        {'Cabugao|Vigan Bus Terminal'},
      );
    });

    test('hide is idempotent — one record, not two', () async {
      await repo.hide('Cabugao|Vigan Bus Terminal', _admin);
      await repo.hide('Cabugao|Vigan Bus Terminal', _admin);
      expect((await repo.loadAll()).length, 1);
    });

    test('unhide restores; unhide of a non-hidden key is a no-op',
        () async {
      await repo.hide('Cabugao|Vigan Bus Terminal', _admin);
      await repo.unhide('Cabugao|Vigan Bus Terminal', _admin);
      expect(await repo.loadAll(), isEmpty);
      await repo.unhide('Cabugao|Vigan Bus Terminal', _admin);
      expect(await repo.loadAll(), isEmpty);
    });

    test('non-admin hide/unhide throw StateError', () async {
      await expectLater(
        repo.hide('Cabugao|Vigan Bus Terminal', _regular),
        throwsStateError,
      );
      await expectLater(
        repo.unhide('Cabugao|Vigan Bus Terminal', _regular),
        throwsStateError,
      );
      expect(await repo.loadAll(), isEmpty);
    });

    test('empty key throws ArgumentError', () async {
      await expectLater(repo.hide('', _admin), throwsArgumentError);
    });
  });

  group('Fares tab remove flow', () {
    late LocalCustomRouteRepository customRepo;
    late LocalRouteFareOverrideRepository overrideRepo;
    late LocalHiddenRouteRepository hiddenRepo;

    setUp(() {
      customRepo = LocalCustomRouteRepository();
      overrideRepo = LocalRouteFareOverrideRepository();
      hiddenRepo = LocalHiddenRouteRepository();
    });

    Future<void> pumpTab(WidgetTester tester, AuthUser? user) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FaresTab(
              currentUser: user,
              customRouteRepository: customRepo,
              fareOverrideRepository: overrideRepo,
              hiddenRouteRepository: hiddenRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a hidden seeded route is gone from Popular Routes',
        (tester) async {
      await hiddenRepo.hide('Cabugao|Vigan Bus Terminal', _admin);
      await pumpTab(tester, _admin);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsNothing);
      expect(find.text('Cabugao → San Juan, Ilocos Sur'), findsOneWidget);
      expect(find.text('Hidden routes (1)'), findsOneWidget);
    });

    testWidgets('card remove icon hides a seeded route (admin)',
        (tester) async {
      await pumpTab(tester, _admin);
      // One remove icon per route card, seeded first: the first
      // icon belongs to Cabugao → Vigan Bus Terminal.
      expect(find.byTooltip('Remove route'), findsNWidgets(7));
      await tester.ensureVisible(find.byTooltip('Remove route').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove route').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove this route?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsNothing);
      expect(find.text('Route hidden.'), findsOneWidget);
      expect(find.text('Hidden routes (1)'), findsOneWidget);
      expect(
        await hiddenRepo.loadAll(),
        {'Cabugao|Vigan Bus Terminal'},
      );
    });

    testWidgets('sheet Remove route button hides a seeded route',
        (tester) async {
      await pumpTab(tester, _admin);
      await tester.ensureVisible(find.text('Sinait → Cabugao'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sinait → Cabugao'));
      await tester.pumpAndSettle();
      expect(find.text('Remove route'), findsOneWidget);
      // The button sits at the bottom of the sheet's scroll view —
      // scroll it into view before tapping.
      await tester.ensureVisible(find.text('Remove route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove route'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this route?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Sinait → Cabugao'), findsNothing);
      expect(find.text('Route hidden.'), findsOneWidget);
    });

    testWidgets('card remove icon deletes an admin-added route for real',
        (tester) async {
      await customRepo.create(
        const CustomRoute(
          from: 'Sinait',
          to: 'Vigan Bus Terminal',
          operator: 'Partas',
          vehicle: 'Bus',
          fare: 60,
        ),
        _admin,
      );
      await pumpTab(tester, _admin);
      // 7 seeded + 1 custom; the custom card is last.
      expect(find.byTooltip('Remove route'), findsNWidgets(8));
      expect(find.text('Sinait → Vigan Bus Terminal'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Remove route').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove route').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete this route?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Sinait → Vigan Bus Terminal'), findsNothing);
      expect(find.text('Route deleted.'), findsOneWidget);
      // The seeded routes are untouched.
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
      expect(await customRepo.loadAll(), isEmpty);
    });

    testWidgets('Hidden routes sheet restores with override intact',
        (tester) async {
      // An admin-set fare on the route before hiding it.
      await overrideRepo.save(
        const RouteFareOverride(
          routeKey: 'Cabugao|Vigan Bus Terminal',
          fare: 55,
        ),
        _admin,
      );
      // Hide via the repository (the card-icon hide flow is covered
      // by the tests above) so no snackbar covers the button.
      await hiddenRepo.hide('Cabugao|Vigan Bus Terminal', _admin);
      await pumpTab(tester, _admin);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsNothing);
      expect(find.text('₱55'), findsNothing);
      expect(find.text('Hidden routes (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Hidden routes (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hidden routes (1)'));
      await tester.pumpAndSettle();
      // The sheet lists the hidden route with a Restore button.
      expect(find.text('Hidden routes'), findsOneWidget);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Route restored.'), findsOneWidget);
      // Back in the list — with the admin-set fare still applied.
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
      expect(find.text('₱55'), findsOneWidget);
      expect(find.text('Hidden routes (1)'), findsNothing);
      expect(await hiddenRepo.loadAll(), isEmpty);
      final stored = await overrideRepo.loadAll();
      expect(stored['Cabugao|Vigan Bus Terminal']!.fare, 55);
    });

    testWidgets('non-admin sees no remove icon or Hidden routes button',
        (tester) async {
      await hiddenRepo.hide('Sinait|Cabugao', _admin);
      await pumpTab(tester, _regular);
      expect(find.byTooltip('Remove route'), findsNothing);
      expect(find.textContaining('Hidden routes'), findsNothing);
      // Hiding is global: the hidden route is gone for everyone.
      expect(find.text('Sinait → Cabugao'), findsNothing);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
    });
  });
}
