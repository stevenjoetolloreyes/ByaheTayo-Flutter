// EstudyanteGO — startup diagnostics + crash protection.
//
// One stage recorder, used by main() and the splash/gate code. Every
// startup stage gets a start/end record in the same error-log store,
// so a failed or timed-out stage is visible in the Diagnostics screen
// instead of silently freezing or crashing the app.
//
// Startup crash protection rules implemented here:
//   * A recoverable stage failure NEVER throws out of startup: the
//     caller supplies a fallback value and [runStage] returns it.
//   * A stage that exceeds its timeout is recorded as a
//     [ErrorCategory.startupTimeout] entry and the fallback is used.
//     (Dart cannot cancel the underlying future; the timeout only
//     stops startup from waiting on it. The late result is ignored.)
//   * Safe Mode skips ONLY the nonessential services listed in
//     [nonessentialStages]. It never skips auth session restore,
//     profile restore, onboarding progress, or prefs, and it never
//     clears prefs/session.
//   * Fatal errors are recorded, never silently hidden: a stage
//     failure always produces a log entry, even when a fallback lets
//     the app continue.
import 'dart:async';

import 'error_log_entry.dart';
import 'error_log_store.dart';

/// Startup stages, in the order they run on a cold launch. The names
/// are stable strings in log entries and in the Diagnostics screen.
enum StartupStage {
  flutterBinding,
  sharedPreferences,
  firebase,
  appCheck,
  splash,
  authSessionRestore,
  profileRestore,
  dashboardInit,
}

/// Services Safe Mode is allowed to skip. Rationale for each:
///   * appCheck — already best-effort inside firebase_init; skipping
///     it only defers attestation, it does not block auth or data.
///   * adsInit — ads are nonessential and the home shell already
///     initialises them without awaiting; skipping them cannot block
///     any tab.
///   * notificationPrompt — a one-time permission prompt; skipping it
///     only defers the prompt, it does not block the dashboard.
///   * aiServices — AI quiz generation is not part of launch; skipping
///     it only disables the generate screen until a retry.
/// Essential stages (never skipped): flutterBinding,
/// sharedPreferences, firebase core init, authSessionRestore,
/// profileRestore, splash, dashboardInit, onboarding progress.
const Set<String> nonessentialStages = <String>{
  'appCheck',
  'adsInit',
  'notificationPrompt',
  'aiServices',
};

/// One stage timing record, stored as a log entry (severity info on
/// success, error on failure/timeout) so stages and errors live in
/// the same list the Diagnostics screen shows.
class StartupDiagnostics {
  StartupDiagnostics({
    required ErrorLogStore store,
    this.safeMode = false,
    this.androidVersion = 'unknown',
    this.deviceModel = 'unknown',
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _store = store,
       _idGenerator = idGenerator ?? defaultEntryId,
       _clock = clock ?? DateTime.now;

  final ErrorLogStore _store;
  bool safeMode;
  final String androidVersion;
  final String deviceModel;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  final Map<StartupStage, DateTime> _started = <StartupStage, DateTime>{};

  /// Whether [stage] must be skipped in Safe Mode. Returns false for
  /// every essential stage, always.
  bool shouldSkip(StartupStage stage) {
    if (!safeMode) return false;
    return nonessentialStages.contains(stage.name);
  }

  Future<void> startStage(StartupStage stage) async {
    _started[stage] = _clock();
    await _store.add(
      ErrorLogEntry(
        id: _idGenerator(),
        timestampUtc: _clock().toUtc().toIso8601String(),
        category: ErrorCategory.startup,
        message: 'Startup stage started: ${stage.name}',
        startupStage: stage.name,
        androidVersion: androidVersion,
        deviceModel: deviceModel,
        severity: ErrorSeverity.info,
      ),
    );
  }

  Future<void> endStage(
    StartupStage stage, {
    bool success = true,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    await _store.add(
      ErrorLogEntry(
        id: _idGenerator(),
        timestampUtc: _clock().toUtc().toIso8601String(),
        category: success
            ? ErrorCategory.startup
            : ErrorCategory.startupTimeout,
        message: success
            ? 'Startup stage completed: ${stage.name}'
            : 'Startup stage failed: ${stage.name}: ${error ?? 'unknown error'}',
        stackTrace: stackTrace?.toString(),
        startupStage: stage.name,
        androidVersion: androidVersion,
        deviceModel: deviceModel,
        severity: success ? ErrorSeverity.info : ErrorSeverity.error,
      ),
    );
    _started.remove(stage);
  }

  /// Runs [work] for [stage] with a timeout and a fallback. On
  /// success the stage is recorded as completed and [work]'s value
  /// is returned. On error or timeout the failure is recorded (never
  /// hidden) and [fallback] is returned instead of throwing.
  /// If Safe Mode skips this stage, [fallback] is returned
  /// immediately and a skipped record is written.
  Future<T> runStage<T>(
    StartupStage stage,
    Future<T> Function() work, {
    required T fallback,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (shouldSkip(stage)) {
      await _store.add(
        ErrorLogEntry(
          id: _idGenerator(),
          timestampUtc: _clock().toUtc().toIso8601String(),
          category: ErrorCategory.startup,
          message: 'Startup stage skipped (Safe Mode): ${stage.name}',
          startupStage: stage.name,
          androidVersion: androidVersion,
          deviceModel: deviceModel,
          severity: ErrorSeverity.warning,
        ),
      );
      return fallback;
    }
    await startStage(stage);
    try {
      final value = await work().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            'Startup stage timed out after ${timeout.inSeconds}s',
            timeout,
          );
        },
      );
      await endStage(stage, success: true);
      return value;
    } on TimeoutException catch (error, stack) {
      await _store.add(
        ErrorLogEntry(
          id: _idGenerator(),
          timestampUtc: _clock().toUtc().toIso8601String(),
          category: ErrorCategory.startupTimeout,
          message: 'Startup stage timed out: ${stage.name}: $error',
          stackTrace: stack.toString(),
          startupStage: stage.name,
          androidVersion: androidVersion,
          deviceModel: deviceModel,
          severity: ErrorSeverity.error,
        ),
      );
      // The timeout entry above is the stage's end record; do not
      // write a second failure entry for the same stage.
      _started.remove(stage);
      return fallback;
    } catch (error, stack) {
      await _store.add(
        ErrorLogEntry(
          id: _idGenerator(),
          timestampUtc: _clock().toUtc().toIso8601String(),
          category: ErrorCategory.startup,
          message: 'Startup stage failed: ${stage.name}: $error',
          stackTrace: stack.toString(),
          startupStage: stage.name,
          androidVersion: androidVersion,
          deviceModel: deviceModel,
          severity: ErrorSeverity.error,
        ),
      );
      // The failure entry above is the stage's end record; do not
      // write a second failure entry for the same stage.
      _started.remove(stage);
      return fallback;
    }
  }
}
