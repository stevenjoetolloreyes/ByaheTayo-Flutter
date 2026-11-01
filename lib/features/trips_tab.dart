// Trips tab — Find a Route (reference-based redesign).
//
// Follows the reference Routes screen: "Browse commute options" heading,
// "Find a Route" title, current-location indicator, Nearby Routes cards
// (transport type, start/end, distance from the origin, fare, View Full
// Route action, favorite button), session-only Recent trips, and Saved
// routes shared with the Map tab through SharedPreferences.
//
// All numbers reuse the Map tab's route helpers and the Fares tab's data
// (hubs, rates, formula) — nothing here is invented. Recent trips are
// session-only, exactly like the web app's Trips page.
//
// Routes Directory (Davao-reference function, own data only): the same
// routes grouped Northbound/Southbound, each opening a detail sheet
// with a stops list. Our routes are direct hub-to-hub, so the stops
// list is honestly just First stop -> Last stop — no invented
// intermediate stops, no Davao routes, no timetable claims.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'community_posts.dart';
import 'fares_tab.dart';
import 'map_tab.dart';

class TripsTab extends StatefulWidget {
  const TripsTab({super.key, this.onViewOnMap});

  /// Jump to the Map tab (wired in main.dart like FriendsTab).
  final VoidCallback? onViewOnMap;

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  static const _savedKey = 'byahetayo_saved_routes';
  static const _homeHub = 2; // Cabugao — default origin (Fares default).

  final _searchController = TextEditingController();
  Position? _userPos;
  bool _locating = false;
  String _searchQuery = '';
  // Vehicle filter for the directory: which real fare mode the cards
  // price with. Every hub-pair route can be served by jeepney or bus,
  // so the chips switch the fare mode instead of inventing per-route
  // vehicle assignments.
  String _fareModeId = 'trad-jeep';
  Set<String> _savedRoutes = {};
  List<RouteInfo> _recents = [];
  String? _expandedKey;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _savedRoutes = prefs.getStringList(_savedKey)?.toSet() ?? {};
        });
      }
    } catch (_) {
      // No saved routes without storage (e.g. widget tests) — stay empty.
    }
  }

  Future<void> _persistSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedKey, _savedRoutes.toList());
    } catch (_) {
      // Best-effort; the in-memory set still works this session.
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _fetchLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on Location (GPS) on your phone first.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack('Location permission is needed to see where you are.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _userPos = position);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  ({double lat, double lng, String name, Hub? hub}) _origin() {
    final pos = _userPos;
    if (pos != null) {
      return (
        lat: pos.latitude,
        lng: pos.longitude,
        name: 'Your location',
        hub: null,
      );
    }
    final hub = hubs[_homeHub];
    return (lat: hub.lat, lng: hub.lng, name: hub.name, hub: hub);
  }

  void _toggleSaved(RouteInfo route) {
    final key = '${route.originName}>${route.dest.name}';
    setState(() {
      if (_savedRoutes.contains(key)) {
        _savedRoutes.remove(key);
        _snack('Removed from saved routes.');
      } else {
        _savedRoutes.add(key);
        _snack('This route has been saved.');
      }
    });
    _persistSaved();
  }

  void _showRoute(RouteInfo route) {
    // Filter the nearby list to this destination and expand it there.
    final key = '${route.originName}>${route.dest.name}';
    setState(() {
      _searchController.text = route.dest.name;
      _searchQuery = route.dest.name;
      _expandedKey = key;
    });
  }

  void _viewRoute(RouteInfo route) {
    final key = '${route.originName}>${route.dest.name}';
    setState(() {
      _expandedKey = _expandedKey == key ? null : key;
      _recents.removeWhere((r) => '${r.originName}>${r.dest.name}' == key);
      _recents.insert(0, route);
      if (_recents.length > 10) _recents = _recents.sublist(0, 10);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final origin = _origin();
    var routes = routesFrom(origin.lat, origin.lng, origin.name);
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      routes = routes
          .where(
            (r) =>
                r.dest.name.toLowerCase().contains(q) ||
                r.dest.region.toLowerCase().contains(q),
          )
          .toList();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Browse commute options',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        const Text(
          'Find a Route',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.my_location, color: scheme.primary),
            title: Text(
              _userPos != null
                  ? 'Using your current location'
                  : 'Cabugao · default origin',
            ),
            trailing: _locating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _fetchLocation,
                    child: const Text('Use my location'),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'Search a destination…',
            filled: true,
            fillColor: scheme.surface,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.outline),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in const [
              ('Jeepney', 'trad-jeep'),
              ('Modern Jeepney', 'modern-jeep'),
              ('Bus', 'prov-ordinary'),
            ])
              ChoiceChip(
                label: Text(mode.$1),
                selected: _fareModeId == mode.$2,
                onSelected: (_) => setState(() => _fareModeId = mode.$2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Nearby Routes (${routes.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (routes.isEmpty)
          Card(
            child: ListTile(
              title: Text('No routes found for “$_searchQuery”.'),
              subtitle: const Text('Try a different destination.'),
            ),
          )
        else
          for (final route in routes) _routeCard(route, origin),
        // Routes Directory: same routes, grouped by direction like the
        // reference app's routes list. Rows show the destination only
        // (the origin is the section header) so the Nearby card titles
        // stay unique. Tap opens the detail sheet with the stops list.
        if (routes.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Routes Directory · From ${origin.name}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final dir in const [
            Direction.northbound,
            Direction.southbound,
          ])
            if (groupRoutesByDirection(routes)[dir]!.isNotEmpty) ...[
              Text(
                dir == Direction.northbound
                    ? '↑ NORTHBOUND (${groupRoutesByDirection(routes)[dir]!.length})'
                    : '↓ SOUTHBOUND (${groupRoutesByDirection(routes)[dir]!.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final route in groupRoutesByDirection(routes)[dir]!)
                _directoryRow(route),
              const SizedBox(height: 8),
            ],
        ],
        if (_recents.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Recent trips',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Chip(
                label: const Text('Current session only'),
                labelStyle: const TextStyle(fontSize: 11),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final route in _recents) _summaryCard(route),
        ],
        if (_savedRoutes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Saved routes',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final key in _savedRoutes)
            Builder(
              builder: (context) {
                final destName = key.split('>').length == 2
                    ? key.split('>')[1]
                    : '';
                final match = routes.where((r) => r.dest.name == destName);
                if (match.isEmpty) return const SizedBox.shrink();
                return _summaryCard(match.first);
              },
            ),
        ],
      ],
    );
  }

  Widget _routeCard(
    RouteInfo route,
    ({double lat, double lng, String name, Hub? hub}) origin, {
    bool detailed = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final key = '${route.originName}>${route.dest.name}';
    final saved = _savedRoutes.contains(key);
    final expanded = detailed && _expandedKey == key;
    final rate = fareRates.firstWhere((r) => r.id == _fareModeId);
    final fare = computeFare(
      rate,
      route.roadKm,
      false,
    );

    String? walkText;
    if (origin.hub == null && _userPos != null) {
      walkText = 'You are here';
    } else if (origin.hub != null && _userPos != null) {
      walkText =
          '${roadKmBetween(_userPos!.latitude, _userPos!.longitude, origin.lat, origin.lng).toStringAsFixed(1)} km to origin';
    }

    String? detailFareNote;
    // The verified fares are bus fares, so the note only applies when
    // the Bus fare mode is selected.
    if (expanded && origin.hub != null && _fareModeId == 'prov-ordinary') {
      final verified = knownBusFares['${origin.hub!.name}|${route.dest.name}'];
      if (verified != null) {
        detailFareNote =
            'User-verified bus fare: ₱$verified (reported Oct 16, 2026).';
      }
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.directions_bus_outlined),
            title: Text('${route.originName} → ${route.dest.name}'),
            subtitle: Text(
              '${rate.label} · ${route.roadKm.toStringAsFixed(1)} km · '
              '${route.direction == Direction.northbound ? 'Northbound' : 'Southbound'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peso(fare.regular),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    saved ? Icons.favorite : Icons.favorite_border,
                    color: saved ? Colors.red : null,
                  ),
                  tooltip: saved ? 'Remove from saved' : 'Save route',
                  onPressed: () => _toggleSaved(route),
                ),
              ],
            ),
          ),
          if (detailed)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _viewRoute(route),
                child: Text(expanded ? 'Hide full route' : 'View full route'),
              ),
            ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _detailRow(
                    'Distance',
                    '${route.roadKm.toStringAsFixed(1)} km',
                  ),
                  _detailRow(
                    'Estimated time',
                    'About ${formatTripTime(estimateTripMinutes(roadKm: route.roadKm < 1 ? 1 : route.roadKm, mountain: (origin.hub != null && isMountainHub(origin.hub!)) || isMountainHub(route.dest), sameRegion: origin.hub != null && origin.hub!.region == route.dest.region, mode: TravelMode.transit))}',
                  ),
                  _detailRow('Rides', '1 direct ride'),
                  if (walkText != null)
                    _detailRow('Walking distance', walkText),
                  _detailRow('Estimated fare', peso(fare.regular)),
                  if (detailFareNote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          detailFareNote,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _directoryRow(RouteInfo route) {
    final scheme = Theme.of(context).colorScheme;
    final key = '${route.originName}>${route.dest.name}';
    final saved = _savedRoutes.contains(key);
    final rate = fareRates.firstWhere((r) => r.id == _fareModeId);
    final fare = computeFare(rate, route.roadKm, false);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.directions_bus_outlined),
        title: Text(route.dest.name),
        subtitle: Text(
          '2 stops · ${route.roadKm.toStringAsFixed(1)} km · '
          '${route.direction == Direction.northbound ? 'Northbound' : 'Southbound'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              peso(fare.regular),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            IconButton(
              icon: Icon(
                saved ? Icons.favorite : Icons.favorite_border,
                color: saved ? Colors.red : null,
              ),
              tooltip: saved ? 'Remove from saved' : 'Save route',
              onPressed: () => _toggleSaved(route),
            ),
          ],
        ),
        onTap: () => _showDirectoryDetail(route),
      ),
    );
  }

  void _showDirectoryDetail(RouteInfo route) {
    final origin = _origin();
    final rate = fareRates.firstWhere((r) => r.id == _fareModeId);
    final fare = computeFare(rate, route.roadKm, false);
    final minutes = estimateTripMinutes(
      roadKm: route.roadKm < 1 ? 1 : route.roadKm,
      mountain: (origin.hub != null && isMountainHub(origin.hub!)) ||
          isMountainHub(route.dest),
      sameRegion:
          origin.hub != null && origin.hub!.region == route.dest.region,
      mode: TravelMode.transit,
    );
    final key = '${route.originName}>${route.dest.name}';
    final saved = _savedRoutes.contains(key);
    String? detailFareNote;
    if (origin.hub != null && _fareModeId == 'prov-ordinary') {
      final verified = knownBusFares['${origin.hub!.name}|${route.dest.name}'];
      if (verified != null) {
        detailFareNote =
            'User-verified bus fare: ₱$verified (reported Oct 16, 2026).';
      }
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${route.originName} → ${route.dest.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'No verified timetable yet — AM/PM cannot filter '
              'departures yet.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Stops',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_checked, size: 18),
              title: Text(route.originName),
              subtitle: const Text('First stop'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.location_on, size: 18),
              title: Text(route.dest.name),
              subtitle: const Text('Last stop'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const Text(
              'Direct route — no intermediate stops.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            _detailRow('Distance', '${route.roadKm.toStringAsFixed(1)} km'),
            _detailRow(
              'Estimated time',
              'About ${formatTripTime(minutes)}',
            ),
            _detailRow('Rides', '1 direct ride'),
            _detailRow('Estimated fare', peso(fare.regular)),
            if (detailFareNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  detailFareNote,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // Same jump the Friends tab uses: the Map tab listens
                  // to this notifier and selects the hub, then the tab
                  // switch shows it.
                  communityMapJump.value = route.dest.name;
                  widget.onViewOnMap?.call();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.map),
                label: const Text('View on map'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _toggleSaved(route);
                  Navigator.pop(context);
                },
                icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                label: Text(saved ? 'Remove from saved' : 'Save route'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact card for Recent / Saved lists. Tapping it filters the nearby
  /// list to this destination and expands it there.
  Widget _summaryCard(RouteInfo route) {
    final scheme = Theme.of(context).colorScheme;
    final key = '${route.originName}>${route.dest.name}';
    final saved = _savedRoutes.contains(key);
    final rate = fareRates.firstWhere((r) => r.id == _fareModeId);
    final fare = computeFare(
      rate,
      route.roadKm,
      false,
    );
    return Card(
      child: ListTile(
        leading: const Icon(Icons.directions_bus_outlined),
        title: Text('${route.originName} → ${route.dest.name}'),
        subtitle: Text(
          '${rate.label} · ${route.roadKm.toStringAsFixed(1)} km',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              peso(fare.regular),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            IconButton(
              icon: Icon(
                saved ? Icons.favorite : Icons.favorite_border,
                color: saved ? Colors.red : null,
              ),
              tooltip: saved ? 'Remove from saved' : 'Save route',
              onPressed: () => _toggleSaved(route),
            ),
          ],
        ),
        onTap: () => _showRoute(route),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
