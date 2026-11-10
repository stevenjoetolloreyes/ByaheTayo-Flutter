// Fares tab — Trip picker + Popular Routes.
//
// Nov 7, 2026 (Steven): the fare calculator (Sasakyan card, result
// card, estimate disclaimer), Added routes, and Posted operator fares
// sections were removed at his request. What remains is the Trip
// picker (From/To + Find routes to the Map tab) and the Popular
// Routes list with their fare breakdown sheets. The LTFRB formula
// below (same 11 vehicle rates, same 16 hubs, straight-line distance
// + 22% road allowance) still powers those breakdown sheets and the
// Map/Trips path. No dummy data: every number shown comes from the
// rate table below or from the distance the user actually picked.
import 'dart:math' as math;

import 'top_popup.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'add_route_sheet.dart';
import 'admin_access.dart';
import 'app_layout.dart';
import 'app_rating.dart';
import 'bus_companies.dart';
import 'bus_stops.dart';
import 'custom_routes.dart';
import 'hidden_routes.dart';
import 'ios_components.dart';
import 'minecraft_tap_animation.dart';
import 'minecraft_theme.dart';
import 'onboarding/auth_service.dart';
import 'operator_fares.dart';
import 'place_picker.dart';
import 'route_fare_overrides.dart';

// Fares-local ChatGPT design tokens (Premium Dark + Emerald Green,
// adopted Nov 5 as a LOOSE UI base). Tab-local on purpose: the shared
// AppLayout/AppText scale is used by other tabs and stays untouched.
// Only the tokens this tab actually uses are defined here.
const kFaresDarkCard = Color(0xFF202B25);
const kFaresCardRadius = 20.0;
const kFaresInputRadius = 14.0;
const kFaresPageTitle = TextStyle(fontSize: 26, fontWeight: FontWeight.w800);
const kFaresCardHeading = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

/// ChatGPT dark card surface (#202B25); light cards stay white.
Color _faresCardColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? kFaresDarkCard
      : Colors.white;
}

/// Brand tokens (Nov 5 emerald system, shared with the preview):
/// Deep Emerald #14532D and accent #16A34A.
const kFaresDeepEmerald = Color(0xFF14532D);
const kFaresAccent = Color(0xFF16A34A);

/// 20% off, rounded to the nearest ₱0.25 — the same rule
/// [computeFare] uses for a discounted fare.
double discountedFareOf(double fare) => (fare * 0.8 * 4).round() / 4;

/// Fares → Map jump (preview parity: "Find routes" / "Show
/// direction on Map" open the Map tab WITH the selected route,
/// not just the tab). Set to the route's From/To before switching
/// tabs; MapTab consumes it once and clears it — the same pattern
/// as [communityMapJump] in community_posts.dart. `from` may be
/// 'My location' when the calculator's origin is the GPS position;
/// the Map tab resolves that to the device location (else the home
/// hub), exactly like its hub-tap flow.
/// A Fares → Map jump: the Map tab draws this route when the
/// value is set. [fromLat]/[fromLng] carry the device position
/// when the jump's origin is 'My location' (J2, Nov 7, 2026) —
/// without them the Map silently retargeted to the home hub.
/// Null when the origin is a hub (the Map resolves it by name).
/// [startLive] asks the Map tab to start Live Follow on the
/// jumped route (Start Ride, Nov 8, 2026) — false for a plain jump.
final faresMapJump =
    ValueNotifier<
      ({
        String from,
        String to,
        double? fromLat,
        double? fromLng,
        bool startLive,
      })?
    >(null);

/// Web formatTripTime, mirrored here so the Fares sheet can show an
/// ETA without importing map_tab.dart (which imports this file):
/// "45 min" / "1 hr 10 min". Keep in sync with map_tab.dart.
String formatTripTimeShort(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins min';
  if (mins == 0) return '$hours hr';
  return '$hours hr $mins min';
}

/// One route in the "Popular Routes" list (preview design, ported
/// Nov 6, 2026). Only REAL routes are listed here:
///
/// * Verified fares come from the Oct 16, 2026 user-verified trips
///   (the same pairs as `knownBusFares` in map_tab.dart — that table
///   stays the source of truth for the Map/Trips path; the values
///   below are copied from it, never re-derived).
/// * Routes Steven asked for by name with no fare yet (Partas Laoag
///   → Cubao, GMW Bantay → Tuguegarao, Vigan Bus Terminal → San
///   Juan, Laoag Terminal → Vigan Bus Terminal) carry `fare: null`
///   and show "Fare not set" — never a sample.
/// * The preview's SAMPLE fares are deliberately NOT here: ₱45
///   Vigan → San Juan, ₱120 Laoag → Vigan, ₱40/₱13/₱7 breakdown,
///   and the Dominion Van Cabugao → Vigan ₱60 (operator and fare
///   both sample-only) are all omitted.
/// * `operator` is set ONLY where Steven named the operator
///   (Partas, GMW Trans). The verified ₱60/₱20 trips were reported
///   as "bus" with no company named, so they carry no operator —
///   the operator filter only ever matches a named operator.
class PopularRoute {
  const PopularRoute({
    required this.from,
    required this.to,
    required this.vehicle,
    this.operator,
    this.fare,
    this.studentFare,
    this.pwdFare,
    this.seniorFare,
    this.fareLabel,
    this.distanceKm,
    this.distanceNote,
    this.viaHubs = const [],
    this.customRouteId,
    this.createdAt,
  });

  /// Endpoint names as shown on the card. Hub names (members of
  /// [hubs]) let the route load into the calculator; other names
  /// (e.g. 'Laoag Partas Terminal') are display-only.
  final String from;
  final String to;

  /// One of 'Bus', 'Van', 'Jeepney', 'Tricycle'.
  final String vehicle;

  /// Bus company, or null when no operator was verified/named.
  final String? operator;

  /// The route's own fare in pesos, or null when no fare is set.
  final double? fare;

  /// The student fare in pesos, set by an admin — or null to
  /// derive 20% off [fare] (see [effectiveStudentFare]).
  final double? studentFare;

  /// The PWD fare in pesos, set by an admin — or null to
  /// derive 20% off [fare] (see [effectivePwdFare]).
  final double? pwdFare;

  /// The Senior Citizen fare in pesos, set by an admin — or
  /// null to derive 20% off [fare] (see [effectiveSeniorFare]).
  final double? seniorFare;

  /// Label for [fare] when set, e.g. 'Verified bus fare'.
  final String? fareLabel;

  /// Road distance in km when known without the calculator
  /// (only the GMW route, measured on the preview map Nov 6,
  /// 2026). Hub routes compute it from hub coordinates instead.
  final double? distanceKm;

  /// Where [distanceKm] came from, when it is a stored value.
  final String? distanceNote;

  /// Ordered via-stops of an admin-added custom route (the admin's
  /// own line). Empty for built-in routes.
  final List<String> viaHubs;

  /// The admin-added route's id, when this came from
  /// [popularRouteFromCustomRoute]; null for built-in routes.
  final String? customRouteId;

  /// When this route was created, for 'Newest Routes' sorting —
  /// set for admin-added routes ([CustomRoute.createdAt]); null
  /// for the built-in routes, which have no creation date (none
  /// is invented).
  final DateTime? createdAt;

  bool get isBus => vehicle == 'Bus';

  /// The student fare to show: the admin-set [studentFare] when
  /// present, otherwise 20% off [fare] — null when no fare is set.
  double? get effectiveStudentFare {
    if (fare == null) return null;
    return studentFare ?? discountedFareOf(fare!);
  }

  /// The PWD fare to show: the admin-set [pwdFare] when present,
  /// otherwise 20% off [fare] — null when no fare is set. Same
  /// pattern as [effectiveStudentFare].
  double? get effectivePwdFare {
    if (fare == null) return null;
    return pwdFare ?? discountedFareOf(fare!);
  }

  /// The Senior Citizen fare to show: the admin-set [seniorFare]
  /// when present, otherwise 20% off [fare] — null when no fare
  /// is set. Same pattern as [effectiveStudentFare].
  double? get effectiveSeniorFare {
    if (fare == null) return null;
    return seniorFare ?? discountedFareOf(fare!);
  }

  /// A copy of this route with an admin's [RouteFareOverride]
  /// merged in (built-in routes only — custom routes carry their
  /// own fare/student fare). Null override = unchanged.
  PopularRoute applyOverride(RouteFareOverride? override) {
    if (override == null) return this;
    return PopularRoute(
      from: from,
      to: to,
      vehicle: vehicle,
      operator: operator,
      fare: override.fare ?? fare,
      studentFare: override.studentFare ?? studentFare,
      pwdFare: override.pwdFare ?? pwdFare,
      seniorFare: override.seniorFare ?? seniorFare,
      fareLabel: override.fare != null ? 'Admin-set fare' : fareLabel,
      distanceKm: distanceKm,
      distanceNote: distanceNote,
      viaHubs: override.viaHubs == null || override.viaHubs!.isEmpty
          ? viaHubs
          : override.viaHubs!,
      customRouteId: customRouteId,
      createdAt: createdAt,
    );
  }

  /// True when both endpoints are hubs, so the route can load
  /// into the calculator and show a formula breakdown.
  bool get hasHubEndpoints => hubByName(from) != null && hubByName(to) != null;

  /// Road distance for hub routes (straight-line × 1.22, the
  /// calculator's rule); the stored [distanceKm] otherwise.
  double? get roadKm {
    if (distanceKm != null) return distanceKm;
    final fromHub = hubByName(from);
    final toHub = hubByName(to);
    if (fromHub == null || toHub == null) return null;
    return math.max(
      0.1,
      haversineKm(fromHub.lat, fromHub.lng, toHub.lat, toHub.lng) * 1.22,
    );
  }
}

/// Built-in Popular Routes: verified fares first, then Steven's
/// named no-fare routes. Admin-added custom routes are appended
/// at runtime (see [_FaresTabState._allPopularRoutes]).
const popularRoutes = <PopularRoute>[
  // Cabugao → Vigan Bus Terminal, bus ₱60 (verified Oct 16, 2026;
  // knownBusFares 'Cabugao|Vigan Bus Terminal'). 20% off = ₱48.
  PopularRoute(
    from: 'Cabugao',
    to: 'Vigan Bus Terminal',
    vehicle: 'Bus',
    fare: 60,
    fareLabel: 'Verified bus fare',
  ),
  // Cabugao → San Juan, Ilocos Sur, bus ₱20 (verified Oct 16, 2026).
  PopularRoute(
    from: 'Cabugao',
    to: 'San Juan, Ilocos Sur',
    vehicle: 'Bus',
    fare: 20,
    fareLabel: 'Verified bus fare',
  ),
  // Sinait → Cabugao, bus ₱20 (verified Oct 16, 2026).
  PopularRoute(
    from: 'Sinait',
    to: 'Cabugao',
    vehicle: 'Bus',
    fare: 20,
    fareLabel: 'Verified bus fare',
  ),
  // Vigan Bus Terminal → San Juan: Steven's requested route (Nov 6).
  // No verified fare — the preview's ₱45 sample is NOT used.
  PopularRoute(
    from: 'Vigan Bus Terminal',
    to: 'San Juan, Ilocos Sur',
    vehicle: 'Bus',
  ),
  // Laoag Terminal → Vigan Bus Terminal: Steven's requested route
  // (Nov 6). No verified fare — the preview's ₱120 sample is NOT used.
  PopularRoute(
    from: 'Laoag Terminal',
    to: 'Vigan Bus Terminal',
    vehicle: 'Bus',
  ),
  // Laoag Partas Terminal → Cubao Partas Terminal (Partas):
  // Steven's requested route (Nov 6). Fare not set.
  PopularRoute(
    from: 'Laoag Partas Terminal',
    to: 'Cubao Partas Terminal',
    operator: 'Partas',
    vehicle: 'Bus',
  ),
  // Bantay GMW Terminal → Tuguegarao GMW Terminal (GMW Trans):
  // Steven's requested route (Nov 6). Fare not set. The 401.0 km
  // road distance was measured on the preview map (OSRM road path,
  // Nov 6, 2026); the 6 hr 28 min preview duration is NOT carried
  // over — the app's ETA model lives in map_tab.dart and is not
  // duplicated here.
  PopularRoute(
    from: 'Bantay GMW Terminal',
    to: 'Tuguegarao GMW Terminal',
    operator: 'GMW Trans',
    vehicle: 'Bus',
    distanceKm: 401.0,
    distanceNote: 'Road distance from the preview map, Nov 6, 2026.',
  ),
];

/// Vehicle filter chips (preview order).
const vehicleFilters = <String>['All', 'Bus', 'Van', 'Jeepney', 'Tricycle'];

/// Whether [routeOperator] matches the operator chip [chip].
/// 'All' matches everything (including routes with no operator);
/// a named chip matches when either name contains the other, so
/// short chip labels match the app's full operator names
/// ('Dominion' ↔ 'Dominion Bus Lines', 'ALPS' ↔ 'ALPS The Bus',
/// 'GV Florida' ↔ 'GV Florida Transport'). Routes with no
/// operator never match a named chip.
bool popularRouteMatchesOperator(String? routeOperator, String chip) {
  if (chip == 'All') return true;
  if (routeOperator == null) return false;
  final route = routeOperator.toLowerCase();
  final want = chip.toLowerCase();
  return route.contains(want) || want.contains(route);
}

/// Filters [routes] by vehicle, operator, region, and province.
/// Pure, so the filter behaviour is unit-testable without widgets.
/// The categories combine (AND). The operator filter only applies
/// while the Bus vehicle chip is active (see the operator
/// dropdown); the region and province matches are either
/// endpoint. The Fare filter was removed (Nov 8, 2026 redesign)
/// — fare information still shows on the route cards and
/// breakdown sheets, it is just no longer a filter.
List<PopularRoute> filterPopularRoutes(
  List<PopularRoute> routes, {
  required String vehicle,
  required String operator,
  String region = 'All',
  String province = 'All',
  List<BusStop> busStops = const [],
}) {
  return routes.where((route) {
    if (vehicle != 'All' && route.vehicle != vehicle) return false;
    if (vehicle == 'Bus' &&
        operator != 'All' &&
        !popularRouteMatchesOperator(route.operator, operator)) {
      return false;
    }
    if (!popularRouteMatchesRegion(route, region, busStops)) {
      return false;
    }
    if (!popularRouteMatchesProvince(route, province, busStops)) {
      return false;
    }
    return true;
  }).toList();
}

/// Whether [route] touches [region] at either endpoint. 'All'
/// matches everything (including routes with an unknown endpoint
/// region); a named region matches when the origin's OR the
/// destination's ADMINISTRATIVE region equals it (see
/// [administrativeRegionOfEndpoint]). Either endpoint (not just
/// the origin): a route connects two places, and a user browsing
/// a region wants every route that touches it.
bool popularRouteMatchesRegion(
  PopularRoute route,
  String region,
  List<BusStop> busStops,
) {
  if (region == 'All') return true;
  return administrativeRegionOfEndpoint(route.from, busStops) == region ||
      administrativeRegionOfEndpoint(route.to, busStops) == region;
}

/// Whether [route] touches [province] at either endpoint. 'All'
/// matches everything; a named province matches when the origin's
/// OR the destination's province equals it (see
/// [provinceOfRouteEndpoint]).
bool popularRouteMatchesProvince(
  PopularRoute route,
  String province,
  List<BusStop> busStops,
) {
  if (province == 'All') return true;
  return provinceOfRouteEndpoint(route.from, busStops) == province ||
      provinceOfRouteEndpoint(route.to, busStops) == province;
}

/// Distinct operators on [routes] (Bus routes only — the operator
/// filter applies to Bus routes), first-seen order. Routes with
/// no operator are skipped. From the data, never hardcoded: an
/// operator with no route is never offered.
List<String> routeOperators(List<PopularRoute> routes) {
  final seen = <String>{};
  final out = <String>[];
  for (final route in routes) {
    if (!route.isBus) continue;
    final operator = route.operator;
    if (operator == null || operator.isEmpty) continue;
    if (seen.add(operator)) out.add(operator);
  }
  return out;
}

/// Sort orders for Popular Routes. 'Most Popular' is the list's
/// own order (the Popular Routes list IS the popularity order —
/// no popularity metric exists in the data). 'Lowest Fare' is
/// fare ascending, routes with no fare last. 'Newest Routes' is
/// admin-added routes first (newest [PopularRoute.createdAt]
/// first), then the built-in routes in their own order — the
/// built-ins have no creation date, so none is invented.
const sortByOptions = <String>['Most Popular', 'Lowest Fare', 'Newest Routes'];

/// Orders [routes] by [sortBy]. Pure, so the sort behaviour is
/// unit-testable without widgets. Equal keys keep their relative
/// order (stable sort via the original index).
List<PopularRoute> sortPopularRoutes(List<PopularRoute> routes, String sortBy) {
  if (sortBy == 'Most Popular') return List<PopularRoute>.of(routes);
  final indexed = List<MapEntry<int, PopularRoute>>.generate(
    routes.length,
    (i) => MapEntry(i, routes[i]),
  );
  switch (sortBy) {
    case 'Lowest Fare':
      indexed.sort((a, b) {
        final aFare = a.value.fare;
        final bFare = b.value.fare;
        if (aFare == null && bFare == null) return a.key.compareTo(b.key);
        if (aFare == null) return 1;
        if (bFare == null) return -1;
        final byFare = aFare.compareTo(bFare);
        return byFare != 0 ? byFare : a.key.compareTo(b.key);
      });
    case 'Newest Routes':
      indexed.sort((a, b) {
        final aTime = a.value.createdAt;
        final bTime = b.value.createdAt;
        if (aTime == null && bTime == null) return a.key.compareTo(b.key);
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        final byTime = bTime.compareTo(aTime);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    default:
      return List<PopularRoute>.of(routes);
  }
  return [for (final entry in indexed) entry.value];
}

/// Display label for an administrative region in the Region
/// dropdown: the spec's "Region I – Ilocos Region" style. The
/// filter value stays the plain region name (the data value), so
/// matching works on data; only the label carries the prefix.
String regionDisplayLabel(String region) {
  if (region == 'All') return 'All Regions';
  return _regionDisplayLabels[region] ?? region;
}

const _regionDisplayLabels = <String, String>{
  'Ilocos Region': 'Region I – Ilocos Region',
  'Cagayan Valley': 'Region II – Cagayan Valley',
  'Central Luzon': 'Region III – Central Luzon',
  'CALABARZON': 'Region IV-A – CALABARZON',
  'MIMAROPA': 'MIMAROPA – Region IV-B',
  'Bicol Region': 'Region V – Bicol Region',
  'Western Visayas': 'Region VI – Western Visayas',
  'Central Visayas': 'Region VII – Central Visayas',
  'Eastern Visayas': 'Region VIII – Eastern Visayas',
  'Zamboanga Peninsula': 'Region IX – Zamboanga Peninsula',
  'Northern Mindanao': 'Region X – Northern Mindanao',
  'Davao Region': 'Region XI – Davao Region',
  'SOCCSKSARGEN': 'Region XII – SOCCSKSARGEN',
  'Caraga': 'Region XIII – Caraga',
  'Metro Manila': 'NCR – National Capital Region',
  'Cordillera Administrative Region': 'CAR – Cordillera Administrative Region',
  'BARMM': 'BARMM – Bangsamoro Autonomous Region',
};

/// 'N routes' / 'N of M' label for the Popular Routes header.
/// Just the count when nothing is filtered; 'X of Y' when a
/// filter hides routes, so the filter is visible at a glance.
/// The filtered form drops the noun: the header is 350px wide on
/// a 390px phone and 'Popular Routes' already takes 227px, so
/// '1 of 7 routes' (161px) overflows the row by 39px — '1 of 7'
/// fits, and the section title supplies the noun. Pure, so the
/// label is unit-testable.
String routesCountLabel({required int filtered, required int total}) {
  if (filtered == total) return '$total ${total == 1 ? 'route' : 'routes'}';
  return '$filtered of $total';
}

/// One admin-added route as a Popular Route (operator + fare are
/// the admin's own entries — never invented).
PopularRoute popularRouteFromCustomRoute(CustomRoute route) {
  return PopularRoute(
    from: route.from,
    to: route.to,
    operator: route.operator,
    vehicle: route.vehicle,
    fare: route.fare,
    studentFare: route.studentFare,
    pwdFare: route.pwdFare,
    seniorFare: route.seniorFare,
    fareLabel: 'Admin-entered fare',
    viaHubs: route.viaHubs,
    customRouteId: route.id,
    createdAt: route.createdAt,
  );
}

/// LTFRB table rate for a route's vehicle string — the rate the
/// breakdown sheet computes with (Fares × Map audit, Nov 7,
/// 2026: F5). Bus → prov-aircon, Jeepney → trad-jeep; Van /
/// Tricycle / anything else has no table rate, so the sheet
/// shows no breakdown instead of a wrong-rate number. This
/// mirrors [rateForVehicleString] in vehicle_categories.dart
/// (the canonical mapping) because fares_tab cannot import that
/// file — it imports fares_tab for [fareRates].
FareRate? rateForRouteVehicle(String vehicle) {
  final String? rateId;
  switch (vehicle) {
    case 'Bus':
      rateId = 'prov-aircon';
    case 'Jeepney':
      rateId = 'trad-jeep';
    default:
      rateId = null;
  }
  if (rateId == null) return null;
  for (final rate in fareRates) {
    if (rate.id == rateId) return rate;
  }
  return null;
}

/// Road distance for a route, resolving endpoints against the
/// merged hub list (built-ins + admin-added stops). Same ×1.22
/// rule as [PopularRoute.roadKm]; null when an endpoint is
/// unknown. [PopularRoute.roadKm] stays hubs-only (its tests pin
/// it); callers that hold stops use this. A custom route
/// ([customRoute]) uses its leg-summed distance instead —
/// From → via… → To (see [customRouteRoadKm]) — never the direct
/// endpoint-to-endpoint distance (Fares × Map audit, Nov 7,
/// 2026: F3).
double? popularRouteRoadKm(
  PopularRoute route,
  List<BusStop> stops, {
  CustomRoute? customRoute,
}) {
  if (route.distanceKm != null) return route.distanceKm;
  if (customRoute != null) return customRouteRoadKm(customRoute, stops);
  final fromHub = hubByName(route.from, stops);
  final toHub = hubByName(route.to, stops);
  if (fromHub == null || toHub == null) return null;
  return math.max(
    0.1,
    haversineKm(fromHub.lat, fromHub.lng, toHub.lat, toHub.lng) * 1.22,
  );
}

/// The fare breakdown of one calculator result, line by line, so
/// the fare breakdown sheet shows real arithmetic instead of the
/// preview's sample ₱40 + ₱13 + ₱7. Every field is derived from
/// the same inputs as [computeFare]; [regular] and [collected]
/// always equal the corresponding [FareResult] values.
class FareBreakdown {
  const FareBreakdown({
    required this.base,
    required this.bracket,
    required this.perKm,
    required this.billableKm,
    required this.distanceFare,
    required this.formulaFare,
    required this.minimumAdjustment,
    required this.regular,
    required this.discounted,
    required this.collected,
  });

  /// Base fare covering the first [bracket] km.
  final double base;

  /// Km covered by [base].
  final double bracket;

  /// Per-km charge after the bracket.
  final double perKm;

  /// Billable km: ceil(roadKm − bracket), never below 0.
  final int billableKm;

  /// [billableKm] × [perKm].
  final double distanceFare;

  /// [base] + [distanceFare], before any minimum.
  final double formulaFare;

  /// Amount the minimum added (0 when the formula already beats
  /// it): minimum − [formulaFare].
  final double minimumAdjustment;

  /// Fare before discount (minimum applied when it beats the
  /// formula).
  final double regular;

  /// Whether the 20% discount applies.
  final bool discounted;

  /// Amount to actually pay.
  final double collected;
}

/// Builds the breakdown for [rate] at [roadKm]. Returns null only
/// when there is no rate (the tricycle-local state has no fare to
/// break down).
FareBreakdown? fareBreakdownFor(FareRate rate, double roadKm, bool discounted) {
  final billableKm = math.max(0, (roadKm - rate.bracket).ceil());
  final distanceFare = billableKm * rate.perKm;
  final formulaFare = rate.base + distanceFare;
  final minimumAdjustment = rate.minimum != null
      ? math.max(0.0, rate.minimum! - formulaFare)
      : 0.0;
  final regular = formulaFare + minimumAdjustment;
  final collected = discounted ? (regular * 0.8 * 4).round() / 4 : regular;
  return FareBreakdown(
    base: rate.base,
    bracket: rate.bracket,
    perKm: rate.perKm,
    billableKm: billableKm,
    distanceFare: distanceFare,
    formulaFare: formulaFare,
    minimumAdjustment: minimumAdjustment,
    regular: regular,
    discounted: discounted,
    collected: collected,
  );
}

/// One vehicle rate from the web calculator's fareRates table.
class FareRate {
  const FareRate({
    required this.id,
    required this.label,
    required this.base,
    required this.bracket,
    required this.perKm,
    this.minimum,
    this.local = false,
  });

  final String id;
  final String label;
  final double base;
  final double bracket;
  final double perKm;
  final double? minimum;
  final bool local;
}

/// The 11 rated modes. 'tricycle-local' is deliberately NOT here: it has
/// no rate and is handled as a special honest state in the UI.
const fareRates = <FareRate>[
  FareRate(
    id: 'trad-jeep',
    label: 'Traditional jeepney',
    base: 14,
    bracket: 4,
    perKm: 2,
  ),
  FareRate(
    id: 'modern-jeep',
    label: 'Modern jeepney',
    base: 17,
    bracket: 4,
    perKm: 2.4,
  ),
  FareRate(
    id: 'prov-ordinary',
    label: 'Ordinary provincial bus',
    base: 12,
    bracket: 5,
    perKm: 2.2,
    minimum: 100,
  ),
  FareRate(
    id: 'prov-aircon',
    label: 'Air-conditioned provincial bus',
    base: 12,
    bracket: 5,
    perKm: 2.45,
    minimum: 100,
  ),
  FareRate(
    id: 'prov-deluxe',
    label: 'Deluxe provincial bus',
    base: 12,
    bracket: 5,
    perKm: 2.6,
    minimum: 100,
  ),
  FareRate(
    id: 'prov-super',
    label: 'Super deluxe provincial bus',
    base: 12,
    bracket: 5,
    perKm: 2.7,
    minimum: 100,
  ),
  FareRate(
    id: 'prov-luxury',
    label: 'Luxury provincial bus',
    base: 12,
    bracket: 5,
    perKm: 3.35,
    minimum: 100,
  ),
  FareRate(
    id: 'city-ordinary',
    label: 'Ordinary city bus',
    base: 15,
    bracket: 5,
    perKm: 2.49,
    minimum: 20,
  ),
  FareRate(
    id: 'city-aircon',
    label: 'Air-conditioned city bus',
    base: 18,
    bracket: 5,
    perKm: 2.98,
  ),
  FareRate(
    id: 'dagupan-shared',
    label: 'Dagupan shared tricycle',
    base: 20,
    bracket: 2,
    perKm: 10,
    local: true,
  ),
  FareRate(
    id: 'dagupan-special',
    label: 'Dagupan special-hire tricycle',
    base: 30,
    bracket: 2,
    perKm: 10,
    local: true,
  ),
];

/// Result of [computeFare]: the undiscounted fare and the amount to
/// actually pay (same as regular unless [discounted] is true).
class FareResult {
  const FareResult({required this.regular, required this.collected});

  final double regular;
  final double collected;
}

/// Web formula, exactly: billable = max(0, ceil(distance - bracket));
/// formulaFare = base + billable * perKm; regular fare = max(minimum,
/// formulaFare) when a minimum exists; discounted = regular * 0.8
/// rounded to the nearest ₱0.25.
FareResult computeFare(FareRate rate, double distance, bool discounted) {
  final billable = math.max(0, (distance - rate.bracket).ceil());
  final formulaFare = rate.base + billable * rate.perKm;
  final regular = rate.minimum != null
      ? math.max(rate.minimum!, formulaFare)
      : formulaFare;
  final collected = discounted ? (regular * 0.8 * 4).round() / 4 : regular;
  return FareResult(regular: regular, collected: collected);
}

/// One supported hub, copied from the web app's places list.
class Hub {
  const Hub(this.name, this.region, this.lat, this.lng);

  final String name;
  final String region;
  final double lat;
  final double lng;
}

const hubs = <Hub>[
  Hub('Laoag City', 'Ilocos Region', 18.20207, 120.53721),
  Hub('Vigan City', 'Ilocos Region', 17.56138, 120.38564),
  Hub('Cabugao', 'Ilocos Sur', 17.78916, 120.45838),
  Hub('San Juan, Ilocos Sur', 'Ilocos Sur', 17.73979, 120.45719),
  Hub('Sinait', 'Ilocos Sur', 17.87538, 120.48078),
  Hub('San Fernando City', 'La Union', 16.59756, 120.30610),
  Hub('Dagupan City', 'Pangasinan', 16.04603, 120.34429),
  Hub('Baguio City', 'Cordillera Administrative Region', 16.40144, 120.59387),
  Hub('Bontoc', 'Mountain Province', 17.09071, 120.97601),
  Hub('Banaue', 'Ifugao', 16.92957, 121.05433),
  Hub('Tuguegarao City', 'Cagayan', 17.64215, 121.75457),
  Hub('Ilagan City', 'Isabela', 17.17717, 121.94163),
  Hub('Santiago City', 'Isabela', 16.70647, 121.54278),
  Hub('Bayombong', 'Nueva Vizcaya', 16.50537, 121.13958),
  // Vigan Bus Terminal (Jose Singson / Rivero, Vigan) is a SEPARATE
  // hub from 'Vigan City' — the city hub's name is used by community
  // posts and other screens, so it is kept as-is. The terminal is
  // the Vigan endpoint of the Cabugao bus (verified ₱60 trip) and
  // the default destination. Appended last so existing hub indices
  // do not shift.
  Hub('Vigan Bus Terminal', 'Ilocos Sur', 17.56641, 120.38590),
  // Laoag Terminal (RCJ Terminal, Fr. Castro Ave, Laoag City) —
  // separate from the 'Laoag City' hub for the same reason.
  Hub('Laoag Terminal', 'Ilocos Norte', 18.1958, 120.59062),
];

/// Straight-line distance in km (haversine), same as the web app's
/// distanceKm helper.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusKm * 2 * math.asin(math.sqrt(a));
}

/// Web peso(): ₱ + thousands separators, 2 decimals only when the value
/// has a fractional part.
String peso(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  if (parts[1] == '00') return '₱$intPart';
  return '₱$intPart.${parts[1]}';
}

/// One operator's posted fares, grouped by company. This is reference
/// data only: posted fares are never mixed with formula fares. The
/// "Posted operator fares" tab section that displayed these groups was
/// removed Nov 7, 2026 (Steven); the grouping stays for the verified
/// dataset and its tests.
class OperatorFareGroup {
  const OperatorFareGroup({
    required this.company,
    required this.fares,
    required this.sourceNote,
  });

  final String company;
  final List<OperatorFare> fares;
  final String sourceNote;
}

/// Display order for the reference section (dataset prominence order).
const operatorFareGroupOrder = <String>[
  'Partas',
  'Victory Liner',
  'JAC Liner',
  'ALPS The Bus',
  'Bicol Isarog',
];

/// Source note shown under each operator's group header. Kept short
/// and factual: post type + date, plus the caveats the sources
/// themselves carry (Partas drop-off note, Bicol Isarog comment
/// replies).
String operatorFareSourceNote(String company) {
  switch (company) {
    case 'Partas':
      return 'Official Facebook post, Oct 9, 2026. Exact fare depends on actual drop-off point.';
    case 'Victory Liner':
      return 'Official Facebook posts, Jan 17 and Jan 24, 2026.';
    case 'JAC Liner':
      return 'Official-account fare-guide flyer, May 26, 2026. Regular fares as printed.';
    case 'ALPS The Bus':
      return 'Official Facebook post, Sept 5, 2026.';
    case 'Bicol Isarog':
      return 'From the official account\u2019s own comment replies, Aug 26, 2026 \u2014 not the post body.';
    default:
      return 'Officially posted by the operator.';
  }
}

/// Groups [fares] by company in [operatorFareGroupOrder]; companies
/// not in the order list keep first-seen order after the known ones.
/// Grouping is lossless: every input fare appears in exactly one
/// group, and no fare is invented, estimated, or renamed.
List<OperatorFareGroup> groupOperatorFares([
  List<OperatorFare> fares = operatorFares,
]) {
  final byCompany = <String, List<OperatorFare>>{};
  for (final fare in fares) {
    byCompany.putIfAbsent(fare.company, () => []).add(fare);
  }
  final groups = <OperatorFareGroup>[];
  for (final company in operatorFareGroupOrder) {
    final group = byCompany.remove(company);
    if (group != null) {
      groups.add(
        OperatorFareGroup(
          company: company,
          fares: group,
          sourceNote: operatorFareSourceNote(company),
        ),
      );
    }
  }
  for (final entry in byCompany.entries) {
    groups.add(
      OperatorFareGroup(
        company: entry.key,
        fares: entry.value,
        sourceNote: operatorFareSourceNote(entry.key),
      ),
    );
  }
  return groups;
}

/// The result of [resetAllDirectionsPlan]: which stored
/// directions to clear, which overrides to save with the
/// direction removed, and which overrides to delete (they carry
/// nothing but a direction). Fares are never part of a reset.
class ResetAllDirectionsPlan {
  const ResetAllDirectionsPlan({
    required this.clearedCustoms,
    required this.clearedOverrides,
    required this.deletedOverrideKeys,
  });

  /// Admin-added routes whose saved direction is cleared (a
  /// copy with viaHubs + viaWaypoints emptied; fares untouched).
  final List<CustomRoute> clearedCustoms;

  /// Seeded-route overrides whose saved direction is cleared
  /// but which still carry a fare (saved back with the
  /// direction removed; fares untouched).
  final List<RouteFareOverride> clearedOverrides;

  /// Seeded-route override keys whose override carried ONLY a
  /// direction — clearing it empties the override, so the doc
  /// is deleted (a reset to the built-in route).
  final List<String> deletedOverrideKeys;

  /// Routes touched by the reset (custom + override saves +
  /// override deletes).
  int get affectedCount =>
      clearedCustoms.length +
      clearedOverrides.length +
      deletedOverrideKeys.length;

  bool get isEmpty => affectedCount == 0;
}

/// Plans a full reset of every saved direction (Steven, Nov 7,
/// 20:41: "Mag Reset Direction ka ako na gagawa New Line" +
/// "Lahat" — he draws the new lines himself). Clears BOTH
/// [CustomRoute.viaWaypoints] (drawn line points) AND
/// [CustomRoute.viaHubs] (named via stops) on every admin-added
/// route, and the same two fields on every seeded-route
/// override — a full reset to each route's generated/OSRM path.
/// Fares (regular / student / PWD / Senior) are NEVER changed:
/// an override that still carries a fare is saved back, one
/// that carried only a direction is deleted. Routes with no
/// saved direction are left alone (no-ops are skipped, so a
/// reset touches only what it must).
ResetAllDirectionsPlan resetAllDirectionsPlan({
  required List<CustomRoute> customs,
  required List<RouteFareOverride> overrides,
}) {
  final clearedCustoms = <CustomRoute>[];
  for (final route in customs) {
    if (route.viaHubs.isNotEmpty || route.viaWaypoints.isNotEmpty) {
      clearedCustoms.add(
        route.copyWith(viaHubs: const [], viaWaypoints: const []),
      );
    }
  }
  final clearedOverrides = <RouteFareOverride>[];
  final deletedOverrideKeys = <String>[];
  for (final override in overrides) {
    final hasDirection =
        (override.viaHubs?.isNotEmpty == true) ||
        (override.viaWaypoints?.isNotEmpty == true);
    if (!hasDirection) continue;
    final cleared = override.copyWith(
      viaHubs: const [],
      viaWaypoints: const [],
    );
    if (routeFareOverrideIsEmpty(cleared)) {
      deletedOverrideKeys.add(override.routeKey);
    } else {
      clearedOverrides.add(cleared);
    }
  }
  return ResetAllDirectionsPlan(
    clearedCustoms: clearedCustoms,
    clearedOverrides: clearedOverrides,
    deletedOverrideKeys: deletedOverrideKeys,
  );
}

enum _OriginMode { location, hub }

class FaresTab extends StatefulWidget {
  /// The signed-in user (null when signed out). Drives the
  /// admin-only Add Route entry point — see admin_access.dart.
  const FaresTab({
    super.key,
    this.currentUser,
    this.customRouteRepository,
    this.fareOverrideRepository,
    this.hiddenRouteRepository,
    this.busStopRepository,
    this.busCompanyRepository,
    this.onViewOnMap,
  });

  final AuthUser? currentUser;

  /// Admin-added routes source. Null = no custom routes are shown.
  final CustomRouteRepository? customRouteRepository;

  /// Admin-set fare / student fare / direction overrides for the
  /// built-in routes. Null = no overrides are applied.
  final RouteFareOverrideRepository? fareOverrideRepository;

  /// Hidden built-in routes source. Null = no routes are hidden.
  final HiddenRouteRepository? hiddenRouteRepository;

  /// Admin-added bus stops source. Null = only the 16 built-in
  /// hubs are known.
  final BusStopRepository? busStopRepository;

  /// Admin-added bus companies source. Null = only the preset
  /// operator chips are shown.
  final BusCompanyRepository? busCompanyRepository;

  /// Opens the Map tab for the current trip. Null when the host
  /// does not wire it (same pattern as StudentTab/CommunitiesTab):
  /// the "Find routes" and "Show direction on Map" buttons are
  /// hidden then, so there is never a dead button. main.dart is the
  /// only place that can wire this (it owns tab switching).
  final VoidCallback? onViewOnMap;

  @override
  State<FaresTab> createState() => _FaresTabState();
}

class _FaresTabState extends State<FaresTab> {
  // Nov 7 (Steven): the vehicle/discount pickers were removed with the
  // calculator, so the discount stays frozen at Regular. The rate is
  // NOT frozen: each breakdown sheet uses the rate matching the
  // route's vehicle (Fares × Map audit, Nov 7, 2026: F5).
  final bool _discounted = false;
  _OriginMode _originMode = _OriginMode.location;
  int _originHub = 2; // Cabugao.
  int _destHub = 14; // Vigan Bus Terminal.
  double? _deviceLat;
  double? _deviceLng;
  bool _locating = false;

  /// Admin-added routes (Add Route), newest first.
  List<CustomRoute> _customRoutes = [];

  /// Admin-set overrides for the built-in routes, keyed by
  /// [seededRouteKey] ('From|To'). Empty when none are stored.
  Map<String, RouteFareOverride> _fareOverrides = {};

  /// Built-in routes removed from Popular Routes, keyed by
  /// [seededRouteKey] ('From|To'). Empty when none are hidden.
  Set<String> _hiddenRouteKeys = {};

  /// Admin-added bus stops (Map line maker / "+ Add bus stop"),
  /// appended after the 16 built-in hubs everywhere hubs appear.
  List<BusStop> _busStops = [];

  /// Admin-added bus companies ("+ Add company"), appended after
  /// the preset operator chips in the Add Route sheet.
  List<BusCompany> _busCompanies = [];

  /// Trip-card From/To choices: the 16 built-in hubs first, then
  /// the admin-added bus stops (indices 0–15 never shift).
  List<Hub> get _tripHubs => allHubs(_busStops);

  /// The Add Route form stashed when the admin left the sheet to
  /// place a new bus stop on the map — the next Add Route / Edit
  /// Route open pre-fills from it, then clears it. The seeded
  /// route / existing route being edited are stashed alongside,
  /// so the sheet reopens in the same mode.
  AddRouteSheetDraft? _pendingAddRouteDraft;
  PopularRoute? _pendingSeededRoute;
  CustomRoute? _pendingExistingRoute;

  /// Popular Routes filters (preview chips). The operator filter
  /// only applies while the Bus vehicle chip is active; picking
  /// any other vehicle resets it to All. The region and fare
  /// filters combine with the vehicle/operator filters (AND).
  String _vehicleFilter = 'All';
  String _operatorFilter = 'All';
  String _regionFilter = 'All';
  String _provinceFilter = 'All';
  String _sortBy = 'Most Popular';

  /// Staged selections — what the chips/dropdowns show while the
  /// user is choosing. Apply copies them into the applied
  /// filters above; Reset restores them all to their defaults.
  String _stagedVehicleFilter = 'All';
  String _stagedOperatorFilter = 'All';
  String _stagedRegionFilter = 'All';
  String _stagedProvinceFilter = 'All';
  String _stagedSortBy = 'Most Popular';

  /// Whether the Additional Filters section is expanded.
  bool _additionalFiltersExpanded = false;

  bool get _isAdmin => isAdminUser(widget.currentUser);

  @override
  void initState() {
    super.initState();
    busStopsChanged.addListener(_onRouteDataChanged);
    customRoutesChanged.addListener(_onRouteDataChanged);
    routeFareOverridesChanged.addListener(_onRouteDataChanged);
    hiddenRoutesChanged.addListener(_onRouteDataChanged);
    faresAdminActionRequest.addListener(_onFaresAdminActionRequest);
    _loadRouteData();
  }

  @override
  void dispose() {
    busStopsChanged.removeListener(_onRouteDataChanged);
    customRoutesChanged.removeListener(_onRouteDataChanged);
    routeFareOverridesChanged.removeListener(_onRouteDataChanged);
    hiddenRoutesChanged.removeListener(_onRouteDataChanged);
    faresAdminActionRequest.removeListener(_onFaresAdminActionRequest);
    super.dispose();
  }

  /// A request from the Account tab's Admin Access section (Nov 8,
  /// 2026 organize: the standalone admin actions live there now).
  /// Runs synchronously: the section jumps to this tab first and
  /// then sets the request, so the sheet/dialog opens over the
  /// Fares tab. (A post-frame deferral was tried first — a
  /// post-frame callback registered outside a frame never runs
  /// under the test binding, so the action never fired.) Consumed
  /// once; the notifier is cleared here so the same action can be
  /// requested again. Non-admins are ignored (the section is
  /// hidden for them, and the repos re-check on save).
  void _onFaresAdminActionRequest() {
    final action = faresAdminActionRequest.value;
    if (action == null) return;
    faresAdminActionRequest.value = null;
    if (!mounted || !isAdminUser(widget.currentUser)) return;
    switch (action) {
      case FaresAdminAction.addRoute:
        _openAddRoute();
      case FaresAdminAction.manageBusStops:
        _showManageBusStops();
      case FaresAdminAction.resetDirections:
        _resetAllDirections();
      case FaresAdminAction.hiddenRoutes:
        _showHiddenRoutes();
      case FaresAdminAction.addCompany:
        _addCompanyStandalone();
    }
  }

  /// Standalone "Add company" (Admin Access section, Nov 8, 2026
  /// organize): the same save as the Add Route sheet's "+ Add
  /// company" chip — typed name, repository dedupes
  /// case-insensitively — but as its own dialog, because the
  /// section row has no route form to attach the chip to.
  Future<void> _addCompanyStandalone() async {
    final user = widget.currentUser;
    final repo = widget.busCompanyRepository;
    if (user == null || repo == null || !isAdminUser(user)) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCompanyDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await repo.create(
        BusCompany(name: name, authorUid: user.uid, authorEmail: user.email),
        user,
      );
      await _loadRouteData();
      if (!mounted) return;
      TopPopup.show(context, message: 'Company added.');
    } catch (_) {
      if (!mounted) return;
      TopPopup.show(context, message: 'Could not add the company.');
    }
  }

  /// A route / override / stop changed elsewhere (the Map tab's
  /// line maker, another sheet) — reload so this tab shows the
  /// new data without a restart.
  void _onRouteDataChanged() {
    _loadRouteData();
  }

  Future<void> _loadRouteData() async {
    final repo = widget.customRouteRepository;
    final overrideRepo = widget.fareOverrideRepository;
    if (repo != null) {
      final routes = await repo.loadAll();
      if (mounted) setState(() => _customRoutes = routes);
    }
    if (overrideRepo != null) {
      final overrides = await overrideRepo.loadAll();
      if (mounted) {
        setState(() => _fareOverrides = overrides);
      }
    }
    final hiddenRepo = widget.hiddenRouteRepository;
    if (hiddenRepo != null) {
      final hidden = await hiddenRepo.loadAll();
      if (mounted) setState(() => _hiddenRouteKeys = hidden);
    }
    final stopRepo = widget.busStopRepository;
    if (stopRepo != null) {
      final stops = await stopRepo.loadAll();
      if (mounted) {
        setState(() {
          _busStops = stops;
          // A selected stop may have been deleted — clamp the
          // Trip-card indices back into the merged list.
          _originHub = math.max(0, math.min(_originHub, _tripHubs.length - 1));
          _destHub = math.max(0, math.min(_destHub, _tripHubs.length - 1));
        });
      }
    }
    final companyRepo = widget.busCompanyRepository;
    if (companyRepo != null) {
      final companies = await companyRepo.loadAll();
      if (mounted) setState(() => _busCompanies = companies);
    }
  }

  /// Opens the Add Route form (admin only — the button is hidden
  /// for everyone else, and the repository re-checks on save).
  /// When [existing] is given, edits that route. A stashed draft
  /// (the admin returning from placing a bus stop on the map)
  /// pre-fills the form, then clears. If the admin taps
  /// "+ Add bus stop", the form is stashed, the map opens in
  /// add-stop mode, and the next Add Route open pre-fills from it.
  Future<void> _openAddRoute({CustomRoute? existing}) async {
    final user = widget.currentUser;
    final repo = widget.customRouteRepository;
    if (user == null || repo == null || !isAdminUser(user)) return;
    final draft = _pendingAddRouteDraft;
    final pendingExisting = _pendingExistingRoute;
    final result = await showModalBottomSheet<AddRouteSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddRouteSheet(
        existing: existing ?? pendingExisting,
        repository: repo,
        author: user,
        busStops: _busStops,
        busCompanies: _busCompanies,
        companyRepository: widget.busCompanyRepository,
        initialDraft: draft,
      ),
    );
    _pendingAddRouteDraft = null;
    _pendingExistingRoute = null;
    if (result == null || !mounted) return;
    if (result.addBusStopDraft != null) {
      _pendingAddRouteDraft = result.addBusStopDraft;
      _pendingExistingRoute = existing ?? pendingExisting;
      if (result.companiesChanged) await _loadRouteData();
      mapLineMakerRequest.value = (drawLine: false, addStop: true);
      widget.onViewOnMap?.call();
      return;
    }
    await _loadRouteData();
    if (!mounted) return;
    TopPopup.show(
      context,
      message: result.deleted
          ? 'Route deleted.'
          : existing == null
          ? 'Route added.'
          : 'Route updated.',
    );
  }

  /// Opens the edit sheet for one Popular Route (admin only —
  /// the entry point is hidden for everyone else, and the
  /// repositories re-check on save). Admin-added routes edit
  /// their custom route; built-in routes edit their stored
  /// override (fare, student fare, and via stops). A stashed
  /// draft (returning from placing a bus stop) pre-fills the
  /// form, but only for the same seeded route it came from.
  Future<void> _openEditRoute(PopularRoute route) async {
    final user = widget.currentUser;
    if (user == null || !isAdminUser(user)) return;
    final customId = route.customRouteId;
    if (customId != null) {
      final existing = _customRoutes.where((r) => r.id == customId).firstOrNull;
      if (existing == null) return;
      await _openAddRoute(existing: existing);
      return;
    }
    final overrideRepo = widget.fareOverrideRepository;
    if (overrideRepo == null) return;
    final useDraft =
        _pendingSeededRoute != null &&
        _pendingSeededRoute!.from == route.from &&
        _pendingSeededRoute!.to == route.to;
    final draft = useDraft ? _pendingAddRouteDraft : null;
    final result = await showModalBottomSheet<AddRouteSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddRouteSheet.editSeededRoute(
        route: route,
        existingOverride: _fareOverrides[seededRouteKey(route.from, route.to)],
        overrideRepository: overrideRepo,
        author: user,
        busStops: _busStops,
        busCompanies: _busCompanies,
        companyRepository: widget.busCompanyRepository,
        initialDraft: draft,
      ),
    );
    _pendingAddRouteDraft = null;
    _pendingSeededRoute = null;
    if (result == null || !mounted) return;
    if (result.addBusStopDraft != null) {
      _pendingAddRouteDraft = result.addBusStopDraft;
      _pendingSeededRoute = route;
      if (result.companiesChanged) await _loadRouteData();
      mapLineMakerRequest.value = (drawLine: false, addStop: true);
      widget.onViewOnMap?.call();
      return;
    }
    await _loadRouteData();
    if (!mounted) return;
    TopPopup.show(
      context,
      message: result.deleted
          ? 'Route reset to its built-in fare.'
          : 'Route updated.',
    );
  }

  /// Remove a route (admin only — the entry points are hidden
  /// for everyone else, and the repositories re-check on save).
  /// An admin-added route is DELETED for real (same confirm +
  /// repository call as the Edit sheet's Delete route); a
  /// built-in route is HIDDEN (restorable from Hidden routes —
  /// never hard-deleted, and its fare/direction override is
  /// untouched). Both confirm first.
  Future<void> _removeRoute(PopularRoute route) async {
    final user = widget.currentUser;
    if (user == null || !isAdminUser(user)) return;
    final customId = route.customRouteId;
    if (customId != null) {
      final custom = _customRoutes.where((r) => r.id == customId).firstOrNull;
      final repo = widget.customRouteRepository;
      if (custom == null || repo == null) return;
      final confirmed = await showIosAlert<bool>(
        context: context,
        title: 'Delete this route?',
        message:
            '${custom.from} → ${custom.to} will be removed from '
            'Popular Routes. This cannot be undone.',
        actions: const [
          IosAlertAction<bool>('Cancel', value: false),
          IosAlertAction<bool>('Delete', value: true, isDestructive: true),
        ],
      );
      if (confirmed != true || !mounted) return;
      try {
        await repo.delete(custom, user);
        await _loadRouteData();
        if (!mounted) return;
        TopPopup.show(context, message: 'Route deleted.');
      } catch (_) {
        if (!mounted) return;
        TopPopup.show(context, message: 'Could not delete the route.');
      }
      return;
    }
    final repo = widget.hiddenRouteRepository;
    if (repo == null) return;
    final key = seededRouteKey(route.from, route.to);
    final confirmed = await showIosAlert<bool>(
      context: context,
      title: 'Remove this route?',
      message:
          '${route.from} → ${route.to} will be hidden from '
          'Popular Routes. You can restore it from Hidden routes.',
      actions: const [
        IosAlertAction<bool>('Cancel', value: false),
        IosAlertAction<bool>('Remove', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true || !mounted) return;
    try {
      await repo.hide(key, user);
      await _loadRouteData();
      if (!mounted) return;
      TopPopup.show(
        context,
        message: 'Route hidden.',
        actionLabel: 'View hidden',
        onAction: _showHiddenRoutes,
      );
    } catch (_) {
      if (!mounted) return;
      TopPopup.show(context, message: 'Could not hide the route.');
    }
  }

  /// Popular Routes: the built-in verified / named routes (with
  /// any admin overrides merged in) plus admin-added custom routes
  /// (newest first). Hidden built-in routes are skipped — a
  /// remove never hard-deletes them, so they come back from
  /// Hidden routes. The list is rebuilt from [_customRoutes] and
  /// [_fareOverrides] on every build, so a newly added route or
  /// an edited fare appears here without a reload.
  List<PopularRoute> get _allPopularRoutes => [
    for (final route in popularRoutes)
      if (!_hiddenRouteKeys.contains(seededRouteKey(route.from, route.to)))
        route.applyOverride(
          _fareOverrides[seededRouteKey(route.from, route.to)],
        ),
    for (final route in _customRoutes) popularRouteFromCustomRoute(route),
  ];

  /// Built-in routes currently hidden, for the Hidden routes
  /// admin sheet. A hidden key with no matching built-in route
  /// (stale data) is skipped — it hides nothing.
  List<PopularRoute> get _hiddenSeededRoutes => [
    for (final route in popularRoutes)
      if (_hiddenRouteKeys.contains(seededRouteKey(route.from, route.to)))
        route,
  ];

  /// The Popular Routes list under the current APPLIED filters
  /// and sort order. The chips/dropdowns stage a selection; only
  /// Apply (see [_applyFilters]) changes what this returns.
  List<PopularRoute> get _filteredPopularRoutes => sortPopularRoutes(
    filterPopularRoutes(
      _allPopularRoutes,
      vehicle: _vehicleFilter,
      operator: _operatorFilter,
      region: _regionFilter,
      province: _provinceFilter,
      busStops: _busStops,
    ),
    _sortBy,
  );

  /// Provinces offered by the Province dropdown: the provinces of
  /// the staged region (the region the user is choosing, so the
  /// list follows the dropdown), alphabetical; 'All' regions →
  /// every province in the bundled data (see
  /// [provincesInRegion]). 'Metro Manila' is a region, not a
  /// province, so it never appears.
  List<String> get _provinceOptions => provincesInRegion(_stagedRegionFilter);

  /// Operators offered by the Operator dropdown: the distinct
  /// operators on the full Popular Routes list (Bus routes only),
  /// first-seen order — from the data, never hardcoded. An
  /// operator with no route is never offered.
  List<String> get _operatorOptions => routeOperators(_allPopularRoutes);

  /// True when any Popular Routes filter is applied.
  bool get _hasActiveFilters =>
      _vehicleFilter != 'All' ||
      _operatorFilter != 'All' ||
      _regionFilter != 'All' ||
      _provinceFilter != 'All' ||
      _sortBy != 'Most Popular';

  /// True when the staged selection differs from the applied
  /// filters — i.e. there is something to Apply.
  bool get _hasStagedChanges =>
      _stagedVehicleFilter != _vehicleFilter ||
      _stagedOperatorFilter != _operatorFilter ||
      _stagedRegionFilter != _regionFilter ||
      _stagedProvinceFilter != _provinceFilter ||
      _stagedSortBy != _sortBy;

  /// Applies the staged selection: the displayed Popular Routes
  /// list updates, the count label updates, and the empty-state
  /// message follows the applied filters.
  void _applyFilters() {
    setState(() {
      _vehicleFilter = _stagedVehicleFilter;
      _operatorFilter = _stagedOperatorFilter;
      _regionFilter = _stagedRegionFilter;
      _provinceFilter = _stagedProvinceFilter;
      _sortBy = _stagedSortBy;
    });
  }

  /// Resets all Popular Routes filters to their defaults — staged
  /// and applied: Vehicle All, Region All Regions, Operator All
  /// Operators, Province All Provinces, Sort By Most Popular.
  void _resetFilters() {
    setState(() {
      _vehicleFilter = 'All';
      _operatorFilter = 'All';
      _regionFilter = 'All';
      _provinceFilter = 'All';
      _sortBy = 'Most Popular';
      _stagedVehicleFilter = 'All';
      _stagedOperatorFilter = 'All';
      _stagedRegionFilter = 'All';
      _stagedProvinceFilter = 'All';
      _stagedSortBy = 'Most Popular';
    });
  }

  /// Empty-state message for the filtered Popular Routes list.
  /// Names the most specific applied filter (operator, then
  /// province, then region, then vehicle) — the existing 'No
  /// Partas routes yet.' / 'No van routes yet.' messages are kept
  /// verbatim, and the region/province messages follow the same
  /// pattern.
  String _emptyRoutesMessage() {
    if (_vehicleFilter == 'Bus' && _operatorFilter != 'All') {
      return 'No $_operatorFilter routes yet.';
    }
    if (_provinceFilter != 'All') {
      return 'No routes in $_provinceFilter yet.';
    }
    if (_regionFilter != 'All') {
      return 'No routes in $_regionFilter yet.';
    }
    if (_vehicleFilter == 'All') return 'No routes yet.';
    return 'No ${_vehicleFilter.toLowerCase()} routes yet.';
  }

  /// One filter chip row (the vehicle row): an optional small
  /// label + a horizontally scrolling row of ChoiceChips in the
  /// existing Fares style. The row scrolls instead of wrapping,
  /// so it never overflows a narrow phone (the preview's pill
  /// nav overflowed a 390px phone by ~100px). [rowKey] is a test
  /// hook for tapping one row's 'All' chip when several rows
  /// carry one.
  Widget _filterChipRow({
    Key? rowKey,
    String? label,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: rowKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(option),
                    selected: selected == option,
                    showCheckmark: false,
                    // Feature 4: grass block chips (Baloo 2 label,
                    // grass fill when selected, 2.5px ink border).
                    selectedColor: MinecraftColors.grassGreen,
                    backgroundColor: _faresCardColor(context),
                    side: BorderSide(
                      color: selected == option
                          ? MinecraftColors.grassGreen
                          : scheme.outline,
                      width: selected == option ? 2.5 : 1,
                    ),
                    labelStyle: MinecraftText.button(
                      color: selected == option
                          ? Colors.white
                          : scheme.onSurface,
                      fontSize: 14,
                    ),
                    onSelected: enabled ? (_) => onSelected(option) : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One filter dropdown (region / operator / province / sort):
  /// an optional small label + a compact DropdownButtonFormField
  /// in the existing Fares style (rounded border, card fill, the
  /// accent border on focus). [enabled] false greys the control
  /// out (the operator dropdown, when the vehicle is not Bus —
  /// operators only apply to Bus routes); the control stays
  /// visible so the category is discoverable. [value] must be
  /// one of [options]; [display] maps a value to its shown label
  /// ('Region I – Ilocos Region'), defaulting to the value
  /// itself. [fieldKey] is a test hook for finding one dropdown
  /// among several.
  Widget _filterDropdown({
    Key? fieldKey,
    String? label,
    required List<String> options,
    required String value,
    required ValueChanged<String> onChanged,
    String Function(String value)? display,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: _faresCardColor(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kFaresAccent, width: 2),
            ),
          ),
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option,
                child: Text(
                  display == null ? option : display(option),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled
              ? (next) {
                  if (next != null) onChanged(next);
                }
              : null,
        ),
      ],
    );
  }

  /// Loads a hub route into the calculator: hub-origin mode with
  /// From/To set to the route's hubs, so the distance and fare
  /// recompute. Non-hub routes cannot load (their endpoints are
  /// not hubs) and are left untouched. Hubs here are the merged
  /// list — an admin-added stop is a valid endpoint.
  void _loadRouteIntoCalculator(PopularRoute route) {
    final fromIndex = _tripHubs.indexWhere((h) => h.name == route.from);
    final toIndex = _tripHubs.indexWhere((h) => h.name == route.to);
    if (fromIndex < 0 || toIndex < 0) return;
    setState(() {
      _originMode = _OriginMode.hub;
      _originHub = fromIndex;
      _destHub = toIndex;
    });
  }

  /// Sets the Fares → Map jump, then switches to the Map tab.
  /// The Map tab draws the route and shows its ETA • FARE sheet;
  /// without the jump it would open with no route at all.
  /// [fromLat]/[fromLng] carry the device position when the
  /// jump's origin is 'My location' (J2) — the Map starts at the
  /// real location instead of silently retargeting to the home
  /// hub. Null for hub origins (resolved by name on the Map).
  void _jumpToMap({
    required String from,
    required String to,
    double? fromLat,
    double? fromLng,
    bool startLive = false,
  }) {
    // Rating prompt (Nov 9): jumping to the Map with a route is a
    // real action; Start Ride (startLive) counts separately.
    AppRatingTracker.instance.recordAction(
      startLive
          ? AppRatingAction.startedRide
          : AppRatingAction.viewedRouteOnMap,
    );
    faresMapJump.value = (
      from: from,
      to: to,
      fromLat: fromLat,
      fromLng: fromLng,
      startLive: startLive,
    );
    widget.onViewOnMap?.call();
  }

  /// Tapping a Popular Route loads it into the calculator (hub
  /// routes only) and opens the fare breakdown sheet for it.
  void _openRouteSheet(PopularRoute route) {
    // Rating prompt (Nov 9): opening a fare breakdown sheet is a
    // real action — checking a fare.
    AppRatingTracker.instance.recordAction(AppRatingAction.checkedFare);
    _loadRouteIntoCalculator(route);
    final override = route.customRouteId == null
        ? _fareOverrides[seededRouteKey(route.from, route.to)]
        : null;
    final custom = route.customRouteId == null
        ? null
        : _customRoutes.where((r) => r.id == route.customRouteId).firstOrNull;
    final fromHub = hubByName(route.from, _busStops);
    final toHub = hubByName(route.to, _busStops);
    // F10: the breakdown uses the ROUTE's own distance — never the
    // Trip card's leftover From/To distance (the old code showed
    // another route's estimate for non-hub routes like Laoag
    // Partas → Cubao, and contradicted the GMW route's own
    // 401.0 km). Null when the route's distance is unknown: the
    // estimate section hides instead of showing a borrowed number.
    // F3: a custom route's distance is its leg-summed distance.
    final distanceKm = popularRouteRoadKm(
      route,
      _busStops,
      customRoute: custom,
    );
    // F5: the rate matches the route's vehicle (Bus → prov-aircon,
    // Jeepney → trad-jeep); Van / Tricycle have no table rate, so
    // no breakdown is shown instead of a wrong-rate number.
    final rate = rateForRouteVehicle(route.vehicle);
    final breakdown = rate != null && distanceKm != null
        ? fareBreakdownFor(rate, distanceKm, _discounted)
        : null;
    final distanceNote =
        route.distanceNote ??
        (fromHub != null && toHub != null
            ? 'Straight-line distance + 22% road allowance.'
            : null);
    final etaMinutes = distanceKm != null
        ? (toHub != null
              ? hubPairEtaMinutes(from: fromHub, to: toHub, roadKm: distanceKm)
              : transitEtaMinutes(roadKm: distanceKm))
        : null;
    final fareStatus = route.fare == null
        ? 'Fare not set'
        : route.fareLabel == 'Verified bus fare'
        ? 'Verified fare'
        : 'Admin-set fare';
    // The route's effective direction — a drawn line wins over the
    // named via stops — as raw points for the geometry key/fetch.
    final viaWaypoints = effectiveRouteWaypoints(
      customRoute: custom,
      override: override,
      busStops: _busStops,
    );
    final viaPoints = viaWaypoints.map((w) => w.point).toList();
    // F1/F2: the live OSRM geometry for this route when either tab
    // has already fetched it; the sheet fetches on a miss and
    // updates to the Map's values (distance, ETA, stops) live.
    final initialGeometry = fromHub != null && toHub != null
        ? routeGeometryCache.get(
            routeGeometryKey(
              oLat: fromHub.lat,
              oLng: fromHub.lng,
              dest: toHub,
              via: viaPoints,
            ),
          )
        : null;
    // Stops along the way, without road geometry: origin +
    // destination (+ the route's effective direction). The sheet
    // recomputes the full on-the-way list once its geometry loads
    // — never guessed.
    final stops = fromHub != null && toHub != null && distanceKm != null
        ? hubPairStops(
            from: fromHub,
            to: toHub,
            totalKm: distanceKm,
            viaHubNames: route.viaHubs,
            viaWaypoints: viaWaypoints,
            extraStops: _busStops,
          ).map((s) => (name: s.name, role: s.role)).toList()
        : null;
    final hasEndpoints =
        _tripHubs.any((h) => h.name == route.from) &&
        _tripHubs.any((h) => h.name == route.to);
    final canViewOnMap = widget.onViewOnMap != null && hasEndpoints;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Feature 4: no explicit shape — the Minecraft
      // bottomSheetTheme (16px corners + 3px ink border) applies.
      builder: (_) => _FareBreakdownSheet(
        from: route.from,
        to: route.to,
        operator: route.operator,
        vehicle: route.vehicle,
        isBus: route.isBus,
        showRouteFare: true,
        routeFare: route.fare,
        routeFareLabel: route.fareLabel,
        routeFareNote: route.fare == null
            ? null
            : route.fareLabel == 'Verified bus fare'
            ? 'Verified Oct 16, 2026 — shown as reported, not calculated.'
            : 'Fare entered by an admin.',
        routeFareStudent: route.effectiveStudentFare,
        routeFareStudentSet: route.studentFare != null,
        routeFarePwd: route.effectivePwdFare,
        routeFarePwdSet: route.pwdFare != null,
        routeFareSenior: route.effectiveSeniorFare,
        routeFareSeniorSet: route.seniorFare != null,
        onEditRoute: _isAdmin ? () => _openEditRoute(route) : null,
        onRemoveRoute: _isAdmin ? () => _removeRoute(route) : null,
        distanceKm: distanceKm,
        distanceNote: distanceNote,
        etaMinutes: etaMinutes,
        etaNote: etaMinutes == null
            ? null
            : 'Estimate — straight-line distance + 22% road allowance.',
        fareStatus: fareStatus,
        stops: stops,
        breakdown: breakdown,
        breakdownNote: breakdown == null && hasEndpoints
            ? 'No calculator breakdown for the current vehicle and trip.'
            : null,
        onViewOnMap: canViewOnMap
            ? () => _jumpToMap(from: route.from, to: route.to)
            : null,
        // Start Ride (Nov 8, 2026): the same jump, with Live
        // Follow requested — the Map starts GPS tracking on
        // this route. Same endpoint gate as Show direction.
        onStartRide: canViewOnMap
            ? () => _jumpToMap(from: route.from, to: route.to, startLive: true)
            : null,
        // F1/F2: the sheet shows the live OSRM geometry when
        // available (cached or freshly fetched) and falls back to
        // the estimate values above until it loads.
        initialGeometry: initialGeometry,
        loadGeometry: fromHub != null && toHub != null
            ? () => fetchRouteGeometry(
                oLat: fromHub.lat,
                oLng: fromHub.lng,
                dest: toHub,
                via: viaPoints,
              )
            : null,
        geometryFrom: fromHub,
        geometryTo: toHub,
        geometryViaHubNames: route.viaHubs,
        geometryViaWaypoints: viaWaypoints,
        geometryExtraStops: _busStops,
        breakdownForKm: (km) =>
            rate == null ? null : fareBreakdownFor(rate, km, _discounted),
      ),
    ).then((_) {
      // A geometry fetched while the sheet was open is now cached:
      // refresh the Trip card so it shows the live distance too.
      if (mounted) setState(() {});
    });
  }

  /// Manage bus stops (admin only): the list of admin-added
  /// stops with per-stop Edit (region only — a stop's name and
  /// coordinates are its identity, and routes reference it by
  /// name) and Delete. Delete is blocked while any custom route
  /// (From / To / via stops) or any stored override (via stops)
  /// references the name — deleting it would orphan those
  /// routes. A stop selected in the Trip card is not checked:
  /// the indices are clamped on the next load instead.
  Future<void> _showManageBusStops() async {
    final user = widget.currentUser;
    final repo = widget.busStopRepository;
    if (user == null || repo == null || !isAdminUser(user)) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manage bus stops',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Stops you added on the map. New stops are added '
                    'from Add Route → Via stops → Add bus stop.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (_busStops.isEmpty)
                    const Text('No bus stops added yet.')
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final stop in _busStops)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.push_pin_outlined),
                              title: Text(stop.name),
                              subtitle: Text(
                                '${stop.region} · '
                                '${stop.lat.toStringAsFixed(5)}, '
                                '${stop.lng.toStringAsFixed(5)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit region',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final updated = await _editBusStopRegion(
                                        stop,
                                      );
                                      if (updated != null && mounted) {
                                        setSheetState(() {});
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Delete stop',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final deleted = await _deleteBusStop(
                                        stop,
                                      );
                                      if (deleted && mounted) {
                                        setSheetState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Hidden routes (admin only): the built-in routes removed
  /// from Popular Routes, each with a Restore button. Restoring
  /// deletes the hidden record — the route comes back with any
  /// fare/direction override intact, because hiding never
  /// touches the override.
  Future<void> _showHiddenRoutes() async {
    final user = widget.currentUser;
    final repo = widget.hiddenRouteRepository;
    if (user == null || repo == null || !isAdminUser(user)) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final hidden = _hiddenSeededRoutes;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hidden routes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Built-in routes removed from Popular Routes. '
                    'Restoring brings a route back — its fares and '
                    'direction are untouched.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (hidden.isEmpty)
                    const Text('No hidden routes.')
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final route in hidden)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.visibility_off_outlined,
                              ),
                              title: Text('${route.from} → ${route.to}'),
                              subtitle: Text(
                                [
                                  if (route.operator != null) route.operator!,
                                  route.vehicle,
                                ].join(' · '),
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  try {
                                    await repo.unhide(
                                      seededRouteKey(route.from, route.to),
                                      user,
                                    );
                                    await _loadRouteData();
                                    if (mounted) setSheetState(() {});
                                    if (mounted) {
                                      TopPopup.show(
                                        context,
                                        message: 'Route restored.',
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      TopPopup.show(
                                        context,
                                        message: 'Could not restore the route.',
                                      );
                                    }
                                  }
                                },
                                child: const Text('Restore'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Edit one stop's region (name + coordinates are immutable).
  /// Returns the updated stop, or null when cancelled / failed.
  Future<BusStop?> _editBusStopRegion(BusStop stop) async {
    final user = widget.currentUser;
    final repo = widget.busStopRepository;
    if (user == null || repo == null) return null;
    var region = stop.region;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Edit ${stop.name}'),
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in hubRegions())
                    ChoiceChip(
                      label: Text(r),
                      selected: region == r,
                      onSelected: (_) => setDialogState(() => region = r),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return null;
    try {
      final updated = await repo.update(stop.copyWith(region: region), user);
      await _loadRouteData();
      return updated;
    } catch (_) {
      if (!mounted) return null;
      TopPopup.show(context, message: 'Could not save the stop.');
      return null;
    }
  }

  /// Delete one stop, blocked while any route references its
  /// name. Returns true when the stop was deleted.
  Future<bool> _deleteBusStop(BusStop stop) async {
    final user = widget.currentUser;
    final repo = widget.busStopRepository;
    if (user == null || repo == null) return false;
    final referenced =
        _customRoutes.any(
          (r) =>
              r.from == stop.name ||
              r.to == stop.name ||
              r.viaHubs.contains(stop.name),
        ) ||
        _fareOverrides.values.any(
          (o) => o.viaHubs?.contains(stop.name) ?? false,
        );
    if (referenced) {
      if (!mounted) return false;
      TopPopup.show(
        context,
        message:
            '"${stop.name}" is still used by a route — remove it '
            'from the route first.',
      );
      return false;
    }
    final confirmed = await showIosAlert<bool>(
      context: context,
      title: 'Delete this bus stop?',
      message:
          '"${stop.name}" will be removed from the From/To and '
          'via-stops pickers. This cannot be undone.',
      actions: const [
        IosAlertAction<bool>('Cancel', value: false),
        IosAlertAction<bool>('Delete', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true || !mounted) return false;
    try {
      await repo.delete(stop, user);
      await _loadRouteData();
      return true;
    } catch (_) {
      if (!mounted) return false;
      TopPopup.show(context, message: 'Could not delete the stop.');
      return false;
    }
  }

  /// Resets every saved direction (admin only): clears the
  /// drawn line points (viaWaypoints) AND the named via stops
  /// (viaHubs) on every route in one tap — Steven (Nov 7,
  /// 20:41) resets them all and draws the new lines himself.
  /// Fares are never touched: an override that still carries a
  /// fare is saved back with only the direction removed; one
  /// that carried only a direction is deleted (reset to the
  /// built-in route). A confirm dialog shows the count first —
  /// this wipes all saved directions. The repos enforce the
  /// admin allowlist on every write; the button is hidden for
  /// non-admins and this method re-checks.
  Future<void> _resetAllDirections() async {
    final user = widget.currentUser;
    final repo = widget.customRouteRepository;
    final overrideRepo = widget.fareOverrideRepository;
    if (user == null ||
        repo == null ||
        overrideRepo == null ||
        !isAdminUser(user)) {
      return;
    }
    final plan = resetAllDirectionsPlan(
      customs: _customRoutes,
      overrides: _fareOverrides.values.toList(),
    );
    if (plan.isEmpty) {
      if (!mounted) return;
      TopPopup.show(context, message: 'No saved directions to reset.');
      return;
    }
    final confirmed = await showIosAlert<bool>(
      context: context,
      title: 'Reset all directions?',
      message:
          'This clears the saved direction on '
          '${plan.affectedCount} route(s) — every drawn line and '
          'every named via stop. Fares stay as they are. You can '
          'draw new lines on the Map afterwards.',
      actions: const [
        IosAlertAction<bool>('Cancel', value: false),
        IosAlertAction<bool>('Reset all', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true || !mounted) return;
    try {
      for (final route in plan.clearedCustoms) {
        await repo.update(route, user, busStops: _busStops);
      }
      for (final override in plan.clearedOverrides) {
        await overrideRepo.save(override, user);
      }
      for (final routeKey in plan.deletedOverrideKeys) {
        await overrideRepo.delete(routeKey, user);
      }
      await _loadRouteData();
      if (!mounted) return;
      TopPopup.show(
        context,
        message:
            'Reset ${plan.affectedCount} direction(s). '
            'Fares were not changed.',
      );
    } catch (_) {
      await _loadRouteData();
      if (!mounted) return;
      TopPopup.show(
        context,
        message:
            'Some directions could not be reset. Check the routes '
            'and try again.',
      );
    }
  }

  /// The custom route matching the Trip card's current From/To
  /// (hub mode only), or null when the pair is a generated route
  /// or the origin is the device location.
  CustomRoute? _tripCustomRoute() {
    if (_originMode != _OriginMode.hub) return null;
    return matchCustomRoute(
      _customRoutes,
      _tripHubs[_originHub].name,
      _tripHubs[_destHub].name,
    );
  }

  /// Cached live OSRM geometry for the Trip card's current
  /// From/To (+ the matching custom route's via points), or null
  /// when the route has not been fetched yet — the Map tab or a
  /// breakdown sheet populates the cache (see
  /// [routeGeometryCache]).
  RouteGeometry? _tripGeometry() {
    final dest = _tripHubs[_destHub];
    final custom = _tripCustomRoute();
    final via = custom == null
        ? const <LatLng>[]
        : effectiveRouteWaypoints(
            customRoute: custom,
            busStops: _busStops,
          ).map((w) => w.point).toList();
    if (_originMode == _OriginMode.location) {
      if (_deviceLat == null || _deviceLng == null) return null;
      return routeGeometryCache.get(
        routeGeometryKey(
          oLat: _deviceLat!,
          oLng: _deviceLng!,
          dest: dest,
          via: via,
        ),
      );
    }
    final from = _tripHubs[_originHub];
    return routeGeometryCache.get(
      routeGeometryKey(oLat: from.lat, oLng: from.lng, dest: dest, via: via),
    );
  }

  /// Road distance shown in the Trip card: the live OSRM distance
  /// when the route has been fetched (same as the Map tab — F2),
  /// else a custom route's leg-summed distance (F3), else
  /// max(0.1, direct * 1.22) like the web calculator.
  double? get _roadKm {
    final geometry = _tripGeometry();
    if (geometry != null) return geometry.distanceKm;
    final custom = _tripCustomRoute();
    if (custom != null) return customRouteRoadKm(custom, _busStops);
    final direct = _directKm;
    if (direct == null) return null;
    return math.max(0.1, direct * 1.22);
  }

  /// Direct (straight-line) distance for the computed modes, null when
  /// no origin is available yet.
  double? get _directKm {
    double? fromLat;
    double? fromLng;
    if (_originMode == _OriginMode.location) {
      fromLat = _deviceLat;
      fromLng = _deviceLng;
    } else {
      fromLat = _tripHubs[_originHub].lat;
      fromLng = _tripHubs[_originHub].lng;
    }
    if (fromLat == null || fromLng == null) return null;
    return haversineKm(
      fromLat,
      fromLng,
      _tripHubs[_destHub].lat,
      _tripHubs[_destHub].lng,
    );
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          TopPopup.show(
            context,
            message: 'Turn on Location (GPS) on your phone first.',
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          TopPopup.show(
            context,
            message: 'Location permission is needed to see where you are.',
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _deviceLat = position.latitude;
        _deviceLng = position.longitude;
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Opens the searchable place picker for a Trip-card endpoint
  /// and stores the picked place's index into [_tripHubs]. The
  /// merged list is ~180 places now (16 hubs + admin stops +
  /// the bundled Philippines list), far past what the old
  /// dropdown menu could show.
  Future<void> _pickTripPlace({
    required String label,
    required int current,
    required ValueChanged<int> onPicked,
  }) async {
    final picked = await showPlacePicker(
      context: context,
      places: _tripHubs,
      stopsCount: _busStops.length,
      selected: _tripHubs[current],
      title: label,
    );
    if (picked == null || !mounted) return;
    final index = _tripHubs.indexWhere((h) => h.name == picked.name);
    if (index >= 0) onPicked(index);
  }

  /// A Trip-card place field: looks like the old dropdown field
  /// (label + value + chevron) but opens the searchable picker.
  Widget _tripPlaceField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final hub = _tripHubs[value];
    return InkWell(
      onTap: () =>
          _pickTripPlace(label: label, current: value, onPicked: onChanged),
      borderRadius: BorderRadius.circular(kFaresInputRadius),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kFaresInputRadius),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text('${hub.name} · ${hub.region}')),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roadKm = _roadKm;
    final directKm = _directKm;
    final tripGeometry = _tripGeometry();
    final tripCustom = _tripCustomRoute();
    final filteredRoutes = _filteredPopularRoutes;

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: MinecraftText.title(color: scheme.onSurface)),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FaresHero(),
            const SizedBox(height: 24),
            // Feature 4: blocky Minecraft card shell (3px ink
            // border, hard shadow) around the unchanged Trip
            // picker — same fields, same behaviour, new look.
            MinecraftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sectionTitle('Trip'),
                  IosSegmentedControl<_OriginMode>(
                    segments: const [
                      IosSegment(
                        value: _OriginMode.location,
                        label: 'My location',
                      ),
                      IosSegment(value: _OriginMode.hub, label: 'Choose a hub'),
                    ],
                    groupValue: _originMode,
                    onValueChanged: (value) {
                      setState(() => _originMode = value);
                    },
                  ),
                  const SizedBox(height: AppLayout.cardGap),
                  if (_originMode == _OriginMode.location) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _deviceLat == null
                                ? 'No location yet. Tap to get your current location.'
                                : 'Your location has been found.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        FilledButton(
                          onPressed: _locating ? null : _useLocation,
                          child: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _deviceLat == null
                                      ? 'Use my location'
                                      : 'Refresh',
                                ),
                        ),
                      ],
                    ),
                  ] else ...[
                    _tripPlaceField(
                      label: 'From',
                      value: _originHub,
                      onChanged: (v) => setState(() => _originHub = v),
                    ),
                  ],
                  if (_originMode == _OriginMode.hub) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Swap From and To',
                        onPressed: () {
                          setState(() {
                            final from = _originHub;
                            _originHub = _destHub;
                            _destHub = from;
                          });
                        },
                        icon: const Icon(Icons.swap_vert),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppLayout.cardGap),
                  _tripPlaceField(
                    label: 'To',
                    value: _destHub,
                    onChanged: (v) => setState(() => _destHub = v),
                  ),
                  const SizedBox(height: AppLayout.cardGap),

                  if (roadKm != null) ...[
                    Text(
                      '${roadKm.toStringAsFixed(1)} km',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      // F2: the ×1.22 figure is labelled an
                      // estimate; the live OSRM distance says so.
                      tripGeometry != null
                          ? 'Live road distance — same as the Map tab.'
                          : tripCustom != null
                          ? 'Calculated from your stops: straight-line legs + 22% road allowance.'
                          : 'Calculated: ${directKm!.toStringAsFixed(1)} km straight-line distance + 22% road allowance. May differ from the actual route.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ] else
                    Text(
                      '— km',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  if (widget.onViewOnMap != null) ...[
                    const SizedBox(height: AppLayout.cardGap),
                    FilledButton.icon(
                      onPressed: () => _jumpToMap(
                        from: _originMode == _OriginMode.location
                            ? 'My location'
                            : _tripHubs[_originHub].name,
                        to: _tripHubs[_destHub].name,
                        // J2: the device position travels with the
                        // jump, so the Map starts at the real
                        // location instead of the home hub.
                        fromLat: _originMode == _OriginMode.location
                            ? _deviceLat
                            : null,
                        fromLng: _originMode == _OriginMode.location
                            ? _deviceLng
                            : null,
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Find routes'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Feature 4: blocky section header (grass icon badge +
            // Baloo 2 title) with the live route count as trailing.
            MinecraftSectionHeader(
              icon: Icons.directions_bus,
              title: 'Popular Routes',
              trailing: Text(
                routesCountLabel(
                  filtered: filteredRoutes.length,
                  total: _allPopularRoutes.length,
                ),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            // Nov 8, 2026 redesign (Steven: pasted spec, approved
            // with resolutions): the Popular Routes filters are
            // Vehicle chips → Region dropdown → Additional Filters
            // (collapsible: Operator / Province / Sort By), with
            // STAGED Apply / Reset. The Fare filter was removed —
            // fare info still shows on the cards and sheets.
            // Tapping a chip or dropdown only STAGES the
            // selection; Apply updates the list.
            _filterChipRow(
              rowKey: const ValueKey('vehicle-filter-row'),
              label: 'Vehicle',
              options: vehicleFilters,
              selected: _stagedVehicleFilter,
              onSelected: (vehicle) {
                setState(() {
                  _stagedVehicleFilter = vehicle;
                  if (vehicle != 'Bus') _stagedOperatorFilter = 'All';
                });
              },
            ),
            const SizedBox(height: AppLayout.cardGap),
            _filterDropdown(
              fieldKey: const ValueKey('region-filter-dropdown'),
              label: 'Region',
              options: ['All', ...allAdministrativeRegions],
              value: _stagedRegionFilter,
              display: regionDisplayLabel,
              onChanged: (region) {
                setState(() {
                  _stagedRegionFilter = region;
                  // The province list follows the region — a
                  // province from the old region no longer
                  // applies, so it resets to All Provinces.
                  _stagedProvinceFilter = 'All';
                });
              },
            ),
            const SizedBox(height: AppLayout.cardGap),
            // Additional Filters: operator, province, sort —
            // collapsed by default. The header row toggles the
            // section; AnimatedSize gives the smooth
            // expand/collapse, and the '+'/'−' shows the state.
            Column(
              key: const ValueKey('additional-filters-section'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _additionalFiltersExpanded = !_additionalFiltersExpanded;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'Additional Filters',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _additionalFiltersExpanded ? Icons.remove : Icons.add,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const Spacer(),
                        if (_stagedOperatorFilter != 'All' ||
                            _stagedProvinceFilter != 'All' ||
                            _stagedSortBy != 'Most Popular')
                          Text(
                            'Active',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: MinecraftColors.deepLeaves,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  // Reduced motion: no expand/collapse animation.
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _additionalFiltersExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.s8),
                            // The operator dropdown only APPLIES to
                            // Bus routes, so when another vehicle
                            // is picked it disables (and the
                            // selection resets to All, as before)
                            // instead of vanishing.
                            _filterDropdown(
                              fieldKey: const ValueKey(
                                'operator-filter-dropdown',
                              ),
                              label: 'Operator',
                              options: ['All', ..._operatorOptions],
                              value: _stagedOperatorFilter,
                              onChanged: (operator) {
                                setState(() {
                                  _stagedOperatorFilter = operator;
                                });
                              },
                              enabled: _stagedVehicleFilter == 'Bus',
                            ),
                            const SizedBox(height: AppLayout.cardGap),
                            _filterDropdown(
                              fieldKey: const ValueKey(
                                'province-filter-dropdown',
                              ),
                              label: 'Province',
                              options: ['All', ..._provinceOptions],
                              value: _stagedProvinceFilter,
                              onChanged: (province) {
                                setState(() {
                                  _stagedProvinceFilter = province;
                                });
                              },
                            ),
                            const SizedBox(height: AppLayout.cardGap),
                            _filterDropdown(
                              fieldKey: const ValueKey('sort-filter-dropdown'),
                              label: 'Sort By',
                              options: sortByOptions,
                              value: _stagedSortBy,
                              onChanged: (sortBy) {
                                setState(() => _stagedSortBy = sortBy);
                              },
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _hasStagedChanges ? _applyFilters : null,
                    child: const Text('Apply Filters'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _hasActiveFilters || _hasStagedChanges
                        ? _resetFilters
                        : null,
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            if (filteredRoutes.isEmpty)
              Text(
                _emptyRoutesMessage(),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              for (final route in filteredRoutes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  // Feature 5: tap squash + ring/bits. The wrapper
                  // only observes the pointer; the card's InkWell
                  // still owns the tap.
                  child: MinecraftTapAnimation(
                    child: _PopularRouteCard(
                      route: route,
                      onTap: () => _openRouteSheet(route),
                      onRemove: _isAdmin ? () => _removeRoute(route) : null,
                    ),
                  ),
                ),
            // Nov 7 (Steven): the calculator (Sasakyan card, result
            // card, estimate disclaimer), Added routes, and Posted
            // operator fares sections were removed at his request.
            // Nov 8, 2026 (Steven: organize Admin Access into one
            // category): the standalone admin actions — Add Route,
            // Manage bus stops, Reset all directions, Hidden routes
            // — moved to the Account tab's Admin Access section.
            // They run here on request (see
            // _onFaresAdminActionRequest), so this tab keeps only
            // the route-specific entries: Edit route in the fare
            // breakdown sheet and Remove on each route card / sheet.
          ],
        ),
      ),
    );
  }
}

/// Standalone "Add company" dialog (Admin Access section). Owns
/// its TextEditingController so disposal happens with the dialog:
/// disposing a caller-owned controller right after showDialog
/// returns breaks the TextField while the pop animation is still
/// in flight. Returns the typed name, or null when cancelled.
class _AddCompanyDialog extends StatefulWidget {
  const _AddCompanyDialog();

  @override
  State<_AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends State<_AddCompanyDialog> {
  final _controller = TextEditingController();
  var _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add company'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A bus company for the operator list, e.g. Partas.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Company name *',
              errorText: _error.isEmpty ? null : _error,
            ),
            onChanged: (_) {
              if (_error.isNotEmpty) {
                setState(() => _error = '');
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_controller.text.trim().isEmpty) {
              setState(() => _error = 'Type a company name first.');
              return;
            }
            Navigator.pop(context, _controller.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Whole km without decimals, fractional km with one decimal.
String formatKm(double km) =>
    km.toStringAsFixed(km.truncateToDouble() == km ? 0 : 1);

/// Hero panel at the top of the Fares tab (Feature 4 Minecraft
/// restyle): a grass gradient carrying the tab's existing title
/// and subtitle, with a 3px ink border and a dirt block badge.
/// No dark-mode toggle here — that lives only in Settings →
/// General → Appearance (Nov 5 rule); the preview's in-tab toggle
/// is preview chrome and is deliberately not ported.
class _FaresHero extends StatelessWidget {
  const _FaresHero();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MinecraftColors.grassBright, MinecraftColors.grassMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MinecraftIconBadge(
                icon: Icons.calculate_outlined,
                backgroundColor: MinecraftColors.dirtBrown,
                size: 40,
                iconSize: 22,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  'Know your fare before you go',
                  style: MinecraftText.heading(
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'LTFRB fare calculator — same rates and formula as the web app.',
            style: MinecraftText.body(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// "Provincial" scope tag carried by every bus route card and the
/// fare breakdown sheet (preview design). Van / jeepney / tricycle
/// routes carry no scope tag. Feature 4: blocky chip — grass
/// tint, 2.5px ink border, Baloo 2 label.
class _ProvincialTag extends StatelessWidget {
  const _ProvincialTag();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: MinecraftColors.grassGreen.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: 2,
        ),
      ),
      child: Text(
        'Provincial',
        style: MinecraftText.button(
          color: isDark ? Colors.white : MinecraftColors.deepLeaves,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Material icon for a Popular Route vehicle. No emoji anywhere.
IconData _popularRouteIcon(String vehicle) {
  switch (vehicle) {
    case 'Bus':
      return Icons.directions_bus;
    case 'Van':
      return Icons.airport_shuttle;
    case 'Jeepney':
      return Icons.directions_bus_outlined;
    case 'Tricycle':
      return Icons.motorcycle;
    default:
      return Icons.directions_transit;
  }
}

/// One Popular Routes card (Feature 4 Minecraft restyle): a
/// blocky card with a grass icon badge, the From → To route in
/// Baloo 2, operator and vehicle, the "Provincial" scope tag on
/// bus cards, the route's own live fare (regular + 20%-off
/// student fare) or "Fare not set", and the road detail — the
/// route's real road distance when known, plus its admin-set via
/// stops. No sample fares, no invented distances: a route with
/// no known distance shows no distance line.
class _PopularRouteCard extends StatelessWidget {
  const _PopularRouteCard({
    required this.route,
    required this.onTap,
    this.onRemove,
  });

  final PopularRoute route;
  final VoidCallback onTap;

  /// Admin-only remove (delete for admin-added routes, hide for
  /// built-in routes). Null for non-admins — no icon is shown.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fare = route.fare;
    final roadKm = route.roadKm;
    return MinecraftCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MinecraftIconBadge(icon: _popularRouteIcon(route.vehicle)),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${route.from} → ${route.to}',
                  style: MinecraftText.title(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.s4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (route.operator != null)
                      Text(
                        route.operator!,
                        style: MinecraftText.caption(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      route.vehicle,
                      style: MinecraftText.caption(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (route.isBus) const _ProvincialTag(),
                  ],
                ),
                if (roadKm != null || route.viaHubs.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    [
                      if (roadKm != null)
                        '≈ ${formatKm(roadKm)} km road distance',
                      if (route.viaHubs.isNotEmpty)
                        'Via ${route.viaHubs.join(' · ')}',
                    ].join(' · '),
                    style: MinecraftText.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          fare == null
              ? Text(
                  'Fare not set',
                  style: MinecraftText.caption(color: scheme.onSurfaceVariant),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      peso(fare),
                      style: MinecraftText.heading(
                        color: scheme.onSurface,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${peso(route.effectiveStudentFare!)} student',
                      style: MinecraftText.caption(
                        color: MinecraftColors.deepLeaves,
                      ),
                    ),
                  ],
                ),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.s4),
            IconButton(
              tooltip: 'Remove route',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: scheme.error,
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled row in the fare breakdown sheet.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    this.detail,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final String? detail;
  final String amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MinecraftText.bodySemiBold(color: scheme.onSurface)
                      .copyWith(
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                      ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: MinecraftText.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            amount,
            style: MinecraftText.bodySemiBold(color: scheme.onSurface)
                .copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Fare breakdown bottom sheet (preview design, real numbers): the
/// route's own fare (verified / admin-entered / not set) and, when
/// the trip can be priced, the LTFRB calculator breakdown for the
/// current vehicle and discount. Every row comes from
/// [FareBreakdown] or the route's own fare — the preview's sample
/// ₱40 + ₱13 + ₱7 breakdown is never shown.
class _FareBreakdownSheet extends StatefulWidget {
  const _FareBreakdownSheet({
    required this.from,
    required this.to,
    required this.operator,
    required this.vehicle,
    required this.isBus,
    required this.showRouteFare,
    required this.routeFare,
    required this.routeFareLabel,
    required this.routeFareNote,
    this.routeFareStudent,
    this.routeFareStudentSet = false,
    this.routeFarePwd,
    this.routeFarePwdSet = false,
    this.routeFareSenior,
    this.routeFareSeniorSet = false,
    required this.distanceKm,
    required this.distanceNote,
    required this.etaMinutes,
    required this.etaNote,
    required this.fareStatus,
    required this.stops,
    required this.breakdown,
    required this.breakdownNote,
    required this.onViewOnMap,
    this.onStartRide,
    this.onEditRoute,
    this.onRemoveRoute,
    this.initialGeometry,
    this.loadGeometry,
    this.geometryFrom,
    this.geometryTo,
    this.geometryViaHubNames = const [],
    this.geometryViaWaypoints = const [],
    this.geometryExtraStops = const [],
    this.breakdownForKm,
  });

  final String from;
  final String to;
  final String? operator;
  final String vehicle;
  final bool isBus;

  /// False for the current-calculation sheet (no route fare to
  /// show); true for a tapped Popular Route.
  final bool showRouteFare;
  final double? routeFare;
  final String? routeFareLabel;
  final String? routeFareNote;

  /// The student fare to show — the admin-set value when present,
  /// otherwise 20% off [routeFare]; null when no fare is set.
  final double? routeFareStudent;

  /// True when [routeFareStudent] was set by an admin (not
  /// derived) — the detail line says so instead of "20% off".
  final bool routeFareStudentSet;

  /// The PWD fare to show — the admin-set value when present,
  /// otherwise 20% off [routeFare]; null when no fare is set.
  /// Same pattern as [routeFareStudent].
  final double? routeFarePwd;

  /// True when [routeFarePwd] was set by an admin (not derived).
  final bool routeFarePwdSet;

  /// The Senior Citizen fare to show — the admin-set value when
  /// present, otherwise 20% off [routeFare]; null when no fare
  /// is set. Same pattern as [routeFareStudent].
  final double? routeFareSenior;

  /// True when [routeFareSenior] was set by an admin (not derived).
  final bool routeFareSeniorSet;

  final double? distanceKm;
  final String? distanceNote;

  /// Transit ETA in minutes (same estimateTripMinutes model as the
  /// Map tab), or null when no distance is known.
  final int? etaMinutes;
  final String? etaNote;

  /// 'Verified fare' / 'Admin-set fare' / 'Fare not set' for a
  /// tapped Popular Route; null for the calculator sheet.
  final String? fareStatus;

  /// Stops along the way as (name, role) pairs — origin + destination
  /// (+ an admin route's via-stops); null when the endpoints are not
  /// both known hubs. Intermediate on-the-way towns appear once
  /// the live geometry loads (see [initialGeometry]/[loadGeometry]);
  /// they are never guessed.
  final List<({String name, String role})>? stops;

  final FareBreakdown? breakdown;
  final String? breakdownNote;
  final VoidCallback? onViewOnMap;

  /// Starts Live Follow on this route (Start Ride, Nov 8, 2026):
  /// the sheet closes, the Map opens on the route, and GPS
  /// follow starts. Null when the route cannot be jumped to
  /// (same gate as [onViewOnMap]).
  final VoidCallback? onStartRide;

  /// Admin-only: opens the edit sheet for this route. Null for
  /// non-admins (no edit entry is shown) and for the calculator
  /// sheet (no route to edit).
  final VoidCallback? onEditRoute;

  /// Admin-only: removes this route — delete for admin-added
  /// routes, hide for built-in routes. Null for non-admins (no
  /// remove entry is shown) and for the calculator sheet.
  final VoidCallback? onRemoveRoute;

  /// Live OSRM geometry for this route when either tab already
  /// fetched it (see [routeGeometryCache]); null until the sheet
  /// fetches it (see [loadGeometry]).
  final RouteGeometry? initialGeometry;

  /// Fetches the route's live geometry (cache-first, see
  /// [fetchRouteGeometry]). Null when the endpoints are unknown
  /// — the sheet stays on the estimate values.
  final Future<RouteGeometry?> Function()? loadGeometry;

  /// Endpoints + direction inputs for recomputing the stops list
  /// from the live geometry (see [hubPairStops]). Null when the
  /// endpoints are not both known hubs.
  final Hub? geometryFrom;
  final Hub? geometryTo;
  final List<String> geometryViaHubNames;
  final List<RouteWaypoint> geometryViaWaypoints;
  final List<BusStop> geometryExtraStops;

  /// Rebuilds the calculator breakdown for a live road distance
  /// (same rate as the estimate breakdown). Null when the route's
  /// vehicle has no table rate.
  final FareBreakdown? Function(double roadKm)? breakdownForKm;

  @override
  State<_FareBreakdownSheet> createState() => _FareBreakdownSheetState();
}

class _FareBreakdownSheetState extends State<_FareBreakdownSheet> {
  RouteGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    _geometry = widget.initialGeometry;
    if (_geometry == null && widget.loadGeometry != null) {
      widget.loadGeometry!().then((geometry) {
        if (!mounted || geometry == null) return;
        setState(() => _geometry = geometry);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final geometry = _geometry;
    // Effective values: the live geometry wins when loaded (the
    // SAME distance, ETA, and stops the Map tab shows — F1/F2);
    // the estimate values passed in are the pre-load fallback.
    final from = widget.from;
    final to = widget.to;
    final operator = widget.operator;
    final vehicle = widget.vehicle;
    final isBus = widget.isBus;
    final showRouteFare = widget.showRouteFare;
    final routeFare = widget.routeFare;
    final routeFareLabel = widget.routeFareLabel;
    final routeFareNote = widget.routeFareNote;
    final routeFareStudent = widget.routeFareStudent;
    final routeFareStudentSet = widget.routeFareStudentSet;
    final routeFarePwd = widget.routeFarePwd;
    final routeFarePwdSet = widget.routeFarePwdSet;
    final routeFareSenior = widget.routeFareSenior;
    final routeFareSeniorSet = widget.routeFareSeniorSet;
    final fareStatus = widget.fareStatus;
    final breakdownNote = widget.breakdownNote;
    final onViewOnMap = widget.onViewOnMap;
    final onStartRide = widget.onStartRide;
    final onEditRoute = widget.onEditRoute;
    final onRemoveRoute = widget.onRemoveRoute;
    final distanceKm = geometry?.distanceKm ?? widget.distanceKm;
    final distanceNote = geometry != null
        ? 'Live road distance — same as the Map tab.'
        : widget.distanceNote;
    final etaMinutes = geometry != null
        ? (geometry.durationSec / 60).round()
        : widget.etaMinutes;
    final etaNote = geometry != null
        ? 'Live road time — same as the Map tab.'
        : widget.etaNote;
    final stops =
        geometry != null &&
            widget.geometryFrom != null &&
            widget.geometryTo != null
        ? hubPairStops(
            from: widget.geometryFrom!,
            to: widget.geometryTo!,
            totalKm: geometry.distanceKm,
            viaHubNames: widget.geometryViaHubNames,
            viaWaypoints: widget.geometryViaWaypoints,
            extraStops: widget.geometryExtraStops,
            roadPoints: geometry.points,
          ).map((s) => (name: s.name, role: s.role)).toList()
        : widget.stops;
    final breakdown = geometry != null && widget.breakdownForKm != null
        ? widget.breakdownForKm!(geometry.distanceKm)
        : widget.breakdown;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fare breakdown',
                      style: MinecraftText.title(color: scheme.onSurface),
                    ),
                  ),
                  if (onEditRoute != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onEditRoute();
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit route'),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                '$from → $to',
                style: MinecraftText.title(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.s4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (operator != null)
                    Text(
                      operator,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  Text(
                    vehicle,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (isBus) const _ProvincialTag(),
                ],
              ),
              if (distanceKm != null) ...[
                const SizedBox(height: AppSpacing.s16),
                _SheetRow(
                  label: 'Distance',
                  detail: distanceNote,
                  amount: '${distanceKm.toStringAsFixed(1)} km',
                ),
              ],
              if (etaMinutes != null) ...[
                const SizedBox(height: AppSpacing.s8),
                _SheetRow(
                  label: 'ETA',
                  detail: etaNote,
                  amount: formatTripTimeShort(etaMinutes),
                ),
              ],
              if (fareStatus != null) ...[
                const SizedBox(height: AppSpacing.s8),
                _SheetRow(label: 'Fare status', amount: fareStatus, bold: true),
              ],
              if (showRouteFare) ...[
                const SizedBox(height: AppSpacing.s16),
                Text(
                  'Route fare',
                  style: MinecraftText.title(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.s8),
                if (routeFare != null) ...[
                  _SheetRow(
                    label: routeFareLabel ?? 'Route fare',
                    amount: peso(routeFare),
                    bold: true,
                  ),
                  _SheetRow(
                    label: 'Student discount',
                    detail: routeFareStudentSet
                        ? 'Set by an admin'
                        : '20% off with a valid student ID',
                    amount: peso(
                      routeFareStudent ?? discountedFareOf(routeFare),
                    ),
                  ),
                  _SheetRow(
                    label: 'PWD discount',
                    detail: routeFarePwdSet
                        ? 'Set by an admin'
                        : '20% off with a valid PWD ID',
                    amount: peso(routeFarePwd ?? discountedFareOf(routeFare)),
                  ),
                  _SheetRow(
                    label: 'Senior Citizen discount',
                    detail: routeFareSeniorSet
                        ? 'Set by an admin'
                        : '20% off with a valid senior citizen ID',
                    amount: peso(
                      routeFareSenior ?? discountedFareOf(routeFare),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'The discounted fare applies to students, PWD, and senior citizens with a valid ID.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  // Feature 4 (preview parity): a flat note card
                  // for the student discount — 20% off the regular
                  // fare unless the admin set a student fare, and
                  // the school ID is shown at the gate. No fare
                  // amount is repeated here (the rows above carry
                  // it), so the sheet's fare counts stay unchanged.
                  const SizedBox(height: AppSpacing.s8),
                  Container(
                    key: const Key('student-discount-card'),
                    decoration: MinecraftDecorations.flatCardFor(
                      Theme.of(context).brightness,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MinecraftIconBadge(
                          icon: Icons.school_outlined,
                          backgroundColor: MinecraftColors.gold,
                          iconColor: MinecraftColors.ink,
                          size: 36,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            routeFareStudentSet
                                ? 'Student fare set by an admin — show your school ID.'
                                : 'Student discount: 20% off the regular fare — show your school ID.',
                            style: MinecraftText.bodySemiBold(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (routeFareNote != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      routeFareNote,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ] else ...[
                  Text(
                    'Fare not set',
                    style: MinecraftText.title(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'No fare has been set for this route yet.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
              if (breakdown != null) ...[
                const SizedBox(height: AppSpacing.s16),
                Text(
                  'Calculator estimate',
                  style: MinecraftText.title(color: scheme.onSurface),
                ),
                _SheetRow(
                  label: 'Base fare',
                  detail: 'Covers the first ${formatKm(breakdown.bracket)} km',
                  amount: peso(breakdown.base),
                ),
                _SheetRow(
                  label: 'Distance',
                  detail:
                      '${breakdown.billableKm} km × ${peso(breakdown.perKm)} per km',
                  amount: peso(breakdown.distanceFare),
                ),
                if (breakdown.minimumAdjustment > 0)
                  _SheetRow(
                    label: 'Minimum applied',
                    detail:
                        'Formula fare ${peso(breakdown.formulaFare)} was below the minimum',
                    amount: '+${peso(breakdown.minimumAdjustment)}',
                  ),
                const Divider(),
                _SheetRow(
                  label: 'Regular fare',
                  amount: peso(breakdown.regular),
                  bold: true,
                ),
                if (breakdown.discounted)
                  _SheetRow(
                    label: 'Student / Senior / PWD discount',
                    detail: '20% off',
                    amount: '−${peso(breakdown.regular - breakdown.collected)}',
                  ),
                const SizedBox(height: AppSpacing.s8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Amount to pay',
                      style: MinecraftText.bodySemiBold(
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '≈ ${peso(breakdown.collected)}',
                      style: MinecraftText.heading(
                        color: MinecraftColors.grassGreen,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  'LTFRB formula — same rates as the calculator above.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ] else if (breakdownNote != null) ...[
                const SizedBox(height: AppSpacing.s16),
                Text(
                  breakdownNote,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (stops != null && stops.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                Text(
                  'Stops along the way',
                  style: MinecraftText.title(color: scheme.onSurface),
                ),
                for (var i = 0; i < stops.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}',
                            style: MinecraftText.button(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            stops[i].name,
                            style: MinecraftText.bodySemiBold(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          stops[i].role,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
              if (onStartRide != null) ...[
                const SizedBox(height: AppSpacing.s16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onStartRide();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Ride'),
                ),
              ],
              if (onViewOnMap != null) ...[
                const SizedBox(height: AppSpacing.s16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onViewOnMap();
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show direction on Map'),
                ),
              ],
              if (onRemoveRoute != null) ...[
                const SizedBox(height: AppSpacing.s12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onRemoveRoute();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove route'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
