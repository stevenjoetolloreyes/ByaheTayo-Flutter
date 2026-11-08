// Tests for the Admin Access organize (Nov 8, 2026): one Admin
// Access section in the Account tab gathers ALL admin tools.
// Standalone Fares actions run from the section via a request the
// Fares tab consumes; Map actions jump to the Map tab with the
// tool ready; route-specific actions jump to the tab where the
// route / stop is picked. Admin-only throughout — non-admins see
// no section and no request runs for them.
import 'package:estudyantego/features/account_tab.dart';
import 'package:estudyantego/features/bus_companies.dart';
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/hidden_routes.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/route_fare_overrides.dart';
import 'package:estudyantego/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _admin = AuthUser(
  uid: 'admin-1',
  email: 'stevenjoereyes0625@gmail.com',
);
const _regular = AuthUser(uid: 'user-1', email: 'student@example.com');

void main() {
  group('Account Admin Access section', () {
    late int faresJumps;
    late int mapJumps;

    Future<void> pumpAccount(WidgetTester tester, AuthUser? user) async {
      faresJumps = 0;
      mapJumps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountTab(
              themePreference: AppThemePreference.dark,
              onThemePreferenceChanged: (_) {},
              authService: FakeAuthService(user: user),
              user: user,
              permissionService: FakePermissionService(),
              onViewFares: () => faresJumps++,
              onViewMap: () => mapJumps++,
              onSignedOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Taps a section row that may sit below the fold.
    Future<void> tapRow(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    setUp(() {
      faresAdminActionRequest.value = null;
      mapLineMakerRequest.value = null;
      mapSetEndpointsRequest.value = false;
    });

    tearDown(() {
      faresAdminActionRequest.value = null;
      mapLineMakerRequest.value = null;
      mapSetEndpointsRequest.value = false;
    });

    testWidgets('admin sees every Admin Access row, grouped',
        (tester) async {
      await pumpAccount(tester, _admin);
      await tester.ensureVisible(find.text('Admin Access'));
      await tester.pumpAndSettle();

      expect(find.text('Admin Access'), findsOneWidget);
      // Communities tools, kept as-is.
      expect(find.text('Post approvals'), findsOneWidget);
      expect(find.text('LGU directory'), findsOneWidget);
      // Routes & fares group.
      expect(find.text('ROUTES & FARES'), findsOneWidget);
      expect(find.text('Add Route'), findsOneWidget);
      expect(find.text('Manage bus stops'), findsOneWidget);
      expect(find.text('Reset all directions'), findsOneWidget);
      expect(find.text('Hidden routes'), findsOneWidget);
      expect(find.text('Add company'), findsOneWidget);
      expect(find.text('Edit or remove a route'), findsOneWidget);
      // On the map group.
      expect(find.text('ON THE MAP'), findsOneWidget);
      expect(find.text('Draw a line'), findsOneWidget);
      expect(find.text('Set Start/End'), findsOneWidget);
      expect(find.text('Rename a stop'), findsOneWidget);
    });

    testWidgets('each Routes & fares row requests its action and jumps',
        (tester) async {
      await pumpAccount(tester, _admin);
      const rows = {
        'Add Route': FaresAdminAction.addRoute,
        'Manage bus stops': FaresAdminAction.manageBusStops,
        'Reset all directions': FaresAdminAction.resetDirections,
        'Hidden routes': FaresAdminAction.hiddenRoutes,
        'Add company': FaresAdminAction.addCompany,
      };
      var jumps = 0;
      for (final entry in rows.entries) {
        await tapRow(tester, entry.key);
        expect(faresAdminActionRequest.value, entry.value);
        expect(faresJumps, ++jumps);
        // No consumer in this test — clear it so the next row's
        // request is a fresh value.
        faresAdminActionRequest.value = null;
      }
      expect(mapJumps, 0);
    });

    testWidgets('Edit or remove a route jumps to Fares, no request',
        (tester) async {
      await pumpAccount(tester, _admin);
      await tapRow(tester, 'Edit or remove a route');
      expect(faresJumps, 1);
      expect(faresAdminActionRequest.value, isNull);
    });

    testWidgets('Draw a line requests the line maker and jumps to Map',
        (tester) async {
      await pumpAccount(tester, _admin);
      await tapRow(tester, 'Draw a line');
      expect(mapLineMakerRequest.value, (drawLine: true, addStop: false));
      expect(mapJumps, 1);
      expect(faresJumps, 0);
    });

    testWidgets('Set Start/End requests the mode and jumps to Map',
        (tester) async {
      await pumpAccount(tester, _admin);
      await tapRow(tester, 'Set Start/End');
      expect(mapSetEndpointsRequest.value, isTrue);
      expect(mapJumps, 1);
      expect(faresJumps, 0);
    });

    testWidgets('Rename a stop jumps to Map, no request', (tester) async {
      await pumpAccount(tester, _admin);
      await tapRow(tester, 'Rename a stop');
      expect(mapJumps, 1);
      expect(mapSetEndpointsRequest.value, isFalse);
      expect(mapLineMakerRequest.value, isNull);
    });

    testWidgets('non-admin sees no Admin Access section', (tester) async {
      await pumpAccount(tester, _regular);
      expect(find.text('Admin Access'), findsNothing);
      expect(find.text('Add Route'), findsNothing);
      expect(find.text('Draw a line'), findsNothing);
      expect(find.text('Post approvals'), findsNothing);
    });
  });

  group('Fares admin action requests', () {
    late LocalCustomRouteRepository customRepo;
    late LocalRouteFareOverrideRepository overrideRepo;
    late LocalHiddenRouteRepository hiddenRepo;
    late LocalBusStopRepository busStopRepo;
    late LocalBusCompanyRepository companyRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      faresAdminActionRequest.value = null;
      customRepo = LocalCustomRouteRepository();
      overrideRepo = LocalRouteFareOverrideRepository();
      hiddenRepo = LocalHiddenRouteRepository();
      busStopRepo = LocalBusStopRepository();
      companyRepo = LocalBusCompanyRepository();
    });

    tearDown(() {
      faresAdminActionRequest.value = null;
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
              busStopRepository: busStopRepo,
              busCompanyRepository: companyRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Sets the request the way the Admin Access section does, then
    /// lets the Fares tab consume it one frame later.
    Future<void> request(
      WidgetTester tester,
      FaresAdminAction action,
    ) async {
      faresAdminActionRequest.value = action;
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('the Fares tab body has no admin buttons anymore',
        (tester) async {
      await pumpTab(tester, _admin);
      expect(find.text('Add Route'), findsNothing);
      expect(find.text('Manage bus stops'), findsNothing);
      expect(find.text('Reset all directions'), findsNothing);
    });

    testWidgets('addRoute opens the Add Route sheet', (tester) async {
      await pumpTab(tester, _admin);
      await request(tester, FaresAdminAction.addRoute);
      // The sheet shows 'Add Route' twice — the title and the
      // submit button — so the sheet's From field pins it open.
      expect(find.text('Add Route'), findsNWidgets(2));
      expect(find.text('From *'), findsOneWidget);
    });

    testWidgets('manageBusStops opens the Manage bus stops sheet',
        (tester) async {
      await pumpTab(tester, _admin);
      await request(tester, FaresAdminAction.manageBusStops);
      expect(find.text('Manage bus stops'), findsOneWidget);
      expect(find.text('No bus stops added yet.'), findsOneWidget);
    });

    testWidgets('hiddenRoutes opens the Hidden routes sheet',
        (tester) async {
      await hiddenRepo.hide('Cabugao|Vigan Bus Terminal', _admin);
      await pumpTab(tester, _admin);
      await request(tester, FaresAdminAction.hiddenRoutes);
      expect(find.text('Hidden routes'), findsOneWidget);
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
    });

    testWidgets('resetDirections with nothing saved shows the empty note',
        (tester) async {
      await pumpTab(tester, _admin);
      await request(tester, FaresAdminAction.resetDirections);
      expect(find.text('No saved directions to reset.'), findsOneWidget);
    });

    testWidgets('resetDirections with a saved direction asks then resets',
        (tester) async {
      await customRepo.create(
        const CustomRoute(
          from: 'Cabugao',
          to: 'Vigan Bus Terminal',
          operator: 'Partas',
          vehicle: 'Bus',
          fare: 60,
          viaHubs: ['San Juan, Ilocos Sur'],
        ),
        _admin,
      );
      await pumpTab(tester, _admin);
      await request(tester, FaresAdminAction.resetDirections);
      expect(find.text('Reset all directions?'), findsOneWidget);
      await tester.tap(find.text('Reset all'));
      await tester.pumpAndSettle();
      expect(
        find.text('Reset 1 direction(s). Fares were not changed.'),
        findsOneWidget,
      );
      final routes = await customRepo.loadAll();
      expect(routes.single.viaHubs, isEmpty);
    });

    testWidgets('addCompany opens the dialog and saves', (tester) async {
      await pumpTab(tester, _admin);
      await request(tester, FaresAdminAction.addCompany);
      expect(find.text('Add company'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Farinas Transit');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Company added.'), findsOneWidget);
      final companies = await companyRepo.loadAll();
      expect(companies.map((c) => c.name), contains('Farinas Transit'));
    });

    testWidgets('a non-admin request is ignored', (tester) async {
      await pumpTab(tester, _regular);
      await request(tester, FaresAdminAction.addRoute);
      expect(find.text('Add Route'), findsNothing);
      expect(faresAdminActionRequest.value, isNull);
    });
  });

  group('Map admin action requests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mapSetEndpointsRequest.value = false;
      mapLineMakerRequest.value = null;
    });

    tearDown(() {
      mapSetEndpointsRequest.value = false;
      mapLineMakerRequest.value = null;
    });

    Future<void> pumpMap(WidgetTester tester, AuthUser? user) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapTab(
              currentUser: user,
              customRouteRepository: LocalCustomRouteRepository(),
              fareOverrideRepository: LocalRouteFareOverrideRepository(),
              busStopRepository: LocalBusStopRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('set-endpoints request enters Set Start/End mode',
        (tester) async {
      await pumpMap(tester, _admin);
      mapSetEndpointsRequest.value = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.text('Tap the map to place the Start pin'),
        findsOneWidget,
      );
      expect(mapSetEndpointsRequest.value, isFalse);
    });

    testWidgets('draw-line request enters the line maker',
        (tester) async {
      await pumpMap(tester, _admin);
      mapLineMakerRequest.value = (drawLine: true, addStop: false);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.text('Tap the map to add points in order'),
        findsOneWidget,
      );
      expect(mapLineMakerRequest.value, isNull);
    });

    testWidgets('a non-admin set-endpoints request is ignored',
        (tester) async {
      await pumpMap(tester, _regular);
      mapSetEndpointsRequest.value = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.text('Tap the map to place the Start pin'),
        findsNothing,
      );
      expect(mapSetEndpointsRequest.value, isFalse);
    });
  });
}
