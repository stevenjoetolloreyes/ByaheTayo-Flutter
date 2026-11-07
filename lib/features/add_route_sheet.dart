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

import 'bus_companies.dart';
import 'bus_stops.dart';
import 'custom_routes.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';
import 'route_fare_overrides.dart';

/// The Add Route form's values, stashed when the admin leaves
/// the sheet mid-edit to place a new bus stop on the map
/// ("+ Add bus stop") and restored when the sheet reopens — so
/// nothing typed is lost. Plain values only, no repository.
class AddRouteSheetDraft {
  const AddRouteSheetDraft({
    this.from,
    this.to,
    this.operator = '',
    this.vehicle,
    this.fareText = '',
    this.studentFareText = '',
    this.pwdFareText = '',
    this.seniorFareText = '',
    this.viaHubs = const [],
  });

  final String? from;
  final String? to;
  final String operator;
  final String? vehicle;
  final String fareText;
  final String studentFareText;
  final String pwdFareText;
  final String seniorFareText;
  final List<String> viaHubs;
}

/// What the Add / Edit Route sheet returns on success. Null still
/// means "dismissed without saving".
class AddRouteSheetResult {
  const AddRouteSheetResult.saved(this.route, {this.companiesChanged = false})
    : deleted = false,
      override = null,
      addBusStopDraft = null;

  const AddRouteSheetResult.deleted()
    : route = null,
      deleted = true,
      override = null,
      addBusStopDraft = null,
      companiesChanged = false;

  const AddRouteSheetResult.savedOverride(
    this.override, {
    this.companiesChanged = false,
  }) : route = null,
       deleted = false,
       addBusStopDraft = null;

  const AddRouteSheetResult.deletedOverride()
    : route = null,
      deleted = true,
      override = null,
      addBusStopDraft = null,
      companiesChanged = false;

  /// The admin tapped "+ Add bus stop": no route was saved; the
  /// caller should open the map's add-stop mode, then reopen
  /// this sheet pre-filled from [addBusStopDraft].
  const AddRouteSheetResult.addBusStop(
    this.addBusStopDraft, {
    this.companiesChanged = false,
  }) : route = null,
       deleted = false,
       override = null;

  /// The saved admin-added route (custom mode).
  final CustomRoute? route;

  /// The saved seeded-route override (seeded mode).
  final RouteFareOverride? override;

  /// True when the route (custom mode) or its override (seeded
  /// mode) was deleted — the route reverts to its built-in values
  /// in seeded mode.
  final bool deleted;

  /// The stashed form values, only when the admin left to place
  /// a new bus stop on the map.
  final AddRouteSheetDraft? addBusStopDraft;

  /// True when the admin added a bus company in this sheet — the
  /// caller should reload its company list.
  final bool companiesChanged;
}

/// Add (or edit, when [existing] is given) an admin route. Returns
/// the saved route through the sheet result.
class AddRouteSheet extends StatefulWidget {
  const AddRouteSheet({
    super.key,
    this.existing,
    required this.repository,
    required this.author,
    this.busStops = const [],
    this.busCompanies = const [],
    this.companyRepository,
    this.initialDraft,
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
    this.busStops = const [],
    this.busCompanies = const [],
    this.companyRepository,
    this.initialDraft,
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

  /// Admin-added bus stops, merged after the 16 built-in hubs in
  /// the From/To and via-stops pickers.
  final List<BusStop> busStops;

  /// Admin-added bus companies, merged after the preset operator
  /// chips (case-insensitive dedupe — see [allOperators]).
  final List<BusCompany> busCompanies;

  /// Where a new company is saved (custom mode only — seeded
  /// mode's operator is read-only). Null = no company can be
  /// added from this sheet.
  final BusCompanyRepository? companyRepository;

  /// Form values to pre-fill from (the admin returning from
  /// placing a bus stop on the map). Wins over [existing] /
  /// [existingOverride] for the fields it carries.
  final AddRouteSheetDraft? initialDraft;

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
  final _pwdFareController = TextEditingController();
  final _seniorFareController = TextEditingController();
  final _viaHubs = <String>[];
  String? _error;
  bool _saving = false;
  bool _deleting = false;

  /// Operator chips shown: the presets first, then the
  /// admin-added companies (case-insensitive dedupe).
  late List<String> _companies;

  /// Inline "+ Add company" form state (custom mode only).
  bool _addingCompany = false;
  final _companyController = TextEditingController();
  bool _companySaving = false;
  String? _companyError;

  /// True once the admin added a company in this sheet — the
  /// caller reloads its company list on any result.
  bool _companiesChanged = false;

  /// Companies added in this sheet session (the chips recompute
  /// from the passed-in list + these, so a second add never
  /// drops the first).
  final _addedCompanies = <BusCompany>[];

  /// From/To + via-stops choices: the 16 built-in hubs first,
  /// then the admin-added bus stops (indices 0–15 never shift).
  List<Hub> get _allHubs => allHubs(widget.busStops);

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
    _companies = allOperators(widget.busCompanies);
    final existing = widget.existing;
    if (existing != null) {
      _from = existing.from;
      _to = existing.to;
      _operatorController.text = existing.operator;
      _vehicle = existing.vehicle;
      _fareController.text = _fareText(existing.fare);
      _studentFareController.text = _fareText(existing.studentFare);
      _pwdFareController.text = _fareText(existing.pwdFare);
      _seniorFareController.text = _fareText(existing.seniorFare);
      _viaHubs.addAll(existing.viaHubs);
    } else {
      final seeded = widget.seededRoute;
      if (seeded != null) {
        final override = widget.existingOverride;
        _from = seeded.from;
        _to = seeded.to;
        _operatorController.text = seeded.operator ?? '';
        _vehicle = seeded.vehicle;
        _fareController.text = _fareText(override?.fare ?? seeded.fare);
        _studentFareController.text = _fareText(override?.studentFare);
        _pwdFareController.text = _fareText(override?.pwdFare);
        _seniorFareController.text = _fareText(override?.seniorFare);
        _viaHubs.addAll(override?.viaHubs ?? seeded.viaHubs);
      }
    }
    // Returning from the map's add-stop mode: the stashed form
    // values win over the pre-fill above, so nothing typed is lost.
    final draft = widget.initialDraft;
    if (draft != null) {
      if (!_seededMode) {
        _from = draft.from;
        _to = draft.to;
        _operatorController.text = draft.operator;
        _vehicle = draft.vehicle;
      }
      _fareController.text = draft.fareText;
      _studentFareController.text = draft.studentFareText;
      _pwdFareController.text = draft.pwdFareText;
      _seniorFareController.text = draft.seniorFareText;
      _viaHubs
        ..clear()
        ..addAll(draft.viaHubs);
    }
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _fareController.dispose();
    _studentFareController.dispose();
    _pwdFareController.dispose();
    _seniorFareController.dispose();
    _companyController.dispose();
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
      busStops: widget.busStops,
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
    final (pwdFare, pwdError) = parseOptionalFare(
      _pwdFareController.text,
    );
    if (pwdError != null) {
      setState(() => _error = pwdError);
      return;
    }
    final (seniorFare, seniorError) = parseOptionalFare(
      _seniorFareController.text,
    );
    if (seniorError != null) {
      setState(() => _error = seniorError);
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
        pwdFare: pwdFare,
        seniorFare: seniorFare,
        viaHubs: List.of(_viaHubs),
      );
      final repository = widget.repository!;
      final saved = widget.existing == null
          ? await repository.create(
              route,
              widget.author,
              busStops: widget.busStops,
            )
          : await repository.update(
              route,
              widget.author,
              busStops: widget.busStops,
            );
      if (mounted) {
        Navigator.pop(
          context,
          AddRouteSheetResult.saved(
            saved,
            companiesChanged: _companiesChanged,
          ),
        );
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

  /// Seeded mode: save the fare / discount fares / via-stops
  /// override. Blank fare / discount fares means "keep the
  /// built-in value"; when everything is blank/empty the stored
  /// override is deleted instead, resetting the route to
  /// built-in. A drawn line (the override's viaWaypoints) is
  /// never part of the reset check and is carried through every
  /// save — clearing the fares must not wipe the line.
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
    final (pwdFare, pwdError) = parseOptionalFare(
      _pwdFareController.text,
    );
    if (pwdError != null) {
      setState(() => _error = pwdError);
      return;
    }
    final (seniorFare, seniorError) = parseOptionalFare(
      _seniorFareController.text,
    );
    if (seniorError != null) {
      setState(() => _error = seniorError);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final repository = widget.overrideRepository!;
      final existingWaypoints = widget.existingOverride?.viaWaypoints;
      final reset =
          fare == null &&
          studentFare == null &&
          pwdFare == null &&
          seniorFare == null &&
          _viaHubs.isEmpty &&
          (existingWaypoints == null || existingWaypoints.isEmpty);
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
        pwdFare: pwdFare,
        seniorFare: seniorFare,
        viaHubs: List.of(_viaHubs),
        viaWaypoints: existingWaypoints,
      );
      final saved = await repository.save(override, widget.author);
      if (mounted) {
        Navigator.pop(
          context,
          AddRouteSheetResult.savedOverride(
            saved,
            companiesChanged: _companiesChanged,
          ),
        );
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

  /// "+ Add bus stop": stash the form as a draft and close the
  /// sheet without saving — the caller opens the map's add-stop
  /// mode, then reopens this sheet pre-filled from the draft.
  void _requestAddBusStop() {
    Navigator.pop(
      context,
      AddRouteSheetResult.addBusStop(
        AddRouteSheetDraft(
          from: _from,
          to: _to,
          operator: _operatorController.text,
          vehicle: _vehicle,
          fareText: _fareController.text,
          studentFareText: _studentFareController.text,
          pwdFareText: _pwdFareController.text,
          seniorFareText: _seniorFareController.text,
          viaHubs: List.of(_viaHubs),
        ),
        companiesChanged: _companiesChanged,
      ),
    );
  }

  /// "+ Add company": saves the typed name (the repository
  /// dedupes case-insensitively — a duplicate returns the
  /// existing company, never a second doc), adds it to this
  /// sheet's chips, and selects it as the operator.
  Future<void> _addCompany() async {
    final repository = widget.companyRepository;
    if (repository == null) return;
    final name = _companyController.text.trim();
    if (name.isEmpty) {
      setState(() => _companyError = 'Type a company name first.');
      return;
    }
    setState(() {
      _companyError = null;
      _companySaving = true;
    });
    try {
      final saved = await repository.create(
        BusCompany(
          name: name,
          authorUid: widget.author.uid,
          authorEmail: widget.author.email,
        ),
        widget.author,
      );
      if (!mounted) return;
      setState(() {
        _addedCompanies.add(saved);
        _companies = allOperators([
          ...widget.busCompanies,
          ..._addedCompanies,
        ]);
        _operatorController.text = saved.name;
        _companiesChanged = true;
        _addingCompany = false;
        _companyController.clear();
        _companySaving = false;
      });
    } on ArgumentError catch (e) {
      if (!mounted) return;
      final message = e.message;
      setState(() {
        _companyError =
            message is String ? message : 'Could not add the company.';
        _companySaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _companyError = 'Could not add the company.';
        _companySaving = false;
      });
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
    final viaChoices = _allHubs
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
                  ? 'Fare, discount fares, and direction are yours — '
                        'nothing here is guessed. Blank fare keeps the '
                        'built-in fare; blank discount fares mean 20% off.'
                  : 'Only admins can add routes. The fare and line are yours — '
                        'nothing here is guessed.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _from,
              decoration: const InputDecoration(labelText: 'From *'),
              items: [
                for (final hub in _allHubs)
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
                for (final hub in _allHubs)
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
                for (final preset in _companies)
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
                // Custom mode only (seeded mode's operator is
                // read-only): add a bus company that is not in
                // the list yet. It appears as a chip at once and
                // is selected as the operator.
                if (!_seededMode && widget.companyRepository != null)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add company'),
                    onPressed: busy
                        ? null
                        : () => setState(() => _addingCompany = true),
                  ),
              ],
            ),
            if (_addingCompany) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _companyController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Company name',
                        hintText: 'e.g. Florida Bus',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _companySaving ? null : _addCompany,
                    child: Text(_companySaving ? 'Saving…' : 'Save'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _companySaving
                        ? null
                        : () => setState(() {
                            _addingCompany = false;
                            _companyController.clear();
                            _companyError = null;
                          }),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              if (_companyError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _companyError!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
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
            const SizedBox(height: 12),
            TextField(
              controller: _pwdFareController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'PWD fare (₱)',
                hintText: 'Blank = 20% off the regular fare',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _seniorFareController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Senior fare (₱)',
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
                // A stop that is not in the list yet: tap the map
                // to place it, name it, and come back here — the
                // form values are stashed and restored, so
                // nothing typed is lost.
                ActionChip(
                  avatar: const Icon(Icons.add_location_alt, size: 18),
                  label: const Text('Add bus stop'),
                  onPressed: busy ? null : _requestAddBusStop,
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
