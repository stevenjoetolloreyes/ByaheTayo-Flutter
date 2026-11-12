// Fares home screen widgets — Dart side (Android only).
//
// DESIGN (why this shape): like the Schedule widget
// (schedule_widget_service.dart), the Dart side pushes the merged
// Popular Routes list as ONE JSON blob and the Kotlin providers
// render from it on every update (updatePeriodMillis 30 min). The
// single source of truth stays the SAME merged list the Fares tab
// reads — the built-in `popularRoutes` (fares_tab.dart) with the
// admin's Firestore overrides applied
// (`route_fare_overrides`, merged by RouteFareOverride), plus the
// admin-added custom routes (Firestore `custom_routes`), minus
// the hidden built-in routes (`hidden_routes`). Nothing here
// re-lists routes, so an admin fare edit, a new route, or a hide
// flows to the widget with the next sync call.
//
// DISTANCE + ETA COME FROM THE APP'S OWN MODELS, NOT THE
// PREVIEW: the approved preview v1 (Nov 11, 2026) showed
// "1 hr 10 mins, 32.3 km" for Cabugao → Vigan. The 32.3 km was
// the LIVE OSRM road distance from the Fares detail sheet; the
// widget cannot fetch OSRM, so it shows the distance the Fares
// LIST card shows — the formula road distance ("≈ 31.6 km",
// haversine × 1.22, PopularRoute.roadKm) — and the ETA from the
// app's own estimateTripMinutes model (hubPairEtaMinutes /
// transitEtaMinutes), which gives the same "1 hr 10 min" for
// Cabugao → Vigan. The "≈" prefix is the list card's own marker
// for a formula distance.
//
// NO INVENTED ROUTES OR FARES: only the merged list is pushed.
// A route with no fare carries fare: null and shows "Fare not
// set" — never a sample. The big widget lists the first three
// routes in Fares-tab order (Cabugao → Vigan, Cabugao → San
// Juan, Sinait → Cabugao today); no route is invented to fill
// the list. The "Minimum fare ₱20" footer is Steven's Nov 11
// fare rule, stated in the preview — a rule, not a figure from
// data.
//
// TAP: tapping either widget opens the app's Fares tab. The
// Kotlin providers launch the app with the `homewidget://fares`
// URI (HomeWidgetLaunchIntent) and the app root listens for it
// (see _EstudyanteGOAppState in main.dart) — only when the
// dashboard is showing (signed in, profile done); on the sign-in
// or setup screens the tap just opens the app.
//
// The push is best-effort and never throws: widget tests run
// without the plugin or Firebase, and the Fares tab must never
// break because the widget plugin is unavailable. The provider
// shows an honest empty state ("Open EstudyanteGO to load
// fares.") when no fare data has been pushed yet. Firestore loads
// are time-boxed (8 s) and fall back to the same local caches
// the Fares tab falls back to, so an offline sync still pushes
// the last loaded routes.
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:home_widget/home_widget.dart';

import '../custom_routes.dart';
import '../fares_tab.dart';
import '../hidden_routes.dart';
import '../route_fare_overrides.dart';

/// One route as the widget understands it: endpoints + vehicle +
/// operator + fares + formula distance + ETA. All figures are the
/// Fares tab's own values (see the file header); a null fare means
/// "Fare not set", a null distance/ETA means the endpoints are not
/// known hubs and no figure is guessed.
class FaresWidgetRoute {
  const FaresWidgetRoute({
    required this.from,
    required this.to,
    required this.vehicle,
    this.operator,
    this.fare,
    this.studentFare,
    this.distanceKm,
    this.etaMin,
  });

  factory FaresWidgetRoute.fromPopular(PopularRoute route) {
    final roadKm = route.roadKm;
    int? etaMin;
    if (roadKm != null) {
      final fromHub = hubByName(route.from);
      final toHub = hubByName(route.to);
      etaMin = fromHub != null && toHub != null
          ? hubPairEtaMinutes(from: fromHub, to: toHub, roadKm: roadKm)
          : transitEtaMinutes(roadKm: roadKm);
    }
    return FaresWidgetRoute(
      from: route.from,
      to: route.to,
      vehicle: route.vehicle,
      operator: route.operator,
      fare: route.fare,
      studentFare: route.effectiveStudentFare,
      distanceKm: roadKm,
      etaMin: etaMin,
    );
  }

  factory FaresWidgetRoute.fromJson(Map<String, dynamic> json) {
    final from = json['from'];
    final to = json['to'];
    final vehicle = json['vehicle'];
    final operator = json['operator'];
    final fare = json['fare'];
    final studentFare = json['studentFare'];
    final distanceKm = json['distanceKm'];
    final etaMin = json['etaMin'];
    if (from is! String ||
        to is! String ||
        vehicle is! String ||
        (operator != null && operator is! String) ||
        (fare != null && fare is! num) ||
        (studentFare != null && studentFare is! num) ||
        (distanceKm != null && distanceKm is! num) ||
        (etaMin != null && etaMin is! num)) {
      throw const FormatException('Fares widget route is malformed');
    }
    return FaresWidgetRoute(
      from: from,
      to: to,
      vehicle: vehicle,
      operator: operator as String?,
      fare: (fare as num?)?.toDouble(),
      studentFare: (studentFare as num?)?.toDouble(),
      distanceKm: (distanceKm as num?)?.toDouble(),
      etaMin: (etaMin as num?)?.toInt(),
    );
  }

  final String from;
  final String to;
  final String vehicle;
  final String? operator;
  final double? fare;
  final double? studentFare;
  final double? distanceKm;
  final int? etaMin;

  /// "Cabugao → Vigan Bus Terminal" — the route line the Fares
  /// list card shows.
  String get title => '$from → $to';

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'vehicle': vehicle,
        'operator': operator,
        'fare': fare,
        'studentFare': studentFare,
        'distanceKm': distanceKm,
        'etaMin': etaMin,
      };

  @override
  bool operator ==(Object other) =>
      other is FaresWidgetRoute &&
      other.from == from &&
      other.to == to &&
      other.vehicle == vehicle &&
      other.operator == operator &&
      other.fare == fare &&
      other.studentFare == studentFare &&
      other.distanceKm == distanceKm &&
      other.etaMin == etaMin;

  @override
  int get hashCode => Object.hash(
        from,
        to,
        vehicle,
        operator,
        fare,
        studentFare,
        distanceKm,
        etaMin,
      );
}

/// The whole fares payload the providers read: the merged Popular
/// Routes list in Fares-tab order.
class FaresWidgetData {
  const FaresWidgetData({this.routes = const []});

  factory FaresWidgetData.fromJson(Map<String, dynamic> json) {
    final routes = json['routes'];
    if (routes is! List) {
      throw const FormatException('Fares widget data is malformed');
    }
    return FaresWidgetData(
      routes: routes
          .map((e) => FaresWidgetRoute.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<FaresWidgetRoute> routes;

  /// The featured route for the small widget: the first route in
  /// Fares-tab order (Cabugao → Vigan today). Null when the list
  /// is empty.
  FaresWidgetRoute? get featured => routes.isEmpty ? null : routes.first;

  /// The routes the big widget lists, in Fares-tab order.
  List<FaresWidgetRoute> top(int count) => routes.take(count).toList();

  Map<String, dynamic> toJson() => {
        'routes': routes.map((r) => r.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is FaresWidgetData && _routesEqual(other.routes, routes);

  @override
  int get hashCode => Object.hashAll(routes);
}

bool _routesEqual(List<FaresWidgetRoute> a, List<FaresWidgetRoute> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class FaresWidgetService {
  FaresWidgetService._();

  /// SharedPreferences key (inside the home_widget store) holding
  /// the fares JSON both providers read.
  static const String dataKey = 'fares_widget_data';

  /// Small 4x2 "Fares" provider (featured route).
  static const String providerName = 'FaresWidgetProvider';
  static const String providerQualifiedName =
      'com.estudyantego.app.FaresWidgetProvider';

  /// Big 4x3 "Popular Routes" provider.
  static const String popularProviderName = 'FaresPopularWidgetProvider';
  static const String popularProviderQualifiedName =
      'com.estudyantego.app.FaresPopularWidgetProvider';

  /// URI the providers launch with on tap. The app root listens
  /// for it (HomeWidget.widgetClicked /
  /// initiallyLaunchedFromHomeWidget) and opens the Fares tab
  /// when the dashboard is showing.
  static const String faresUri = 'homewidget://fares';

  /// Shown by the providers when no fare data has been pushed
  /// yet. (The Kotlin side carries the same wording; keep them in
  /// sync.)
  static const String emptyTitle = 'Open EstudyanteGO to load fares.';
  static const String emptySubtitle =
      'Fares load from the Fares tab when the app opens.';

  /// Shown by the providers for a route with no fare set. (The
  /// Kotlin side carries the same wording; keep them in sync.)
  static const String fareNotSet = 'Fare not set';

  /// Steven's fare rule (Nov 11, 2026): the minimum fare is ₱20.
  /// Shown as the big widget's footer, as in the approved
  /// preview. (The Kotlin side carries the same wording.)
  static const String minFareLabel = 'Minimum fare ₱20';

  /// How many routes the small widget's featured slot and the big
  /// widget's list show. The payload carries at most [maxRoutes]
  /// so the pushed JSON stays small.
  static const int maxRoutes = 8;
  static const int bigListCount = 3;

  /// How long a Firestore load may take before the sync falls
  /// back to the local caches (the same caches the Fares tab
  /// falls back to).
  static const Duration firestoreTimeout = Duration(seconds: 8);

  /// Pure: the merged Popular Routes list, in exactly the Fares
  /// tab's order — built-ins with overrides applied (hidden ones
  /// dropped), then admin-added custom routes. Mirrors
  /// [_FaresTabState._allPopularRoutes] in fares_tab.dart; the
  /// two must agree, or the widget and the Fares tab disagree
  /// about the routes.
  static List<PopularRoute> mergedRoutes(
    List<CustomRoute> customs,
    Map<String, RouteFareOverride> overrides,
    Set<String> hidden,
  ) => [
        for (final route in popularRoutes)
          if (!hidden.contains(seededRouteKey(route.from, route.to)))
            route.applyOverride(
              overrides[seededRouteKey(route.from, route.to)],
            ),
        for (final route in customs) popularRouteFromCustomRoute(route),
      ];

  /// Pure: encodes the widget payload from the merged inputs.
  static String encodeData(
    List<CustomRoute> customs,
    Map<String, RouteFareOverride> overrides,
    Set<String> hidden,
  ) {
    final routes = mergedRoutes(customs, overrides, hidden)
        .take(maxRoutes)
        .map(FaresWidgetRoute.fromPopular)
        .toList();
    return jsonEncode(FaresWidgetData(routes: routes).toJson());
  }

  /// Decodes a pushed payload. Returns null for null, empty,
  /// non-map, or malformed JSON — the provider treats that as "no
  /// data yet" and shows the empty state, never a crash.
  static FaresWidgetData? decodeData(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return FaresWidgetData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Loads the admin-added custom routes: Firestore first
  /// (time-boxed), then the local cache — the same load the Fares
  /// tab does, and the same fallback it uses offline. Never
  /// throws.
  ///
  /// Firestore is attempted ONLY when Firebase was initialized
  /// (the same `isConfigured` the app host uses to pick the
  /// Firestore repositories for the Fares tab). Without that gate
  /// the `.timeout()` below creates an 8-second Timer that never
  /// fires in widget tests (fake_async reports it as a pending
  /// timer and fails the test) — the tab never attempts Firestore
  /// when unconfigured, and neither does the widget.
  static bool get _firestoreConfigured {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<List<CustomRoute>> _loadCustomRoutes() async {
    if (_firestoreConfigured) {
      try {
        return await FirestoreCustomRouteRepository()
            .loadAll()
            .timeout(firestoreTimeout);
      } catch (_) {
        // Fall through to the local cache below.
      }
    }
    try {
      return await LocalCustomRouteRepository().loadAll();
    } catch (_) {
      return const [];
    }
  }

  /// Loads the fare overrides the same way.
  static Future<Map<String, RouteFareOverride>> _loadOverrides() async {
    if (_firestoreConfigured) {
      try {
        return await FirestoreRouteFareOverrideRepository()
            .loadAll()
            .timeout(firestoreTimeout);
      } catch (_) {
        // Fall through to the local cache below.
      }
    }
    try {
      return await LocalRouteFareOverrideRepository().loadAll();
    } catch (_) {
      return const {};
    }
  }

  /// Loads the hidden built-in route keys the same way.
  static Future<Set<String>> _loadHidden() async {
    if (_firestoreConfigured) {
      try {
        return await FirestoreHiddenRouteRepository()
            .loadAll()
            .timeout(firestoreTimeout);
      } catch (_) {
        // Fall through to the local cache below.
      }
    }
    try {
      return await LocalHiddenRouteRepository().loadAll();
    } catch (_) {
      return const {};
    }
  }

  /// Pushes the merged routes to the widget store, then asks BOTH
  /// providers to refresh. The payload is written in ONE
  /// saveWidgetData call, so a refresh can never leave one widget
  /// showing new fares with old routes. Best-effort: never
  /// throws, so callers (Fares tab loads, app start) can
  /// fire-and-forget it.
  static Future<void> sync() async {
    try {
      final customs = await _loadCustomRoutes();
      final overrides = await _loadOverrides();
      final hidden = await _loadHidden();
      await HomeWidget.saveWidgetData<String>(
          dataKey, encodeData(customs, overrides, hidden));
      await HomeWidget.updateWidget(
        androidName: providerName,
        qualifiedAndroidName: providerQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: popularProviderName,
        qualifiedAndroidName: popularProviderQualifiedName,
      );
    } catch (_) {
      // No widget plugin (tests, iOS) or a platform failure: the
      // Fares tab and app start must keep working either way.
    }
  }
}
