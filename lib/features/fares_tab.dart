// Fares tab — LTFRB fare calculator (ByaheTayo web app parity).
//
// Faithful port of the web app's faresController.js: same 11 vehicle
// rates, same formula, same 14 hubs, same distance rule (straight-line
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

import 'operator_fares.dart';

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
  const FaresTab({super.key});

  @override
  State<FaresTab> createState() => _FaresTabState();
}

class _FaresTabState extends State<FaresTab> {
  String _rateId = 'trad-jeep';
  bool _discounted = false;
  _OriginMode _originMode = _OriginMode.location;
  int _originHub = 2; // Cabugao.
  int _destHub = 1; // Vigan City.
  double? _deviceLat;
  double? _deviceLng;
  bool _locating = false;

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
              content: Text('Buksan mo muna yung Location (GPS) ng phone.'),
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
                'Kailangan ng location permission para makita kung nasaan ka.',
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

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Know your fare before you go',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'LTFRB fare calculator — parehong rates at formula ng web app.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionTitle('Sasakyan'),
                    DropdownButtonFormField<String>(
                      value: _rateId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 12),
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
                      const SizedBox(height: 8),
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
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionTitle('Biyahe'),
                    SegmentedButton<_OriginMode>(
                      segments: const [
                        ButtonSegment(
                          value: _OriginMode.location,
                          label: Text('Lokasyon ko'),
                        ),
                        ButtonSegment(
                          value: _OriginMode.hub,
                          label: Text('Pumili ng hub'),
                        ),
                      ],
                      selected: {_originMode},
                      onSelectionChanged: (selection) {
                        setState(() => _originMode = selection.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_originMode == _OriginMode.location) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _deviceLat == null
                                  ? 'Wala pang lokasyon. Pindutin para kunin ang kinaroroonan mo.'
                                  : 'Nakuha na ang lokasyon mo.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
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
                                        ? 'Gamitin ang lokasyon ko'
                                        : 'I-refresh',
                                  ),
                          ),
                        ],
                      ),
                    ] else ...[
                      DropdownButtonFormField<int>(
                        value: _originHub,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Mula sa',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _destHub,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Papunta sa',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 12),

                    if (roadKm != null) ...[
                      Text(
                        '${roadKm.toStringAsFixed(1)} km',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kinuwenta: ${directKm!.toStringAsFixed(1)} km na direktang distansya + 22% road allowance. Pwedeng mag-iba sa aktwal na ruta.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ] else
                      Text(
                        '— km',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: rate == null
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Walang nationwide tricycle rate',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tingnan ang fare matrix ng LGU. Ang tricycle fares ay itinakda ng local ordinance, kaya hindi gagawa ang EstudyanteGO ng national estimate.',
                          ),
                        ],
                      )
                    : roadKm == null
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kailangan ng starting location',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Gamitin ang lokasyon mo o pumili ng starting hub para makuwenta ang distansya at pasahe.',
                          ),
                        ],
                      )
                    : _FareAmount(
                        rate: rate,
                        roadKm: roadKm,
                        discounted: _discounted,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Estimate lang. Ang distansya ay tinatantya mula sa coordinates at pwedeng mag-iba sa aktwal na ruta. Ang official fare matrix ng operator ang masusunod sa sisingilin. Ang ₱20 ordinary city-bus minimum at ₱100 provincial-bus minimum ay ina-apply bago ang discount. Ang rates ay ayon sa temporary national fare guide, epektibo Sept. 28–Dec. 31, 2026. Ang tricycle fares ay itinakda ng bawat LGU, hindi ng isang national formula.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            sectionTitle('Posted operator fares'),
            Text(
              'Pasahe na mismong inilathala ng mga operator — reference list lang ito. Hindi ito kinuwenta ng calculator sa itaas, at hindi pinaghalo ang posted fare sa formula fare.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final group in groupOperatorFares())
              _OperatorFareGroupCard(group: group),
            const SizedBox(height: 12),
            Text(
              'Ang listahang ito ay sumasaklaw lang sa mga pasahe na opisyal na inilathala ng mga operator. Ang mga pasahe na hindi opisyal na nailathala ay hindi tinataya o isinasama.',
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
      child: ExpansionTile(
        title: Text(
          '${group.company} · ${group.fares.length} fares',
          style: const TextStyle(fontWeight: FontWeight.bold),
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
        '${peso(rate.base)} ang sakop sa unang ${rate.bracket.toStringAsFixed(rate.bracket.truncateToDouble() == rate.bracket ? 0 : 1)} km, tapos ${peso(rate.perKm)} kada susunod na km.';
    final minimumCopy = rate.minimum != null
        ? ' Ang ${peso(rate.minimum!)} minimum ay ina-apply kapag mas mababa ang formula.'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${rate.label} · ${roadKm.toStringAsFixed(1)} km',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          '≈ ${peso(result.collected)}',
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${discounted ? '20% discount applied; nearest ₱0.25 ang pinapakita.' : 'Regular fare.'} $baseCopy$minimumCopy${rate.local ? ' Dagupan local ordinance example.' : ' Estimate mula sa temporary national guide.'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
