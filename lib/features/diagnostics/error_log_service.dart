// EstudyanteGO — error-log service (ONE logging system).
//
// The singleton the app shell uses. It owns one [ErrorLogStore] and
// one [StartupDiagnostics] instance, installs the Flutter/zone error
// handlers, and is the only object the Diagnostics screen talks to.
//
// Pre-init buffering: [record] works even before [init] (e.g. a
// stage that runs before storage is ready) by buffering in memory
// (capped at 100) and flushing into the store on [init]. Nothing is
// lost and nothing throws before storage exists.
//
// No network code lives here. No automatic upload exists anywhere in
// the diagnostics system. Export is a screen action that happens only
// after the user confirms.
//
// Device info honesty: Android version comes from
// [Platform.operatingSystemVersion] (no new dependency). Device
// model is NOT available without device_info_plus, which is NOT
// added by this change (open decision, see REPORT.md); the field
// therefore reads 'unknown' on the Dart side. The native
// MainActivity handler fills Build.MODEL for its own entries, so
// native entries do carry a model.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'error_log_entry.dart';
import 'error_log_store.dart';
import 'startup_diagnostics.dart';

/// Global access point. Prefer passing the instance explicitly in
/// tests; production code uses [ErrorLogService.instance].
class ErrorLogService {
  ErrorLogService._();

  static final ErrorLogService instance = ErrorLogService._();

  ErrorLogStore? _store;
  StartupDiagnostics? _diagnostics;
  final List<ErrorLogEntry> _preInitBuffer = <ErrorLogEntry>[];
  String _androidVersion = 'unknown';

  /// Called by the app shell to retry the staged initialisation
  /// (prefs + Firebase). Set by main(); the Diagnostics screen's
  /// Retry button invokes it. It never restarts the app and never
  /// clears session/onboarding state — it only re-runs the safe,
  /// re-runnable stages and records the outcome.
  Future<void> Function()? onRetryRequested;

  bool get isInitialized => _store != null;
  ErrorLogStore? get store => _store;
  StartupDiagnostics? get diagnostics => _diagnostics;

  /// Whether Safe Mode is on (skips only nonessential stages).
  bool get safeMode => _diagnostics?.safeMode ?? false;

  set safeMode(bool value) {
    if (_diagnostics != null) _diagnostics!.safeMode = value;
  }

  String get androidVersion => _androidVersion;

  /// Initialise with a ready store. Call once from main(), after
  /// WidgetsFlutterBinding.ensureInitialized(). Never throws.
  Future<void> init({
    required ErrorLogStore store,
    String? androidVersionOverride,
  }) async {
    try {
      _androidVersion =
          androidVersionOverride ??
          (() {
            try {
              return Platform.operatingSystemVersion;
            } catch (_) {
              return 'unknown';
            }
          })();
      _store = store;
      await store.load();
      _diagnostics = StartupDiagnostics(
        store: store,
        androidVersion: _androidVersion,
      );
      for (final entry in _preInitBuffer) {
        await store.add(entry);
      }
      _preInitBuffer.clear();
    } catch (_) {
      // Diagnostics must never break startup.
    }
  }

  /// For tests: install an in-memory store without file IO.
  Future<void> initForTest({ErrorLogStore? store}) async {
    _store = store ?? ErrorLogStore(storage: InMemoryErrorLogStorage());
    await _store!.load();
    _diagnostics = StartupDiagnostics(store: _store!);
    for (final entry in _preInitBuffer) {
      await _store!.add(entry);
    }
    _preInitBuffer.clear();
  }

  Future<void> record({
    required ErrorCategory category,
    required String message,
    String? stackTrace,
    String? startupStage,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    final entry = ErrorLogEntry(
      id: defaultEntryId(),
      timestampUtc: utcNowIso(),
      category: category,
      message: message,
      stackTrace: stackTrace,
      startupStage: startupStage,
      androidVersion: _androidVersion,
      severity: severity,
    );
    final store = _store;
    if (store == null) {
      if (_preInitBuffer.length < 100) _preInitBuffer.add(entry);
      return;
    }
    await store.add(entry);
  }

  /// Synchronous record for FlutterError/zone handlers: writes the
  /// entry to the external mirror immediately (the primary store
  /// write is async and may not flush before a fatal process death).
  /// Never throws.
  void recordSync({
    required ErrorCategory category,
    required String message,
    String? stackTrace,
    String? startupStage,
    ErrorSeverity severity = ErrorSeverity.error,
  }) {
    final entry = ErrorLogEntry(
      id: defaultEntryId(),
      timestampUtc: utcNowIso(),
      category: category,
      message: message,
      stackTrace: stackTrace,
      startupStage: startupStage,
      androidVersion: _androidVersion,
      severity: severity,
    );
    try {
      _store?.mirrorSync(entry);
    } catch (_) {
      // Never throw from the logger.
    }
    // The async store write is best-effort; do not await it here.
    // mirror:false because the entry was already mirrored above.
    final store = _store;
    if (store != null) {
      unawaited(store.add(entry, mirror: false));
    } else if (_preInitBuffer.length < 100) {
      _preInitBuffer.add(entry);
    }
  }

  /// Installs the Flutter framework error handler. Preserves the
  /// default behaviour (presentError) after recording.
  void installFlutterErrorHandler() {
    FlutterError.onError = (FlutterErrorDetails details) {
      recordSync(
        category: ErrorCategory.flutterFramework,
        message: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
        severity: ErrorSeverity.error,
      );
      FlutterError.presentError(details);
    };
  }

  /// Zone error handler for runZonedGuarded around runApp.
  void handleZoneError(Object error, StackTrace stack) {
    recordSync(
      category: ErrorCategory.asyncUnhandled,
      message: error.toString(),
      stackTrace: stack.toString(),
      severity: ErrorSeverity.error,
    );
  }

  /// Platform/plugin error helper for call sites that catch a
  /// PlatformException or a plugin failure and want it recorded
  /// (never rethrown by this helper).
  Future<void> recordPlatformError(Object error, {String? startupStage}) async {
    await record(
      category: ErrorCategory.platform,
      message: error.toString(),
      startupStage: startupStage,
      severity: ErrorSeverity.error,
    );
  }

  Future<void> retryInitialization() async {
    final retry = onRetryRequested;
    if (retry == null) {
      await record(
        category: ErrorCategory.startup,
        message:
            'Retry Initialization requested but no retry handler '
            'is wired in the app shell.',
        severity: ErrorSeverity.warning,
      );
      return;
    }
    await retry();
  }
}
