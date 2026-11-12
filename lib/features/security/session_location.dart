// Login Alerts + Session Manager — best-effort location label.
//
// The label is OFFLINE and honest: it reads the device's last-known
// position (only when location permission is ALREADY granted —
// never requested at sign-in) and names the nearest bundled,
// verified Philippine place (the app's own `hubs` + 164
// `philippinePlaces`, coordinates from OSM/Nominatim at build
// time). No network reverse-geocode, no new permission prompt, no
// invented place: when there is no permission, no last-known
// position, or no bundled place within 50 km, the label is null
// and the UI hides the location row.
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../fares_tab.dart';
import '../philippine_places.dart';

/// Region names in the bundled data (as opposed to provinces).
/// A hub whose `region` is one of these gets its province from the
/// nearest bundled place instead, so 'Vigan City' labels as
/// 'Vigan City, Ilocos Sur' (preview wording) rather than
/// 'Vigan City, Ilocos Region'.
const _regionNames = {
  'Ilocos Region',
  'Cagayan Valley',
  'Cordillera Administrative Region',
  'Central Luzon',
  'Metro Manila',
  'CALABARZON',
  'MIMAROPA',
  'Bicol Region',
  'Western Visayas',
  'Central Visayas',
  'Eastern Visayas',
  'Zamboanga Peninsula',
  'Northern Mindanao',
  'Davao Region',
  'SOCCSKSARGEN',
  'Caraga',
  'BARMM',
};

/// Nearest bundled place must be within this distance, or there is
/// no label (never name a far-away city).
const maxLocationLabelDistanceKm = 50.0;

/// A province is borrowed from the nearest bundled place within
/// this distance when the nearest place's own region is a region
/// name rather than a province.
const maxProvinceBorrowDistanceKm = 100.0;

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadiusKm * math.asin(math.sqrt(a));
}

/// 'Vigan City, Ilocos Sur' for coordinates near Vigan, or null
/// when no bundled place is near. Pure and unit-tested.
String? locationLabelFor(double latitude, double longitude) {
  Hub? nearest;
  var nearestKm = double.infinity;
  for (final place in [...hubs, ...philippinePlaces]) {
    final distance = _haversineKm(
      latitude,
      longitude,
      place.lat,
      place.lng,
    );
    if (distance < nearestKm) {
      nearestKm = distance;
      nearest = place;
    }
  }
  if (nearest == null || nearestKm > maxLocationLabelDistanceKm) {
    return null;
  }
  final region = nearest.region;
  if (!_regionNames.contains(region)) {
    return '${nearest.name}, $region';
  }
  // Region-named hub (e.g. 'Vigan City', 'Ilocos Region'): borrow
  // the province from the nearest bundled place, which always
  // carries a province.
  Hub? nearestProvincial;
  var nearestProvincialKm = double.infinity;
  for (final place in philippinePlaces) {
    final distance = _haversineKm(
      latitude,
      longitude,
      place.lat,
      place.lng,
    );
    if (distance < nearestProvincialKm) {
      nearestProvincialKm = distance;
      nearestProvincial = place;
    }
  }
  if (nearestProvincial != null &&
      nearestProvincialKm <= maxProvinceBorrowDistanceKm) {
    return '${nearest.name}, ${nearestProvincial.region}';
  }
  return nearest.name;
}

/// Best-effort location label for a sign-in. Returns null when
/// location is unavailable for any reason — never throws, never
/// prompts. Callers await it with a short timeout and write the
/// session without a location when it resolves to null.
Future<String?> bestEffortLocationLabel() async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }
    final position = await Geolocator.getLastKnownPosition().timeout(
      const Duration(seconds: 8),
    );
    if (position == null) return null;
    return locationLabelFor(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}
