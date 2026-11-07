// Searchable place picker (Nov 7, 2026 — Steven: the Fares
// From/To list only had the 16 built-in hubs, "ang liit").
//
// One shared sheet for every place choice in the app: the Fares
// Trip card (From/To), the Add Route sheet (From/To), and the
// via-stops multi-select. The merged list is long now (16 hubs +
// admin stops + the bundled Philippines list), so a plain dropdown
// or chip wall no longer works — the picker is searchable.
//
// Single-select pops the tapped [Hub]; multi-select pops the
// chosen names in tap order (via stops keep the admin's order).
// Sections, in display order: Hubs (the 16 built-ins) → My bus
// stops (admin-added) → Philippines (bundled list). A query
// flattens the list and matches name or region.
import 'package:flutter/material.dart';

import 'fares_tab.dart';
import 'ios_components.dart';
import 'philippine_places.dart';

/// Matches [places] against [query] (name, province, or region —
/// a region query like "Central Luzon" shows that region's
/// places — case-insensitive substring). An empty query returns
/// the list unchanged. Pure, so the filter behaviour is
/// unit-testable.
List<Hub> filterPlaces(List<Hub> places, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return places;
  return places.where((h) {
    if (h.name.toLowerCase().contains(q)) return true;
    if (h.region.toLowerCase().contains(q)) return true;
    final region = philippinePlaceRegion[h.name];
    return region != null && region.toLowerCase().contains(q);
  }).toList();
}

/// Section name of [places][index] in the picker: 'Hubs' for the
/// 16 built-ins, 'My bus stops' for admin stops, the place's
/// REGION for bundled places (Steven, Nov 7, 22:43: "dapat
/// organize" — the picker groups by region, alphabetical within
/// each region). Pure — the merged order is hubs (0..15), stops,
/// then bundled places in region order ([philippineRegionOrder]).
String placeSectionName(List<Hub> places, int index, int stopsCount) {
  if (index < hubs.length) return 'Hubs';
  if (index < hubs.length + stopsCount) return 'My bus stops';
  return philippineRegionOf(places[index]);
}

/// Display header for a section, with its place count.
String placeSectionLabel(String section, int count) =>
    '$section · $count';

sealed class _PickerRow {
  const _PickerRow();
}

class _SectionRow extends _PickerRow {
  const _SectionRow(this.section, this.count);

  final String section;
  final int count;
}

class _PlaceRow extends _PickerRow {
  const _PlaceRow(this.place, this.index);

  final Hub place;
  final int index;
}

/// Rows for the picker list: section headers + place rows when
/// there is no query; a flat filtered list when there is one.
/// Private — the sheet rebuilds from this on every keystroke.
List<_PickerRow> _placePickerRows({
  required List<Hub> places,
  required int stopsCount,
  required String query,
}) {
  final filtered = filterPlaces(places, query);
  if (query.trim().isNotEmpty) {
    return [
      for (final place in filtered)
        _PlaceRow(place, places.indexOf(place)),
    ];
  }
  final rows = <_PickerRow>[];
  String? current;
  for (var i = 0; i < places.length; i++) {
    final section = placeSectionName(places, i, stopsCount);
    if (section != current) {
      current = section;
      final count = places
          .asMap()
          .entries
          .where((e) => placeSectionName(places, e.key, stopsCount) == section)
          .length;
      rows.add(_SectionRow(section, count));
    }
    rows.add(_PlaceRow(places[i], i));
  }
  return rows;
}

class _PlacePickerSheet extends StatefulWidget {
  const _PlacePickerSheet({
    required this.places,
    required this.stopsCount,
    required this.title,
    this.selected,
    this.multiSelected,
    this.excludedNames = const {},
  });

  final List<Hub> places;
  final int stopsCount;
  final String title;

  /// Single-select: the currently picked place, if any.
  final Hub? selected;

  /// Multi-select: the picked names, in tap order. Null =
  /// single-select mode.
  final List<String>? multiSelected;

  /// Names shown greyed out and untappable (via stops exclude
  /// the route's From/To, as before). Never pre-selected.
  final Set<String> excludedNames;

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Multi-select picks, in tap order.
  late List<String> _multi;

  @override
  void initState() {
    super.initState();
    _multi = List.of(widget.multiSelected ?? const <String>[]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _multiMode => widget.multiSelected != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _placePickerRows(
      places: widget.places,
      stopsCount: widget.stopsCount,
      query: _query,
    );
    final placeRows = rows.whereType<_PlaceRow>().toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            IosTextField(
              controller: _searchController,
              autofocus: true,
              placeholder: 'Search a place…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.search, size: 20),
              ),
              suffix: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Text(
              _query.trim().isEmpty
                  ? '${widget.places.length} places'
                  : '${placeRows.length} '
                      '${placeRows.length == 1 ? 'place' : 'places'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: placeRows.isEmpty
                  ? Center(
                      child: Text(
                        'No places found for “$_query”.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        if (row is _SectionRow) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: 16,
                              bottom: 4,
                            ),
                            child: Text(
                              placeSectionLabel(row.section, row.count),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          );
                        }
                        final place = (row as _PlaceRow).place;
                        final excluded =
                            widget.excludedNames.contains(place.name);
                        if (_multiMode) {
                          final order = _multi.indexOf(place.name) + 1;
                          return ListTile(
                            enabled: !excluded,
                            contentPadding: EdgeInsets.zero,
                            title: Text(place.name),
                            subtitle: Text(place.region),
                            trailing: order == 0
                                ? null
                                : CircleAvatar(
                                    radius: 13,
                                    backgroundColor: scheme.primary,
                                    child: Text(
                                      '$order',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                            onTap: excluded
                                ? null
                                : () {
                                    setState(() {
                                      if (order == 0) {
                                        _multi.add(place.name);
                                      } else {
                                        _multi.remove(place.name);
                                      }
                                    });
                                  },
                          );
                        }
                        final isSelected =
                            widget.selected?.name == place.name;
                        return ListTile(
                          enabled: !excluded,
                          contentPadding: EdgeInsets.zero,
                          title: Text(place.name),
                          subtitle: Text(place.region),
                          trailing: isSelected
                              ? Icon(Icons.check, color: scheme.primary)
                              : null,
                          onTap: excluded
                              ? null
                              : () => Navigator.of(context).pop(place),
                        );
                      },
                    ),
            ),
            if (_multiMode) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_multi),
                child: Text(
                  _multi.isEmpty ? 'Done' : 'Done · ${_multi.length}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the searchable place picker and pops the tapped [Hub]
/// (null when dismissed). [places] is the merged list (hubs,
/// stops, bundled places); [stopsCount] is how many admin stops
/// it holds, so the sections land in the right places.
Future<Hub?> showPlacePicker({
  required BuildContext context,
  required List<Hub> places,
  required int stopsCount,
  Hub? selected,
  required String title,
}) {
  return showIosSheet<Hub>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PlacePickerSheet(
      places: places,
      stopsCount: stopsCount,
      title: title,
      selected: selected,
    ),
  );
}

/// Opens the searchable multi-select place picker and pops the
/// chosen names in tap order (null when dismissed). [selected]
/// pre-fills the picks (order kept). [excludedNames] are shown
/// greyed out and untappable (via stops exclude the route's
/// From/To, as before). Use for via stops, where the order is
/// the route's direction.
Future<List<String>?> showPlaceMultiPicker({
  required BuildContext context,
  required List<Hub> places,
  required int stopsCount,
  required List<String> selected,
  required String title,
  Set<String> excludedNames = const {},
}) {
  return showIosSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PlacePickerSheet(
      places: places,
      stopsCount: stopsCount,
      title: title,
      multiSelected: selected,
      excludedNames: excludedNames,
    ),
  );
}
