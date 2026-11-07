// Add / edit Route form sheet (admin-only, Nov 6, 2026; fare,
// student-fare, and direction editing added Nov 7, 2026).
//
// The admin picks From/To hubs, the operator (preset chips or free
// text), the vehicle, the fare, the student fare, and the route's
// OWN via-stops in order — the line the Map draws for this route.
// Saving is blocked until every required field is valid; nothing
// is invented (no guessed fare, time, or distance). The sheet
// returns an [AddRouteSheetResult] on success, null when dismissed.
// The repository re-checks the admin allowlist on save — this sheet
// never trusts its caller alone.
//
// Two modes:
// * Custom routes (the default constructor): create or edit an
//   admin-added route in `custom_routes`. The student fare is
//   optional — blank means 20% off the regular fare. An existing
//   route can also be deleted from here.
// * Built-in (seeded) routes ([AddRouteSheet.editSeededRoute]):
//   the route's From/To/operator/vehicle identify it and are
//   shown read-only; only the fare, the student fare, and the via
//   stops are editable, saved as a [RouteFareOverride]. Blank fare
//   / student fare means "keep the built-in value" (derive 20% off
//   for the student fare); clearing everything resets the route
//   to its built-in values.
import 'package:flutter/material.dart';

import 'custom_routes.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';
import 'route_fare_overrides.dart';

/// What the Add / Edit Route sheet returns on success. Null still
/// means "dismissed without saving".
class AddRouteSheetResult {
  const AddRouteSheetResult.saved(this.route)
    : deleted = false,
      override = null;

  const AddRouteSheetResult.deleted()
    : route = null,
      deleted = true,
      override = null;

  const AddRouteSheetResult.savedOverride(this.override)
    : route = null,
      deleted = false;

  const AddRouteSheetResult.deletedOverride()
    : route = null,
      deleted = true,
      override = null;

  /// The saved admin-added route (custom mode).
  final CustomRoute? route;

  /// The saved seeded-route override (seeded mode).
  final RouteFareOverride? override;

  /// True when the route (custom mode) or its override (seeded
  /// mode) was deleted — the route reverts to its built-in values
  /// in seeded mode.
  final bool deleted;
}

/// Add (or edit, when [existing] is given) an admin route. Returns
/// the saved route through the sheet result.
class AddRouteSheet extends StatefulWidget {
  const AddRouteSheet({
    super.key,
    this.existing,
    required this.repository,
    required this.author,
  }) : seededRoute = null,
       existingOverride = null,
       overrideRepository = null;

  /// Edit the fare, student fare, and direction of a built-in
  /// (seeded) route. [route] is the route as shown (with any
  /// current override already merged in); [existingOverride] is
  /// the stored override, if any.
  const AddRouteSheet.editSeededRoute({
    super.key,
    required PopularRoute route,
    this.existingOverride,
    required this.overrideRepository,
    required this.author,
  }) : existing = null,
       repository = null,
       seededRoute = route;

  final CustomRoute? existing;
  final CustomRouteRepository? repository;
  final AuthUser author;

  /// Seeded mode only: the built-in route being edited.
  final PopularRoute? seededRoute;

  /// Seeded mode only: the stored override, if any.
  final RouteFareOverride? existingOverride;

  /// Seeded mode only: where the override is saved.
  final RouteFareOverrideRepository? overrideRepository;

  @override
  State<AddRouteSheet> createState() => _AddRouteSheetState();
}

class _AddRouteSheetState extends State<AddRouteSheet> {
  String? _from;
  String? _to;
  final _operatorController = TextEditingController();
  String? _vehicle;
  final _fareController = TextEditingController();
  final _studentFareController = TextEditingController();
  final _viaHubs = <String>[];
  String? _error;
  bool _saving = false;
  bool _deleting = false;

  /// True when editing a built-in route's override (not a custom
  /// route): From/To/operator/vehicle are read-only, and saving
  /// goes through the override repository.
  bool get _seededMode => widget.overrideRepository != null;

  static String _fareText(double? value) {
    if (value == null) return '';
    return value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 2,
    );
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _from = existing.from;
      _to = existing.to;
      _operatorController.text = existing.operator;
      _vehicle = existing.vehicle;
      _fareController.text = _fareText(existing.fare);
      _studentFareController.text = _fareText(existing.studentFare);
      _viaHubs.addAll(existing.viaHubs);
      return;
    }
    final seeded = widget.seededRoute;
    if (seeded != null) {
      final override = widget.existingOverride;
      _from = seeded.from;
      _to = seeded.to;
      _operatorController.text = seeded.operator ?? '';
      _vehicle = seeded.vehicle;
      _fareController.text = _fareText(override?.fare ?? seeded.fare);
      _studentFareController.text = _fareText(override?.studentFare);
      _viaHubs.addAll(override?.viaHubs ?? seeded.viaHubs);
    }
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _fareController.dispose();
    _studentFareController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_seededMode) {
      await _saveOverride();
      return;
    }
    final error = validateCustomRoute(
      from: _from,
      to: _to,
      operator: _operatorController.text,
      vehicle: _vehicle,
      fareText: _fareController.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final (studentFare, studentError) = parseOptionalFare(
      _studentFareController.text,
    );
    if (studentError != null) {
      setState(() => _error = studentError);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final route = CustomRoute(
        id: widget.existing?.id,
        from: _from!,
        to: _to!,
        operator: _operatorController.text.trim(),
        vehicle: _vehicle!,
        fare: double.parse(_fareController.text.trim()),
        studentFare: studentFare,
        viaHubs: List.of(_viaHubs),
      );
      final repository = widget.repository!;
      final saved = widget.existing == null
          ? await repository.create(route, widget.author)
          : await repository.update(route, widget.author);
      if (mounted) {
        Navigator.pop(context, AddRouteSheetResult.saved(saved));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('StateError: ', '');
          _saving = false;
        });
      }
    }
  }

  /// Seeded mode: save the fare / student fare / via-stops
  /// override. Blank fare / student fare means "keep the built-in
  /// value"; when everything is blank/empty the stored override
  /// is deleted instead, resetting the route to built-in.
  Future<void> _saveOverride() async {
    final seeded = widget.seededRoute!;
    final (fare, fareError) = parseOptionalFare(_fareController.text);
    if (fareError != null) {
      setState(() => _error = fareError);
      return;
    }
    final (studentFare, studentError) = parseOptionalFare(
      _studentFareController.text,
    );
    if (studentError != null) {
      setState(() => _error = studentError);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final repository = widget.overrideRepository!;
      final reset =
          fare == null && studentFare == null && _viaHubs.isEmpty;
      if (reset) {
        await repository.delete(
          seededRouteKey(seeded.from, seeded.to),
          widget.author,
        );
        if (mounted) {
          Navigator.pop(
            context,
            const AddRouteSheetResult.deletedOverride(),
          );
        }
        return;
      }
      final override = RouteFareOverride(
        routeKey: seededRouteKey(seeded.from, seeded.to),
        fare: fare,
        studentFare: studentFare,
        viaHubs: List.of(_viaHubs),
      );
      final saved = await repository.save(override, widget.author);
      if (mounted) {
        Navigator.pop(context, AddRouteSheetResult.savedOverride(saved));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('StateError: ', '');
          _saving = false;
        });
      }
    }
  }

  /// Custom mode only: delete the existing admin-added route
  /// after a confirm. Seeded routes are never deletable.
  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this route?'),
        content: Text(
          '${existing.from} → ${existing.to} will be removed from '
          'Popular Routes. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository!.delete(existing, widget.author);
      if (mounted) {
        Navigator.pop(context, const AddRouteSheetResult.deleted());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('StateError: ', '');
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viaChoices = hubs
        .where((h) => h.name != _from && h.name != _to)
        .toList();
    final busy = _saving || _deleting;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _seededMode
                  ? 'Edit Route'
                  : widget.existing == null
                  ? 'Add Route'
                  : 'Edit Route',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _seededMode
                  ? 'Fare, student fare, and direction are yours — '
                        'nothing here is guessed. Blank fare keeps the '
                        'built-in fare; blank student fare means 20% off.'
                  : 'Only admins can add routes. The fare and line are yours — '
                        'nothing here is guessed.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _from,
              decoration: const InputDecoration(labelText: 'From *'),
              items: [
                for (final hub in hubs)
                  DropdownMenuItem(value: hub.name, child: Text(hub.name)),
              ],
              onChanged: _seededMode
                  ? null
                  : (v) => setState(() {
                      _from = v;
                      _viaHubs.remove(v);
                    }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _to,
              decoration: const InputDecoration(labelText: 'To *'),
              items: [
                for (final hub in hubs)
                  DropdownMenuItem(value: hub.name, child: Text(hub.name)),
              ],
              onChanged: _seededMode
                  ? null
                  : (v) => setState(() {
                      _to = v;
                      _viaHubs.remove(v);
                    }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _operatorController,
              readOnly: _seededMode,
              decoration: const InputDecoration(
                labelText: 'Operator / Bus company *',
                hintText: 'e.g. Partas',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in customRouteOperatorPresets)
                  FilterChip(
                    label: Text(preset),
                    selected:
                        _operatorController.text.trim() == preset,
                    onSelected: _seededMode
                        ? null
                        : (_) => setState(
                            () => _operatorController.text = preset,
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Vehicle *'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final vehicle in customRouteVehicles)
                  ChoiceChip(
                    label: Text(vehicle),
                    selected: _vehicle == vehicle,
                    onSelected: _seededMode
                        ? null
                        : (_) => setState(() => _vehicle = vehicle),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fareController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _seededMode ? 'Fare (₱)' : 'Fare (₱) *',
                hintText: _seededMode
                    ? 'Blank = keep the built-in fare'
                    : 'e.g. 60',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _studentFareController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Student fare (₱)',
                hintText: 'Blank = 20% off the regular fare',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Via stops — in order (optional)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap stops in the order the bus passes them. The map '
              'draws this route through them, so each operator can '
              'have its own line.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (_viaHubs.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _viaHubs.length; i++)
                    Chip(
                      label: Text('${i + 1}. ${_viaHubs[i]}'),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () =>
                          setState(() => _viaHubs.removeAt(i)),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final hub in viaChoices)
                  FilterChip(
                    label: Text(hub.name),
                    selected: _viaHubs.contains(hub.name),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _viaHubs.add(hub.name);
                      } else {
                        _viaHubs.remove(hub.name);
                      }
                    }),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : _seededMode
                    ? 'Save Changes'
                    : widget.existing == null
                    ? 'Add Route'
                    : 'Save Changes',
              ),
            ),
            if (!_seededMode && widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : _delete,
                child: Text(
                  _deleting ? 'Deleting…' : 'Delete route',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
