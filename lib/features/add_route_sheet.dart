// Add Route form sheet (admin-only, Nov 6, 2026).
//
// The admin picks From/To hubs, the operator (preset chips or free
// text), the vehicle, the fare, and the route's OWN via-stops in
// order — the line the Map draws for this route. Saving is blocked
// until every required field is valid; nothing is invented (no
// guessed fare, time, or distance). The sheet returns the saved
// [CustomRoute] on success, null when dismissed. The repository
// re-checks the admin allowlist on save — this sheet never trusts
// its caller alone.
import 'package:flutter/material.dart';

import 'custom_routes.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';

/// Add (or edit, when [existing] is given) an admin route. Returns
/// the saved route through the sheet result.
class AddRouteSheet extends StatefulWidget {
  const AddRouteSheet({
    super.key,
    this.existing,
    required this.repository,
    required this.author,
  });

  final CustomRoute? existing;
  final CustomRouteRepository repository;
  final AuthUser author;

  @override
  State<AddRouteSheet> createState() => _AddRouteSheetState();
}

class _AddRouteSheetState extends State<AddRouteSheet> {
  String? _from;
  String? _to;
  final _operatorController = TextEditingController();
  String? _vehicle;
  final _fareController = TextEditingController();
  final _viaHubs = <String>[];
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _from = existing.from;
      _to = existing.to;
      _operatorController.text = existing.operator;
      _vehicle = existing.vehicle;
      _fareController.text = existing.fare.toStringAsFixed(
        existing.fare.truncateToDouble() == existing.fare ? 0 : 2,
      );
      _viaHubs.addAll(existing.viaHubs);
    }
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _fareController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
        viaHubs: List.of(_viaHubs),
      );
      final saved = widget.existing == null
          ? await widget.repository.create(route, widget.author)
          : await widget.repository.update(route, widget.author);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('StateError: ', '');
          _saving = false;
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
              widget.existing == null ? 'Add Route' : 'Edit Route',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only admins can add routes. The fare and line are yours — '
              'nothing here is guessed.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _from,
              decoration: const InputDecoration(labelText: 'From *'),
              items: [
                for (final hub in hubs)
                  DropdownMenuItem(value: hub.name, child: Text(hub.name)),
              ],
              onChanged: (v) => setState(() {
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
              onChanged: (v) => setState(() {
                _to = v;
                _viaHubs.remove(v);
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _operatorController,
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
                    onSelected: (_) => setState(
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
                    onSelected: (_) =>
                        setState(() => _vehicle = vehicle),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fareController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fare (₱) *',
                hintText: 'e.g. 60',
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
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : widget.existing == null
                    ? 'Add Route'
                    : 'Save Changes',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
