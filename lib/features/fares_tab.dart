// Fares tab — LTFRB fare calculator (EstudyanteGO web app parity).
//
// Faithful port of the web app's faresController.js: same 11 vehicle
// rates, same formula, same 16 hubs, same distance rule (straight-line
// distance + 22% road allowance). Differences from the web version are
// deliberate and small: the tab does NOT auto-prompt for location on
// open (tap "Gamitin ang lokasyon ko" instead), and the distance is
// always auto-computed (straight-line + 22% road allowance) — there is
// no manual distance field. No dummy data: every number shown comes
// from the rate table below or from the distance the user actually
// picked. Tricycle fares outside Dagupan have
// NO national rate, so that mode shows the honest LGU-matrix message
// instead of inventing a number.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'add_route_sheet.dart';
import 'admin_access.dart';
import 'app_layout.dart';
import 'custom_routes.dart';
import 'onboarding/auth_service.dart';
import 'operator_fares.dart';

// Fares-local ChatGPT design tokens (Premium Dark + Emerald Green,
// adopted Nov 5 as a LOOSE UI base). Tab-local on purpose: the shared
// AppLayout/AppText scale is used by other tabs and stays untouched.
// Only the tokens this tab actually uses are defined here.
const kFaresDarkCard = Color(0xFF202B25);
const kFaresCardRadius = 20.0;
const kFaresInputRadius = 14.0;
const kFaresPageTitle =
    TextStyle(fontSize: 26, fontWeight: FontWeight.w800);
const kFaresCardHeading =
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
const kFaresFareAmount =
    TextStyle(fontSize: 30, fontWeight: FontWeight.w800);

/// ChatGPT card geometry for Fares cards: 20dp corners, theme outline.
ShapeBorder _faresCardShape(BuildContext context) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kFaresCardRadius),
    side: BorderSide(color: Theme.of(context).colorScheme.outline),
  );
}

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
final faresMapJump = ValueNotifier<({String from, String to})?>(null);

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
    this.fareLabel,
    this.distanceKm,
    this.distanceNote,
    this.viaHubs = const [],
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

  bool get isBus => vehicle == 'Bus';

  /// True when both endpoints are hubs, so the route can load
  /// into the calculator and show a formula breakdown.
  bool get hasHubEndpoints =>
      hubByName(from) != null && hubByName(to) != null;

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
const vehicleFilters = <String>[
  'All',
  'Bus',
  'Van',
  'Jeepney',
  'Tricycle',
];

/// Bus operator filter chips (preview order, shown only while the
/// Bus vehicle chip is active).
const busOperatorFilters = <String>[
  'All',
  'Partas',
  'Dominion',
  'GV Florida',
  'Viron',
  'Victory Liner',
  'Solid North',
  'Dagupan Bus',
  'Genesis',
  'Five Star',
  'JAC Liner',
  'ALPS',
  'Bicol Isarog',
  'GMW Trans',
];

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

/// Filters [routes] by vehicle chip and (Bus only) operator chip.
/// Pure, so the filter behaviour is unit-testable without widgets.
List<PopularRoute> filterPopularRoutes(
  List<PopularRoute> routes, {
  required String vehicle,
  required String operator,
}) {
  return routes.where((route) {
    if (vehicle != 'All' && route.vehicle != vehicle) return false;
    if (vehicle == 'Bus' &&
        operator != 'All' &&
        !popularRouteMatchesOperator(route.operator, operator)) {
      return false;
    }
    return true;
  }).toList();
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
    fareLabel: 'Admin-entered fare',
    viaHubs: route.viaHubs,
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
FareBreakdown? fareBreakdownFor(
  FareRate rate,
  double roadKm,
  bool discounted,
) {
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

/// One operator's posted fares, for the "Posted operator fares"
/// reference section below the calculator. This is reference data
/// only: posted fares are never mixed with the formula fares above.
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

enum _OriginMode { location, hub }

class FaresTab extends StatefulWidget {
  /// The signed-in user (null when signed out). Drives the
  /// admin-only Add Route entry point — see admin_access.dart.
  const FaresTab({
    super.key,
    this.currentUser,
    this.customRouteRepository,
    this.onViewOnMap,
  });

  final AuthUser? currentUser;

  /// Admin-added routes source. Null = no custom routes are shown.
  final CustomRouteRepository? customRouteRepository;

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
  String _rateId = 'trad-jeep';
  bool _discounted = false;
  _OriginMode _originMode = _OriginMode.location;
  int _originHub = 2; // Cabugao.
  int _destHub = 14; // Vigan Bus Terminal.
  double? _deviceLat;
  double? _deviceLng;
  bool _locating = false;

  /// Admin-added routes (Add Route), newest first.
  List<CustomRoute> _customRoutes = [];

  /// Popular Routes filters (preview chips). The operator filter
  /// only applies while the Bus vehicle chip is active; picking
  /// any other vehicle resets it to All.
  String _vehicleFilter = 'All';
  String _operatorFilter = 'All';

  bool get _isAdmin => isAdminUser(widget.currentUser);

  @override
  void initState() {
    super.initState();
    _loadCustomRoutes();
  }

  Future<void> _loadCustomRoutes() async {
    final repo = widget.customRouteRepository;
    if (repo == null) return;
    final routes = await repo.loadAll();
    if (mounted) setState(() => _customRoutes = routes);
  }

  /// Applies a custom route to the calculator: sets From/To to the
  /// route's hubs (hub-origin mode) so the distance recomputes.
  void _applyCustomRoute(CustomRoute route) {
    final fromIndex = hubs.indexWhere((h) => h.name == route.from);
    final toIndex = hubs.indexWhere((h) => h.name == route.to);
    if (fromIndex < 0 || toIndex < 0) return;
    setState(() {
      _originMode = _OriginMode.hub;
      _originHub = fromIndex;
      _destHub = toIndex;
    });
  }

  /// Opens the Add Route form (admin only — the button is hidden
  /// for everyone else, and the repository re-checks on save).
  Future<void> _openAddRoute({CustomRoute? existing}) async {
    final user = widget.currentUser;
    final repo = widget.customRouteRepository;
    if (user == null || repo == null || !isAdminUser(user)) return;
    final saved = await showModalBottomSheet<CustomRoute>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddRouteSheet(
        existing: existing,
        repository: repo,
        author: user,
      ),
    );
    if (saved != null && mounted) {
      await _loadCustomRoutes();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Route added.' : 'Route updated.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteCustomRoute(CustomRoute route) async {
    final user = widget.currentUser;
    final repo = widget.customRouteRepository;
    if (user == null || repo == null || !isAdminUser(user)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this route?'),
        content: Text('${route.from} → ${route.to} · ${route.operator}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repo.delete(route, user);
      await _loadCustomRoutes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the route: $e')),
      );
    }
  }

  /// Popular Routes: the built-in verified / named routes plus
  /// admin-added custom routes (newest first). The list is rebuilt
  /// from [_customRoutes] on every build, so a newly added route
  /// appears here without a reload.
  List<PopularRoute> get _allPopularRoutes => [
    ...popularRoutes,
    for (final route in _customRoutes)
      popularRouteFromCustomRoute(route),
  ];

  /// The Popular Routes list under the current chip filters.
  List<PopularRoute> get _filteredPopularRoutes =>
      filterPopularRoutes(
        _allPopularRoutes,
        vehicle: _vehicleFilter,
        operator: _operatorFilter,
      );

  /// Loads a hub route into the calculator: hub-origin mode with
  /// From/To set to the route's hubs, so the distance and fare
  /// recompute. Non-hub routes cannot load (their endpoints are
  /// not hubs) and are left untouched.
  void _loadRouteIntoCalculator(PopularRoute route) {
    if (!route.hasHubEndpoints) return;
    final fromIndex = hubs.indexWhere((h) => h.name == route.from);
    final toIndex = hubs.indexWhere((h) => h.name == route.to);
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
  void _jumpToMap({required String from, required String to}) {
    faresMapJump.value = (from: from, to: to);
    widget.onViewOnMap?.call();
  }

  /// Tapping a Popular Route loads it into the calculator (hub
  /// routes only) and opens the fare breakdown sheet for it.
  void _openRouteSheet(PopularRoute route) {
    _loadRouteIntoCalculator(route);
    final rate = _rate;
    final roadKm = _roadKm;
    final breakdown = rate != null && roadKm != null
        ? fareBreakdownFor(rate, roadKm, _discounted)
        : null;
    final fromHub = hubByName(route.from);
    final toHub = hubByName(route.to);
    final distanceKm = route.roadKm;
    final distanceNote = route.distanceNote ??
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
    // Stops along the way, without road geometry: origin +
    // destination (+ the admin's via-stops). The Map tab adds the
    // on-the-way towns once its OSRM line loads — never guessed.
    final stops = fromHub != null && toHub != null && distanceKm != null
        ? hubPairStops(
            from: fromHub,
            to: toHub,
            totalKm: distanceKm,
            viaHubNames: route.viaHubs,
          ).map((s) => (name: s.name, role: s.role)).toList()
        : null;
    final canViewOnMap =
        widget.onViewOnMap != null && route.hasHubEndpoints;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
        distanceKm: distanceKm,
        distanceNote: distanceNote,
        etaMinutes: etaMinutes,
        etaNote: etaMinutes == null
            ? null
            : 'Estimate — straight-line distance + 22% road allowance.',
        fareStatus: fareStatus,
        stops: stops,
        breakdown: breakdown,
        breakdownNote: breakdown == null && route.hasHubEndpoints
            ? 'No calculator breakdown for the current vehicle and trip.'
            : null,
        onViewOnMap: canViewOnMap
            ? () => _jumpToMap(from: route.from, to: route.to)
            : null,
      ),
    );
  }

  /// Opens the fare breakdown sheet for the current calculation
  /// (from the result card's "See breakdown" button).
  void _openCurrentBreakdown() {
    final rate = _rate;
    final roadKm = _roadKm;
    if (rate == null || roadKm == null) return;
    final breakdown = fareBreakdownFor(rate, roadKm, _discounted);
    final fromLabel = _originMode == _OriginMode.location
        ? 'My location'
        : hubs[_originHub].name;
    final fromHub =
        _originMode == _OriginMode.location ? null : hubs[_originHub];
    final toHub = hubs[_destHub];
    final etaMinutes =
        hubPairEtaMinutes(from: fromHub, to: toHub, roadKm: roadKm);
    final stops = fromHub == null
        ? null
        : hubPairStops(from: fromHub, to: toHub, totalKm: roadKm)
            .map((s) => (name: s.name, role: s.role))
            .toList();
    final canViewOnMap =
        widget.onViewOnMap != null &&
        _originMode == _OriginMode.hub;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FareBreakdownSheet(
        from: fromLabel,
        to: hubs[_destHub].name,
        operator: null,
        vehicle: rate.label,
        isBus:
            rate.id.startsWith('prov-') || rate.id.startsWith('city-'),
        showRouteFare: false,
        routeFare: null,
        routeFareLabel: null,
        routeFareNote: null,
        distanceKm: roadKm,
        distanceNote: 'Straight-line distance + 22% road allowance.',
        etaMinutes: etaMinutes,
        etaNote: 'Estimate — straight-line distance + 22% road allowance.',
        fareStatus: null,
        stops: stops,
        breakdown: breakdown,
        breakdownNote: null,
        onViewOnMap: canViewOnMap
            ? () => _jumpToMap(
                  from: hubs[_originHub].name,
                  to: hubs[_destHub].name,
                )
            : null,
      ),
    );
  }

  FareRate? get _rate {
    for (final r in fareRates) {
      if (r.id == _rateId) return r;
    }
    return null; // 'tricycle-local': no rate, handled as a special state.
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
      fromLat = hubs[_originHub].lat;
      fromLng = hubs[_originHub].lng;
    }
    if (fromLat == null || fromLng == null) return null;
    return haversineKm(
      fromLat,
      fromLng,
      hubs[_destHub].lat,
      hubs[_destHub].lng,
    );
  }

  /// Road distance shown and used for the fare: always auto-computed
  /// as max(0.1, direct * 1.22) like the web calculator.
  double? get _roadKm {
    final direct = _directKm;
    if (direct == null) return null;
    return math.max(0.1, direct * 1.22);
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Turn on Location (GPS) on your phone first.'),
            ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is needed to see where you are.',
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = _rate;
    final roadKm = _roadKm;
    final directKm = _directKm;
    final filteredRoutes = _filteredPopularRoutes;

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: kFaresCardHeading,
      ),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FaresHero(),
            const SizedBox(height: 24),
            Card(
              color: _faresCardColor(context),
              shape: _faresCardShape(context),
              child: Padding(
                padding: AppLayout.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionTitle('Trip'),
                    SegmentedButton<_OriginMode>(
                      segments: const [
                        ButtonSegment(
                          value: _OriginMode.location,
                          label: Text('My location'),
                        ),
                        ButtonSegment(
                          value: _OriginMode.hub,
                          label: Text('Choose a hub'),
                        ),
                      ],
                      selected: {_originMode},
                      onSelectionChanged: (selection) {
                        setState(() => _originMode = selection.first);
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
                      DropdownButtonFormField<int>(
                        value: _originHub,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'From',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kFaresInputRadius),
                          ),
                        ),
                        items: [
                          for (var i = 0; i < hubs.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                '${hubs[i].name} · ${hubs[i].region}',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _originHub = value);
                          }
                        },
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
                    DropdownButtonFormField<int>(
                      value: _destHub,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'To',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(kFaresInputRadius),
                        ),
                      ),
                      items: [
                        for (var i = 0; i < hubs.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text('${hubs[i].name} · ${hubs[i].region}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _destHub = value);
                        }
                      },
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
                        'Calculated: ${directKm!.toStringAsFixed(1)} km straight-line distance + 22% road allowance. May differ from the actual route.',
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
                              : hubs[_originHub].name,
                          to: hubs[_destHub].name,
                        ),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Find routes'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Popular Routes', style: kFaresCardHeading),
                const Spacer(),
                Text(
                  '${filteredRoutes.length} ${filteredRoutes.length == 1 ? 'route' : 'routes'}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final vehicle in vehicleFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(vehicle),
                        selected: _vehicleFilter == vehicle,
                        showCheckmark: false,
                        selectedColor: kFaresAccent,
                        backgroundColor: _faresCardColor(context),
                        side: BorderSide(
                          color: _vehicleFilter == vehicle
                              ? kFaresAccent
                              : scheme.outline,
                        ),
                        labelStyle: TextStyle(
                          color: _vehicleFilter == vehicle
                              ? Colors.white
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _vehicleFilter = vehicle;
                            if (vehicle != 'Bus') _operatorFilter = 'All';
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (_vehicleFilter == 'Bus') ...[
              const SizedBox(height: AppLayout.cardGap),
              Text(
                'Bus operator — Luzon, city & provincial',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.s8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final operator in busOperatorFilters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(operator),
                          selected: _operatorFilter == operator,
                          showCheckmark: false,
                          selectedColor: kFaresAccent,
                          backgroundColor: _faresCardColor(context),
                          side: BorderSide(
                            color: _operatorFilter == operator
                                ? kFaresAccent
                                : scheme.outline,
                          ),
                          labelStyle: TextStyle(
                            color: _operatorFilter == operator
                                ? Colors.white
                                : null,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) {
                            setState(() => _operatorFilter = operator);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppLayout.cardGap),
            if (filteredRoutes.isEmpty)
              Text(
                _vehicleFilter == 'Bus' && _operatorFilter != 'All'
                    ? 'No $_operatorFilter routes yet.'
                    : _vehicleFilter == 'All'
                        ? 'No routes yet.'
                        : 'No ${_vehicleFilter.toLowerCase()} routes yet.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              for (final route in filteredRoutes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PopularRouteCard(
                    route: route,
                    onTap: () => _openRouteSheet(route),
                  ),
                ),
            const SizedBox(height: 24),
            Card(
              color: _faresCardColor(context),
              shape: _faresCardShape(context),
              child: Padding(
                padding: AppLayout.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionTitle('Sasakyan'),
                    DropdownButtonFormField<String>(
                      value: _rateId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(kFaresInputRadius),
                        ),
                      ),
                      items: [
                        for (final r in fareRates)
                          DropdownMenuItem(value: r.id, child: Text(r.label)),
                        const DropdownMenuItem(
                          value: 'tricycle-local',
                          child: Text('Other tricycle · local matrix needed'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _rateId = value);
                        }
                      },
                    ),
                    const SizedBox(height: AppLayout.cardGap),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Regular')),
                        ButtonSegment(
                          value: true,
                          label: Text('Student / Senior / PWD · 20% off'),
                        ),
                      ],
                      selected: {_discounted},
                      onSelectionChanged: (selection) {
                        setState(() => _discounted = selection.first);
                      },
                    ),
                    if (rate != null && rate.minimum != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        '${peso(rate.minimum!)} minimum',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: scheme.primaryContainer,
              shape: _faresCardShape(context),
              child: Padding(
                padding: AppLayout.cardPadding,
                child: rate == null
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No nationwide tricycle rate',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: AppSpacing.s4),
                          Text(
                            'Check the LGU fare matrix. Tricycle fares are set by local ordinance, so EstudyanteGO does not provide a national estimate.',
                          ),
                        ],
                      )
                    : roadKm == null
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Starting location needed',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: AppSpacing.s4),
                          Text(
                            'Use your location or choose a starting hub to compute the distance and fare.',
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FareAmount(
                            rate: rate,
                            roadKm: roadKm,
                            discounted: _discounted,
                          ),
                          const SizedBox(height: AppLayout.cardGap),
                          TextButton.icon(
                            onPressed: _openCurrentBreakdown,
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('See breakdown'),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Estimate only. Distance is approximated from coordinates and may differ from the actual route. The official fare matrix of the operator governs what is charged. The ₱20 ordinary city-bus minimum and ₱100 provincial-bus minimum are applied before the discount. Rates follow the temporary national fare guide, effective Sept. 28–Dec. 31, 2026. Tricycle fares are set by each LGU, not by a national formula.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.s24),
            sectionTitle('Added routes'),
            Text(
              'Routes added by an admin. Tap one to load it into the '
              'calculator above. The fare shown is the one the admin '
              'entered — never a guess.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppLayout.cardGap),
            if (_isAdmin)
              FilledButton.icon(
                onPressed: () => _openAddRoute(),
                icon: const Icon(Icons.add),
                label: const Text('Add Route'),
              ),
            if (_isAdmin) const SizedBox(height: AppLayout.cardGap),
            if (_customRoutes.isEmpty)
              Text(
                'No added routes yet.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              for (final route in _customRoutes)
                Card(
                  color: _faresCardColor(context),
                  shape: _faresCardShape(context),
                  child: ListTile(
                    leading: const Icon(Icons.directions_bus_outlined),
                    title: Text('${route.from} → ${route.to}'),
                    subtitle: Text(
                      '${route.operator} · ${route.vehicle}'
                      '${route.viaHubs.isEmpty ? '' : ' · via ${route.viaHubs.join(' → ')}'}'
                      '\nCustom route',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          peso(route.fare),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_isAdmin)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            tooltip: 'Route options',
                            onSelected: (v) {
                              if (v == 'edit') {
                                _openAddRoute(existing: route);
                              }
                              if (v == 'delete') {
                                _deleteCustomRoute(route);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit route'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete route'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    onTap: () => _applyCustomRoute(route),
                  ),
                ),
            const SizedBox(height: AppSpacing.s24),
            sectionTitle('Posted operator fares'),
            Text(
              'Fares published by the operators themselves — this is a reference list only. It was not computed by the calculator above, and posted fares are not mixed with formula fares.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppLayout.cardGap),
            for (final group in groupOperatorFares())
              _OperatorFareGroupCard(group: group),
            const SizedBox(height: AppLayout.cardGap),
            Text(
              'This list covers only fares officially published by operators. Fares that were not officially published are not estimated or included.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// One collapsible operator group in the posted-fares reference
/// section: company header with fare count and source note, then one
/// row per posted fare (origin → destination, service class, peso
/// fare). Plain cards, no icons — visually separate from the
/// primary-colored calculator result card above.
class _OperatorFareGroupCard extends StatelessWidget {
  const _OperatorFareGroupCard({required this.group});

  final OperatorFareGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: _faresCardColor(context),
      shape: _faresCardShape(context),
      child: ExpansionTile(
        title: Text(
          '${group.company} · ${group.fares.length} fares',
          style: kFaresCardHeading,
        ),
        subtitle: Text(
          group.sourceNote,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final fare in group.fares)
            ListTile(
              dense: true,
              title: Text('${fare.origin} → ${fare.destination}'),
              subtitle: Text(fare.fareClass),
              trailing: Text(
                peso(fare.fare),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

class _FareAmount extends StatelessWidget {
  const _FareAmount({
    required this.rate,
    required this.roadKm,
    required this.discounted,
  });

  final FareRate rate;
  final double roadKm;
  final bool discounted;

  @override
  Widget build(BuildContext context) {
    final result = computeFare(rate, roadKm, discounted);
    final baseCopy =
        '${peso(rate.base)} covers the first ${rate.bracket.toStringAsFixed(rate.bracket.truncateToDouble() == rate.bracket ? 0 : 1)} km, then ${peso(rate.perKm)} for each succeeding km.';
    final minimumCopy = rate.minimum != null
        ? ' Ang ${peso(rate.minimum!)} minimum applies when the formula result is lower.'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${rate.label} · ${roadKm.toStringAsFixed(1)} km',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          '≈ ${peso(result.collected)}',
          style: kFaresFareAmount,
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          '${discounted ? '20% discount applied; nearest ₱0.25 shown.' : 'Regular fare.'} $baseCopy$minimumCopy${rate.local ? ' Dagupan local ordinance example.' : ' Estimate from the temporary national guide.'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Whole km without decimals, fractional km with one decimal.
String formatKm(double km) =>
    km.toStringAsFixed(km.truncateToDouble() == km ? 0 : 1);

/// Hero panel at the top of the Fares tab (preview design): a Deep
/// Emerald gradient carrying the tab's existing title and subtitle.
/// No dark-mode toggle here — that lives only in Settings →
/// General → Appearance (Nov 5 rule); the preview's in-tab toggle
/// is preview chrome and is deliberately not ported.
class _FaresHero extends StatelessWidget {
  const _FaresHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kFaresDeepEmerald, Color(0xFF166534)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kFaresCardRadius),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calculate_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              const Expanded(
                child: Text(
                  'Know your fare before you go',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          const Text(
            'LTFRB fare calculator — same rates and formula as the web app.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// "Provincial" scope tag carried by every bus route card and the
/// fare breakdown sheet (preview design). Van / jeepney / tricycle
/// routes carry no scope tag.
class _ProvincialTag extends StatelessWidget {
  const _ProvincialTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kFaresDeepEmerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Provincial',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: kFaresDeepEmerald,
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

/// One Popular Routes card: vehicle icon, From → To, operator and
/// vehicle with the "Provincial" scope tag on bus cards, and the
/// route's own fare (regular + 20%-off) or "Fare not set".
class _PopularRouteCard extends StatelessWidget {
  const _PopularRouteCard({required this.route, required this.onTap});

  final PopularRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fare = route.fare;
    return Card(
      color: _faresCardColor(context),
      shape: _faresCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppLayout.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kFaresAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _popularRouteIcon(route.vehicle),
                  color: kFaresAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${route.from} → ${route.to}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        Text(
                          route.vehicle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (route.isBus) const _ProvincialTag(),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              fare == null
                  ? Text(
                      'Fare not set',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          peso(fare),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${peso(discountedFareOf(fare))} student',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: kFaresAccent),
                        ),
                      ],
                    ),
            ],
          ),
        ),
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
                  style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            amount,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
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
class _FareBreakdownSheet extends StatelessWidget {
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
    required this.distanceKm,
    required this.distanceNote,
    required this.etaMinutes,
    required this.etaNote,
    required this.fareStatus,
    required this.stops,
    required this.breakdown,
    required this.breakdownNote,
    required this.onViewOnMap,
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
  /// both known hubs. Intermediate on-the-way towns appear on the
  /// Map tab once its OSRM line loads; they are never guessed here.
  final List<({String name, String role})>? stops;

  final FareBreakdown? breakdown;
  final String? breakdownNote;
  final VoidCallback? onViewOnMap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final breakdown = this.breakdown;
    final routeFare = this.routeFare;
    final distanceKm = this.distanceKm;
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
                  const Expanded(
                    child: Text(
                      'Fare breakdown',
                      style: kFaresCardHeading,
                    ),
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
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (operator != null)
                    Text(
                      operator!,
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
                  amount: formatTripTimeShort(etaMinutes!),
                ),
              ],
              if (fareStatus != null) ...[
                const SizedBox(height: AppSpacing.s8),
                _SheetRow(
                  label: 'Fare status',
                  amount: fareStatus!,
                  bold: true,
                ),
              ],
              if (showRouteFare) ...[
                const SizedBox(height: AppSpacing.s16),
                const Text('Route fare', style: kFaresCardHeading),
                const SizedBox(height: AppSpacing.s8),
                if (routeFare != null) ...[
                  _SheetRow(
                    label: routeFareLabel ?? 'Route fare',
                    amount: peso(routeFare),
                    bold: true,
                  ),
                  _SheetRow(
                    label: 'Student discount',
                    detail: '20% off with a valid student ID',
                    amount: peso(discountedFareOf(routeFare)),
                  ),
                  _SheetRow(
                    label: 'PWD discount',
                    detail: '20% off with a valid PWD ID',
                    amount: peso(discountedFareOf(routeFare)),
                  ),
                  _SheetRow(
                    label: 'Senior Citizen discount',
                    detail: '20% off with a valid senior citizen ID',
                    amount: peso(discountedFareOf(routeFare)),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'The discounted fare applies to students, PWD, and senior citizens with a valid ID.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (routeFareNote != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      routeFareNote!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ] else ...[
                  const Text(
                    'Fare not set',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
                const Text('Calculator estimate', style: kFaresCardHeading),
                const SizedBox(height: AppSpacing.s8),
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
                    amount:
                        '−${peso(breakdown.regular - breakdown.collected)}',
                  ),
                const SizedBox(height: AppSpacing.s8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Amount to pay',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '≈ ${peso(breakdown.collected)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: kFaresAccent,
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
                  breakdownNote!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (stops != null && stops!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                const Text('Stops along the way',
                    style: kFaresCardHeading),
                const SizedBox(height: AppSpacing.s8),
                for (var i = 0; i < stops!.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            stops![i].name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          stops![i].role,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
              if (onViewOnMap != null) ...[
                const SizedBox(height: AppSpacing.s16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onViewOnMap!();
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show direction on Map'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
