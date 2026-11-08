// Tests for the About EstudyanteGO screen (Nov 8).
//
// The stats graph shows REAL live counts only: routes = built-in
// popular routes + admin-added custom routes, hubs = built-in hubs,
// cities = bundled Philippines places. Nothing hardcoded, nothing
// invented — no downloads, no user counts anywhere. The About copy
// is descriptive only and never claims features the app does not
// have.
import 'package:estudyantego/features/about_screen.dart';
import 'package:estudyantego/features/bus_stops.dart';
import 'package:estudyantego/features/custom_routes.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCustomRouteRepository implements CustomRouteRepository {
  _FakeCustomRouteRepository(this.routes);

  final List<CustomRoute> routes;

  @override
  Future<List<CustomRoute>> loadAll() async => routes;

  @override
  Future<CustomRoute> create(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<CustomRoute> update(
    CustomRoute route,
    AuthUser author, {
    List<BusStop> busStops = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(CustomRoute route, AuthUser author) =>
      throw UnimplementedError();
}

const _routeA = CustomRoute(
  from: 'Cabugao',
  to: 'Vigan Bus Terminal',
  operator: 'Partas',
  vehicle: 'Bus',
  fare: 60,
);
const _routeB = CustomRoute(
  from: 'Laoag Terminal',
  to: 'Vigan Bus Terminal',
  operator: 'Partas',
  vehicle: 'Bus',
  fare: 100,
);

Future<void> _pumpAbout(
  WidgetTester tester, {
  CustomRouteRepository? repo,
  VoidCallback? onBack,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AboutEstudyanteGOScreen(
          onBack: onBack ?? () {},
          customRouteRepository: repo,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('computeAppStats counts live data, never hardcoded numbers', () {
    // Built-in data, no custom routes: 7 seeded routes, 16 hubs,
    // 164 bundled places.
    var stats = computeAppStats(customRouteCount: 0);
    expect(stats.routes, 7);
    expect(stats.hubs, 16);
    expect(stats.cities, 164);

    // Admin-added routes add to the routes count, nothing else moves.
    stats = computeAppStats(customRouteCount: 2);
    expect(stats.routes, 9);
    expect(stats.hubs, 16);
    expect(stats.cities, 164);
  });

  testWidgets('graph shows live counts with custom routes',
      (WidgetTester tester) async {
    await _pumpAbout(
      tester,
      repo: _FakeCustomRouteRepository([_routeA, _routeB]),
    );

    expect(find.text('App stats'), findsOneWidget);
    // Routes = 7 built-in + 2 admin-added; hubs and cities are the
    // live built-in / bundled counts.
    expect(find.text('Routes'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Hubs'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('Cities & towns'), findsOneWidget);
    expect(find.text('164'), findsOneWidget);
    // The caption names each count's source.
    expect(
      find.textContaining('built-in routes plus routes added by an admin'),
      findsOneWidget,
    );
    expect(find.textContaining('bundled Philippines list'), findsOneWidget);
  });

  testWidgets('graph shows built-in counts without a repository',
      (WidgetTester tester) async {
    await _pumpAbout(tester);

    expect(find.text('App stats'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('164'), findsOneWidget);
  });

  testWidgets('About copy sections all render, no invented numbers',
      (WidgetTester tester) async {
    await _pumpAbout(
      tester,
      repo: _FakeCustomRouteRepository(const []),
    );

    expect(find.text('EstudyanteGO'), findsOneWidget);
    expect(
      find.text('Kasama mo sa araw-araw na eskwela'),
      findsOneWidget,
    );
    expect(find.text('Version 1.0.0 · com.estudyantego.app'), findsOneWidget);
    expect(find.text('What is EstudyanteGO?'), findsOneWidget);
    expect(find.text('Fares'), findsOneWidget);
    expect(find.text('Routes & map'), findsOneWidget);
    expect(find.text('Study tools'), findsOneWidget);
    expect(find.text('Communities'), findsOneWidget);
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('Made by a student, for students'), findsOneWidget);
    expect(find.text('ESTUDYANTEGO · VERSION 1.0.0'), findsOneWidget);
    // No invented statistics anywhere on the screen.
    expect(find.textContaining('download'), findsNothing);
    expect(find.textContaining('users'), findsNothing);
    // The Privacy Policy is NOT part of the About screen (Steven,
    // Nov 8: it stays separate) — its content must not appear here.
    expect(find.text('Privacy Policy'), findsNothing);
  });

  testWidgets('back button calls onBack', (WidgetTester tester) async {
    var backCount = 0;
    await _pumpAbout(
      tester,
      repo: _FakeCustomRouteRepository(const []),
      onBack: () => backCount++,
    );

    await tester.tap(find.byTooltip('Back to Account'));
    await tester.pumpAndSettle();
    expect(backCount, 1);
  });
}
