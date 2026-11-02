// Walking Goal — local-only step records (no backend, no Firestore).
//
// The Android step-counter sensor reports a CUMULATIVE total since
// the last device boot. A naive sum of sensor values double-counts
// across app restarts, so the controller converts the stream to
// daily deltas instead:
//
//   * Same day: today's steps grow by (new cumulative - last seen).
//   * App restart: the persisted last-seen value makes the first
//     event after restart contribute only its delta, never the
//     whole cumulative total again.
//   * Device reboot: the sensor resets to 0, so a new cumulative
//     LOWER than the last-seen value means "steps since reboot" —
//     those are added to today's total, and the prior total is kept.
//   * New day: yesterday's total is archived into history and today
//     restarts from the new cumulative value.
//
// Steps walked while the app is closed are NOT tracked live (modern
// Android does not permit continuous background sensor listening
// without a foreground service, which this feature deliberately
// does not run). They are still picked up on reopen: the sensor
// kept counting since boot, so the first event after reopen
// contributes the whole closed-app delta to the current day —
// unless a reboot or a date boundary happened in between, in which
// case the reboot rule above applies and cross-midnight steps land
// on the reopen day. That limit is stated in the UI, not hidden.
//
// Distance, duration, and calories are ESTIMATES from step count
// (average stride 0.762 m, ~100 steps per minute, 0.04 kcal/step)
// and are always labeled as estimates in the UI.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'walking_sensor.dart';

/// Asia/Manila date key (yyyy-MM-dd). The Philippines has no daylight
/// saving, so a fixed UTC+8 shift is exact — no tz database needed.
String manilaDateKey(DateTime now) {
  final manila = now.toUtc().add(const Duration(hours: 8));
  final month = manila.month.toString().padLeft(2, '0');
  final day = manila.day.toString().padLeft(2, '0');
  return '${manila.year}-$month-$day';
}

/// Estimated distance in kilometres from a step count.
double walkingDistanceKm(int steps) => steps * 0.000762;

/// Estimated calories burned from a step count.
double walkingCalories(int steps) => steps * 0.04;

/// Estimated active minutes from a step count (~100 steps/minute).
int walkingDurationMin(int steps) => steps ~/ 100;

/// One observed day's step total. `steps` is null for days the app
/// never observed (a gap in history), which the UI renders as no
/// data rather than as a fabricated zero.
class WalkingDayEntry {
  const WalkingDayEntry({required this.dateKey, required this.steps});

  final String dateKey;
  final int? steps;
}

/// Persisted per-day accumulator state. Pure data: [applyCumulative]
/// is a pure function over it, so the restart/reboot/rollover rules
/// are unit-testable without a sensor.
class WalkingDayState {
  const WalkingDayState({
    required this.day,
    required this.todaySteps,
    required this.lastCumulative,
  });

  final String day;
  final int todaySteps;

  /// Last cumulative sensor value seen, or null before the first
  /// event. Persisted so an app restart never re-adds old steps.
  final int? lastCumulative;

  Map<String, dynamic> toJson() => {
        'day': day,
        'todaySteps': todaySteps,
        'lastCumulative': lastCumulative,
      };

  static WalkingDayState fromJson(Map<String, dynamic> json) =>
      WalkingDayState(
        day: json['day'] as String? ?? '',
        todaySteps: (json['todaySteps'] as num?)?.toInt() ?? 0,
        lastCumulative: (json['lastCumulative'] as num?)?.toInt(),
      );
}

/// Applies one cumulative sensor reading to [prev] for [todayKey].
/// Returns the new state; the caller archives [prev] into history
/// when the returned day differs from [prev]'s day.
WalkingDayState applyCumulative(
  WalkingDayState prev,
  int cumulative,
  String todayKey,
) {
  if (prev.day != todayKey) {
    // New day: restart from this reading. Yesterday's total is the
    // caller's to archive; nothing carries over.
    return WalkingDayState(
      day: todayKey,
      todaySteps: 0,
      lastCumulative: cumulative,
    );
  }
  final last = prev.lastCumulative;
  if (last == null) {
    // First event of the day: this reading becomes the baseline;
    // nothing is counted yet (no delta exists to count).
    return WalkingDayState(
      day: prev.day,
      todaySteps: prev.todaySteps,
      lastCumulative: cumulative,
    );
  }
  if (cumulative >= last) {
    return WalkingDayState(
      day: prev.day,
      todaySteps: prev.todaySteps + (cumulative - last),
      lastCumulative: cumulative,
    );
  }
  // Sensor rebooted (cumulative restarted from 0): steps since the
  // reboot count, and the pre-reboot total is kept.
  return WalkingDayState(
    day: prev.day,
    todaySteps: prev.todaySteps + cumulative,
    lastCumulative: cumulative,
  );
}

/// Local storage for walking data. All keys are namespaced; walking
/// data never leaves the device.
class WalkingStore {
  static const goalKey = 'byahetayo_walking_goal';
  static const historyKey = 'byahetayo_walking_history';
  static const stateKey = 'byahetayo_walking_state';

  static const defaultGoal = 8000;

  Future<int> loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(goalKey) ?? defaultGoal;
  }

  Future<void> saveGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(goalKey, goal);
  }

  /// Completed-day totals, newest last. Days the app never observed
  /// are simply absent — never stored as zeros.
  Future<Map<String, int>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(historyKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> saveHistory(Map<String, int> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(historyKey, jsonEncode(history));
  }

  Future<WalkingDayState?> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(stateKey);
    if (raw == null || raw.isEmpty) return null;
    return WalkingDayState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveState(WalkingDayState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(stateKey, jsonEncode(state.toJson()));
  }
}

/// What the Walking Goal UI can show. `ready` means the sensor is
/// available and permission is granted; a zero step count in that
/// state is real data (no steps recorded yet), not an error.
enum WalkingStatus {
  loading,
  ready,
  noSensor,
  permissionRequired,
  permissionDenied,
  error,
}

/// Owns the walking sensor subscription, the daily accumulator, and
/// goal/history persistence. One controller per hub tab: a single
/// accumulator avoids double-counting when both the hub card and the
/// details screen listen at once.
class WalkingController extends ChangeNotifier {
  WalkingController({
    WalkingSensor? sensor,
    ActivityPermission? permission,
    WalkingStore? store,
  })  : _sensor = sensor ?? PlatformWalkingSensor(),
        _permission = permission ?? AppActivityPermission(),
        _store = store ?? WalkingStore();

  final WalkingSensor _sensor;
  final ActivityPermission _permission;
  final WalkingStore _store;

  WalkingStatus _status = WalkingStatus.loading;
  int _goal = WalkingStore.defaultGoal;
  Map<String, int> _history = {};
  WalkingDayState? _state;
  bool _receivedEvent = false;
  bool _initialized = false;
  StreamSubscription<int>? _subscription;

  WalkingStatus get status => _status;
  int get goal => _goal;
  Map<String, int> get history => Map.unmodifiable(_history);

  /// Today's Manila date key, from the device clock.
  String get todayKey => manilaDateKey(DateTime.now());

  int get todaySteps => _state?.todaySteps ?? 0;
  bool get receivedEvent => _receivedEvent;

  /// 0.0–1.0 progress toward today's goal.
  double get todayProgress {
    if (_goal <= 0) return 0;
    return (todaySteps / _goal).clamp(0.0, 1.0);
  }

  double get todayDistanceKm => walkingDistanceKm(todaySteps);
  double get todayCalories => walkingCalories(todaySteps);
  int get todayDurationMin => walkingDurationMin(todaySteps);

  /// Last 7 calendar days ending today (oldest first). Days with no
  /// record carry a null step count — the UI renders those as no
  /// data, never as a fabricated zero.
  List<WalkingDayEntry> get weeklyHistory {
    // Manila wall clock (UTC+8, no DST): subtract calendar days from
    // it directly — never re-shift an already-shifted value.
    final manilaNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final entries = <WalkingDayEntry>[];
    for (var i = 6; i >= 0; i--) {
      final day = manilaNow.subtract(Duration(days: i));
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}'
          '-${day.day.toString().padLeft(2, '0')}';
      if (key == todayKey) {
        entries.add(WalkingDayEntry(dateKey: key, steps: todaySteps));
      } else {
        entries.add(WalkingDayEntry(dateKey: key, steps: _history[key]));
      }
    }
    return entries;
  }

  int get weeklyTotal {
    var total = 0;
    for (final entry in weeklyHistory) {
      total += entry.steps ?? 0;
    }
    return total;
  }

  /// Loads stored data, then starts the sensor when permitted.
  /// Never throws: every failure lands in [_status] for the UI.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _goal = await _store.loadGoal();
      _history = await _store.loadHistory();
      var state = await _store.loadState();
      // A new day starts clean even before the first sensor event,
      // and yesterday's observed total is archived.
      if (state != null && state.day != todayKey) {
        _history = {..._history, state.day: state.todaySteps};
        await _store.saveHistory(_history);
        state = WalkingDayState(
          day: todayKey,
          todaySteps: 0,
          lastCumulative: null,
        );
        await _store.saveState(state);
      }
      _state = state;
      final available = await _sensor.isAvailable;
      if (!available) {
        _status = WalkingStatus.noSensor;
        notifyListeners();
        return;
      }
      final permission = await _permission.status();
      if (permission == ActivityPermissionStatus.granted) {
        _subscribe();
      } else if (permission ==
          ActivityPermissionStatus.permanentlyDenied) {
        _status = WalkingStatus.permissionDenied;
        notifyListeners();
      } else {
        _status = WalkingStatus.permissionRequired;
        notifyListeners();
      }
    } catch (_) {
      _status = WalkingStatus.error;
      notifyListeners();
    }
  }

  /// User-tapped permission request (never auto-fired on load).
  Future<void> requestPermission() async {
    try {
      final result = await _permission.request();
      if (result == ActivityPermissionStatus.granted) {
        _subscribe();
      } else if (result == ActivityPermissionStatus.permanentlyDenied) {
        _status = WalkingStatus.permissionDenied;
        notifyListeners();
      } else {
        _status = WalkingStatus.permissionRequired;
        notifyListeners();
      }
    } catch (_) {
      _status = WalkingStatus.error;
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    try {
      await _permission.openSettings();
    } catch (_) {
      // Nothing to do: the user stays in the app.
    }
  }

  /// Re-reads the permission status without showing a system dialog
  /// (used after the user returns from app settings).
  Future<void> recheckPermission() async {
    try {
      final result = await _permission.status();
      if (result == ActivityPermissionStatus.granted) {
        _subscribe();
      } else if (result == ActivityPermissionStatus.permanentlyDenied) {
        _status = WalkingStatus.permissionDenied;
        notifyListeners();
      } else {
        _status = WalkingStatus.permissionRequired;
        notifyListeners();
      }
    } catch (_) {
      _status = WalkingStatus.error;
      notifyListeners();
    }
  }

  /// Re-runs init after an error (fresh controller state).
  Future<void> retry() async {
    _initialized = false;
    _status = WalkingStatus.loading;
    notifyListeners();
    await init();
  }

  Future<void> setGoal(int goal) async {
    final clamped = goal.clamp(1000, 100000);
    _goal = clamped;
    notifyListeners();
    try {
      await _store.saveGoal(clamped);
    } catch (_) {
      // The in-memory goal still applies for this session; a failed
      // write surfaces nowhere as data, so it is safe to swallow.
    }
  }

  void _subscribe() {
    _status = WalkingStatus.ready;
    notifyListeners();
    _subscription?.cancel();
    _subscription = _sensor.cumulativeSteps.listen(
      _onCumulative,
      onError: (_) {
        _status = WalkingStatus.error;
        notifyListeners();
      },
    );
  }

  Future<void> _onCumulative(int cumulative) async {
    final prev = _state ??
        WalkingDayState(
          day: todayKey,
          todaySteps: 0,
          lastCumulative: null,
        );
    final next = applyCumulative(prev, cumulative, todayKey);
    if (next.day != prev.day) {
      _history = {..._history, prev.day: prev.todaySteps};
      try {
        await _store.saveHistory(_history);
      } catch (_) {
        // History loss is unfortunate but never corrupts today's
        // count; the day state below is still persisted.
      }
    }
    _state = next;
    _receivedEvent = true;
    notifyListeners();
    try {
      await _store.saveState(next);
    } catch (_) {
      // See setGoal: a failed write never fabricates data.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
