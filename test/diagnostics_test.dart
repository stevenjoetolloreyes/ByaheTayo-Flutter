// EstudyanteGO diagnostics tests — fakes only, no network, no real
// Firebase. Covers the spec's test list: prefs failure, Firebase
// failure, timeout, Safe Mode, 500-entry cap, redaction, export
// format, and clear-with-confirmation.
//
// Run (file-by-file, per repo convention): flutter test
// test/diagnostics_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/diagnostics/error_log_entry.dart';
import '../lib/features/diagnostics/error_log_store.dart';
import '../lib/features/diagnostics/startup_diagnostics.dart';

ErrorLogEntry sampleEntry(String id, {String message = 'boom'}) {
  return ErrorLogEntry(
    id: id,
    timestampUtc: '2026-11-04T00:00:00.000Z',
    category: ErrorCategory.startup,
    message: message,
    stackTrace: '#0 main (main.dart:1:1)',
    startupStage: StartupStage.firebase.name,
    appVersion: '1.0.0',
    buildNumber: '1',
    androidVersion: 'Android 14',
    deviceModel: 'Pixel 8',
    severity: ErrorSeverity.error,
  );
}

/// A fresh diagnostics pair: the store the test asserts on, and the
/// diagnostics object wired to that same store.
class DiagnosticsHarness {
  DiagnosticsHarness({bool safeMode = false})
    : store = ErrorLogStore(storage: InMemoryErrorLogStorage()),
      _safeMode = safeMode;

  final ErrorLogStore store;
  final bool _safeMode;
  late final StartupDiagnostics diagnostics;

  Future<void> init() async {
    await store.load();
    diagnostics = StartupDiagnostics(store: store, safeMode: _safeMode);
  }
}

Future<DiagnosticsHarness> freshDiagnostics({bool safeMode = false}) async {
  final harness = DiagnosticsHarness(safeMode: safeMode);
  await harness.init();
  return harness;
}

void main() {
  test('entry JSON round-trip preserves every required field', () {
    final entry = sampleEntry('id-1');
    final decoded = ErrorLogEntry.fromJson(
      jsonDecode(entry.toJsonLine()) as Map<String, dynamic>,
    );
    expect(decoded.id, 'id-1');
    expect(decoded.timestampUtc, '2026-11-04T00:00:00.000Z');
    expect(decoded.category, ErrorCategory.startup);
    expect(decoded.message, 'boom');
    expect(decoded.stackTrace, '#0 main (main.dart:1:1)');
    expect(decoded.startupStage, 'firebase');
    expect(decoded.appVersion, '1.0.0');
    expect(decoded.buildNumber, '1');
    expect(decoded.androidVersion, 'Android 14');
    expect(decoded.deviceModel, 'Pixel 8');
    expect(decoded.severity, ErrorSeverity.error);
  });

  test('redaction strips passwords, tokens and API keys but keeps paths', () {
    const dirty =
        'login failed password=hunter2 token=abc123 api_key=XYZ '
        'Bearer bearer-secret-here at lib/main.dart:42 in _resolveStart';
    final clean = ErrorLogEntry.redact(dirty);
    expect(clean, isNot(contains('hunter2')));
    expect(clean, isNot(contains('abc123')));
    expect(clean, isNot(contains('XYZ')));
    expect(clean, isNot(contains('bearer-secret-here')));
    expect(clean, contains('[REDACTED]'));
    // Stack frames, file paths and class/function names are kept.
    expect(clean, contains('lib/main.dart:42'));
    expect(clean, contains('_resolveStart'));
  });

  test('store redacts on add, not only in the export', () async {
    final store = ErrorLogStore(storage: InMemoryErrorLogStorage());
    await store.add(
      sampleEntry('id-secret', message: 'failed with password=hunter2'),
    );
    expect(store.entries.single.message, isNot(contains('hunter2')));
    expect(store.entries.single.message, contains('[REDACTED]'));
  });

  test('500-entry cap keeps the newest 500 and trims the oldest', () async {
    final store = ErrorLogStore(storage: InMemoryErrorLogStorage());
    for (var i = 0; i < 505; i++) {
      await store.add(sampleEntry('id-$i'));
    }
    expect(store.entries.length, 500);
    expect(store.entries.first.id, 'id-5');
    expect(store.entries.last.id, 'id-504');
    // Newest-first view still ends with the newest entry.
    expect(store.newestFirst.first.id, 'id-504');
  });

  test('clear only when confirmed', () async {
    final store = ErrorLogStore(storage: InMemoryErrorLogStorage());
    await store.add(sampleEntry('id-1'));
    expect(await store.confirmAndClear(confirmed: false), isFalse);
    expect(store.entries.length, 1);
    expect(await store.confirmAndClear(confirmed: true), isTrue);
    expect(store.entries, isEmpty);
  });

  test('export TXT and JSON are parseable and complete', () async {
    final store = ErrorLogStore(storage: InMemoryErrorLogStorage());
    await store.add(sampleEntry('id-1', message: 'first failure'));
    await store.add(sampleEntry('id-2', message: 'second failure'));
    final txt = store.exportTxt();
    expect(txt, contains('EstudyanteGO error log export'));
    expect(txt, contains('Entries: 2'));
    expect(txt, contains('first failure'));
    expect(txt, contains('second failure'));
    final json = jsonDecode(store.exportJson()) as List<dynamic>;
    expect(json.length, 2);
    expect((json.first as Map<String, dynamic>)['id'], 'id-2'); // newest first
    expect((json.first as Map<String, dynamic>)['appVersion'], '1.0.0');
  });

  test('filter by category, severity and search query', () async {
    final store = ErrorLogStore(storage: InMemoryErrorLogStorage());
    await store.add(sampleEntry('id-1', message: 'firebase boom'));
    await store.add(
      ErrorLogEntry(
        id: 'id-2',
        timestampUtc: '2026-11-04T00:01:00.000Z',
        category: ErrorCategory.flutterFramework,
        message: 'widget overflow',
        severity: ErrorSeverity.warning,
      ),
    );
    expect(store.filter(category: ErrorCategory.startup).length, 1);
    expect(store.filter(severity: ErrorSeverity.warning).length, 1);
    expect(store.filter(query: 'overflow').length, 1);
    expect(store.filter(query: 'no-such-text'), isEmpty);
  });

  test('prefs failure returns fallback and records the failure', () async {
    final harness = await freshDiagnostics();
    final diagnostics = harness.diagnostics;
    final store = harness.store;
    final result = await diagnostics.runStage<String?>(
      StartupStage.sharedPreferences,
      () => throw StateError('prefs unavailable'),
      fallback: null,
      timeout: const Duration(seconds: 5),
    );
    expect(result, isNull);
    final failures = store.filter(
      category: ErrorCategory.startup,
      severity: ErrorSeverity.error,
    );
    expect(
      failures.any((e) => e.message.contains('sharedPreferences')),
      isTrue,
    );
  });

  test('Firebase failure returns fallback and records the failure', () async {
    final harness = await freshDiagnostics();
    final diagnostics = harness.diagnostics;
    final store = harness.store;
    final result = await diagnostics.runStage<bool>(
      StartupStage.firebase,
      () => throw Exception('Firebase init exploded'),
      fallback: false,
      timeout: const Duration(seconds: 5),
    );
    expect(result, isFalse);
    expect(store.entries.any((e) => e.message.contains('firebase')), isTrue);
  });

  test('timeout returns fallback and records a startupTimeout entry', () async {
    final harness = await freshDiagnostics();
    final diagnostics = harness.diagnostics;
    final store = harness.store;
    final result = await diagnostics.runStage<String>(
      StartupStage.profileRestore,
      () => Completer<String>().future, // never completes; timeout must win
      fallback: 'fallback-profile',
      timeout: const Duration(milliseconds: 50),
    );
    expect(result, 'fallback-profile');
    expect(
      store.entries.any((e) => e.category == ErrorCategory.startupTimeout),
      isTrue,
    );
  });

  test('Safe Mode skips appCheck but never skips essential stages', () async {
    final harness = await freshDiagnostics(safeMode: true);
    final diagnostics = harness.diagnostics;
    expect(diagnostics.shouldSkip(StartupStage.appCheck), isTrue);
    for (final stage in <StartupStage>[
      StartupStage.flutterBinding,
      StartupStage.sharedPreferences,
      StartupStage.firebase,
      StartupStage.authSessionRestore,
      StartupStage.profileRestore,
      StartupStage.splash,
      StartupStage.dashboardInit,
    ]) {
      expect(diagnostics.shouldSkip(stage), isFalse, reason: stage.name);
    }
    // A skipped stage returns the fallback and is recorded.
    final store = harness.store;
    final result = await diagnostics.runStage<bool>(
      StartupStage.appCheck,
      () => throw Exception('must not run'),
      fallback: false,
    );
    expect(result, isFalse);
    expect(
      store.entries.any((e) => e.message.contains('skipped (Safe Mode)')),
      isTrue,
    );
  });

  test('successful stage returns work value and records completion', () async {
    final harness = await freshDiagnostics();
    final diagnostics = harness.diagnostics;
    final store = harness.store;
    final result = await diagnostics.runStage<int>(
      StartupStage.dashboardInit,
      () async => 42,
      fallback: 0,
    );
    expect(result, 42);
    expect(
      store.entries.any((e) => e.message.contains('completed: dashboardInit')),
      isTrue,
    );
  });
}
