// My Commute — the Student Hub view of the EXISTING transportation
// system. This screen does NOT duplicate Trips or navigation: saved
// routes are read from the same SharedPreferences key the Map tab
// writes ('byahetayo_saved_routes'), and "View on map" jumps to the
// Map tab with that hub selected, where Start Navigation already
// lives. Distances use the app's roadKm rule (haversine x 1.22),
// fares use the real LTFRB computeFare rates, ETAs use the web
// estimateTripMinutes model. Trip history = the commute expense log
// (the app has no backend trip log to read).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_layout.dart';
import '../community_posts.dart';
import '../fares_tab.dart' as fares;
import '../map_tab.dart' as maps;
import 'student_data.dart';

const _savedRoutesKey = 'byahetayo_saved_routes';

class CommuteScreen extends StatefulWidget {
  const CommuteScreen({super.key, this.onViewOnMap});

  /// Called to switch the shell to the Map tab (like Trips' jump).
  final VoidCallback? onViewOnMap;

  @override
  State<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends State<CommuteScreen> {
  List<String> _savedKeys = [];
  List<String> _favs = [];
  List<CommuteExpense> _expenses = [];
  String _fareModeId = 'trad-jeep';
  String _favPick = 'Vigan City';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final favs =
        await StudentStorage.loadStrings(StudentStorage.commuteFavsKey);
    final expenses =
        await StudentStorage.loadList(StudentStorage.commuteExpensesKey);
    if (!mounted) return;
    setState(() {
      _savedKeys = prefs.getStringList(_savedRoutesKey) ?? [];
      _favs = favs;
      _expenses = expenses.map(CommuteExpense.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _saveFavs() =>
      StudentStorage.saveStrings(StudentStorage.commuteFavsKey, _favs);
  Future<void> _saveExpenses() => StudentStorage.saveList(
      StudentStorage.commuteExpensesKey,
      _expenses.map((e) => e.toJson()).toList());

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  fares.Hub? _hubByName(String name) {
    for (final h in fares.hubs) {
      if (h.name == name) return h;
    }
    return null;
  }

  void _jumpToHub(String name) {
    communityMapJump.value = name;
    widget.onViewOnMap?.call();
    Navigator.pop(context);
  }

  Future<void> _openExpenseForm() async {
    final options = <String>[..._savedKeys];
    for (final f in _favs) {
      options.add('Cabugao → $f');
    }
    if (options.isEmpty) {
      _snack('Save a route on the Map tab first, or add a favorite '
          'destination below.');
      return;
    }
    final result = await showModalBottomSheet<CommuteExpense>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseForm(routeOptions: options),
    );
    if (result == null) return;
    setState(() {
      _expenses.insert(0, result);
      _expenses.sort((a, b) => b.date.compareTo(a.date));
    });
    await _saveExpenses();
    _snack('Commute expense added.');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthTotal = _expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .fold<double>(0, (s, e) => s + e.amount);
    final allTotal = _expenses.fold<double>(0, (s, e) => s + e.amount);
    final rate =
        fares.fareRates.firstWhere((r) => r.id == _fareModeId);

    return Scaffold(
      appBar: AppBar(title: const Text('My Commute')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openExpenseForm,
        icon: const Icon(Icons.add),
        label: const Text('Log expense'),
      ),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          const Text(
            'Saved routes are shared with the Map tab — save or remove '
            'them there.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppLayout.cardGap),
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
                  onSelected: (_) =>
                      setState(() => _fareModeId = mode.$2),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.headerGap),
          const Text('Saved routes',
              style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.s8),
          if (_savedKeys.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No saved routes yet.'),
                subtitle: Text(
                    'Tap the heart on any route card on the Map tab.'),
              ),
            )
          else
            for (final key in _savedKeys) _savedRouteCard(key, rate),
          const SizedBox(height: 20),
          const Text('Favorite destinations',
              style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _favPick,
                  decoration:
                      const InputDecoration(labelText: 'Destination'),
                  items: [
                    for (final h in fares.hubs)
                      DropdownMenuItem(value: h.name, child: Text(h.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _favPick = v);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              FilledButton(
                onPressed: () async {
                  if (_favs.contains(_favPick)) {
                    _snack('Already a favorite.');
                    return;
                  }
                  setState(() => _favs.add(_favPick));
                  await _saveFavs();
                },
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_favs.isEmpty)
            const Card(
                child: ListTile(title: Text('No favorite destinations.')))
          else
            for (final f in _favs)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(f),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _jumpToHub(f),
                        child: const Text('View on map'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          setState(() => _favs.remove(f));
                          await _saveFavs();
                        },
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 20),
          const Text('Commute expenses',
              style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.s8),
          Card(
            child: Padding(
              padding: AppLayout.cardPadding,
              child: Row(
                children: [
                  Expanded(
                      child: Text('This month: ${peso(monthTotal)}')),
                  Expanded(child: Text('All time: ${peso(allTotal)}')),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_expenses.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No commute expenses logged.'),
                subtitle: Text(
                    'Log what you actually paid per trip — this is your trip history.'),
              ),
            )
          else
            for (final e in _expenses)
              Card(
                child: ListTile(
                  title: Text(e.routeKey),
                  subtitle: Text(
                      '${formatDate(e.date)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(peso(e.amount),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          setState(() => _expenses
                              .removeWhere((x) => x.id == e.id));
                          await _saveExpenses();
                        },
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }

  Widget _savedRouteCard(String key, fares.FareRate rate) {
    final parts = key.split('>');
    final originName = parts.isNotEmpty ? parts[0] : key;
    final destName = parts.length > 1 ? parts[1] : '';
    final origin = _hubByName(originName);
    final dest = _hubByName(destName);
    String subtitle;
    if (origin != null && dest != null) {
      final roadKm =
          maps.roadKmBetween(origin.lat, origin.lng, dest.lat, dest.lng);
      final minutes = maps.estimateTripMinutes(
        roadKm: roadKm,
        mountain:
            maps.isMountainHub(origin) || maps.isMountainHub(dest),
        sameRegion: origin.region == dest.region,
        mode: maps.TravelMode.transit,
      );
      final fare = fares.computeFare(rate, roadKm, false).regular;
      final dir = maps.directionOf(origin.lat, dest.lat) ==
              maps.Direction.northbound
          ? 'Northbound'
          : 'Southbound';
      subtitle =
          '${roadKm.toStringAsFixed(1)} km · ${maps.formatTripTime(minutes)} · ${peso(fare)} · $dir';
    } else if (dest != null) {
      subtitle = 'From your location — open on the map for distance.';
    } else {
      subtitle = 'Saved route';
    }
    return Card(
      child: ListTile(
        title: Text('$originName → $destName'),
        subtitle: Text(subtitle),
        trailing: dest == null
            ? null
            : TextButton(
                onPressed: () => _jumpToHub(destName),
                child: const Text('View on map'),
              ),
      ),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.routeOptions});

  final List<String> routeOptions;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  late String _route;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _route = widget.routeOptions.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Log commute expense',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppLayout.cardGap),
          DropdownButtonFormField<String>(
            value: _route,
            decoration: const InputDecoration(labelText: 'Route'),
            items: [
              for (final r in widget.routeOptions)
                DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _route = v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount paid (₱)'),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _note,
            decoration:
                const InputDecoration(labelText: 'Note (optional)'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date: ${formatDate(_date)}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(_amount.text) ?? 0;
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enter an amount greater than zero.')));
                return;
              }
              Navigator.pop(
                context,
                CommuteExpense(
                  id: newId(),
                  routeKey: _route,
                  amount: amount,
                  date: _date,
                  note: _note.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
