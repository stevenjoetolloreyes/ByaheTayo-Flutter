// EstudyanteGO — local error-log storage (ONE logging system).
//
// Storage is local only. There is no network code in this file and
// no automatic upload anywhere in the diagnostics system. Export
// happens only when the Diagnostics screen asks for it after the user
// confirms, and it writes a file the user can inspect first.
//
// Two files, one system:
//   * Primary store: a JSON-lines file in the app documents directory
//     (`error_logs.jsonl`, one [ErrorLogEntry] JSON object per line).
//     The Diagnostics screen reads this file.
//   * External mirror (optional, Android only): the same JSON lines
//     appended to `<external files dir>/estudyantego-crash.log`, so a
//     crash log can be opened in a File Manager without logcat. This
//     replaces the plain-text format of the earlier file-logger
//     diagnostic; it does NOT run a second logger beside this one —
//     the native MainActivity handler writes the same JSON fields to
//     the same mirror file, and the Dart side never writes plain text.
//   * The 500-entry cap is enforced on every add: the oldest entries
//     are trimmed, the newest are always kept.
import 'dart:convert';
import 'dart:io';

import 'error_log_entry.dart';

/// Hard cap required by the spec. Enforced in [ErrorLogStore.add],
/// never silently raised.
const int kMaxLogEntries = 500;

/// Storage backend abstraction. Production uses [FileErrorLogStorage];
/// tests use [InMemoryErrorLogStorage]. No backend ever touches the
/// network.
abstract class ErrorLogStorage {
  Future<List<Map<String, dynamic>>> loadJsonEntries();
  Future<void> saveJsonEntries(List<Map<String, dynamic>> entries);
}

/// JSON-lines file storage. Corrupt lines are skipped (never fatal),
/// so one bad line cannot destroy the whole log.
class FileErrorLogStorage implements ErrorLogStorage {
  FileErrorLogStorage(this.file);

  final File file;

  @override
  Future<List<Map<String, dynamic>>> loadJsonEntries() async {
    try {
      if (!await file.exists()) return <Map<String, dynamic>>[];
      final lines = await file.readAsLines();
      final entries = <Map<String, dynamic>>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) entries.add(decoded);
        } catch (_) {
          // Skip corrupt lines; keep the rest of the log.
          continue;
        }
      }
      return entries;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  @override
  Future<void> saveJsonEntries(List<Map<String, dynamic>> entries) async {
    try {
      await file.parent.create(recursive: true);
      final buffer = StringBuffer();
      for (final entry in entries) {
        buffer.writeln(jsonEncode(entry));
      }
      await file.writeAsString(buffer.toString());
    } catch (_) {
      // Storage failure must never crash the app.
    }
  }
}

/// In-memory storage for tests and for pre-init buffering.
class InMemoryErrorLogStorage implements ErrorLogStorage {
  List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> loadJsonEntries() async {
    return List<Map<String, dynamic>>.from(_entries);
  }

  @override
  Future<void> saveJsonEntries(List<Map<String, dynamic>> entries) async {
    _entries = List<Map<String, dynamic>>.from(entries);
  }
}

/// The store. All entries pass through [add], which redacts first,
/// then trims to [kMaxLogEntries]. [clear] is only ever called from
/// the Diagnostics screen after a confirmation dialog; the pure
/// [confirmAndClear] helper makes that rule testable.
class ErrorLogStore {
  ErrorLogStore({required ErrorLogStorage storage, File? externalMirrorFile})
    : _storage = storage,
      _externalMirrorFile = externalMirrorFile;

  final ErrorLogStorage _storage;
  final File? _externalMirrorFile;
  List<ErrorLogEntry> _entries = <ErrorLogEntry>[];
  bool _loaded = false;

  List<ErrorLogEntry> get entries => List<ErrorLogEntry>.unmodifiable(_entries);

  /// Newest first, for the Diagnostics screen list.
  List<ErrorLogEntry> get newestFirst =>
      List<ErrorLogEntry>.unmodifiable(_entries.reversed);

  Future<void> load() async {
    final raw = await _storage.loadJsonEntries();
    _entries = raw.map(ErrorLogEntry.fromJson).toList();
    if (_entries.length > kMaxLogEntries) {
      _entries = _entries.sublist(_entries.length - kMaxLogEntries);
    }
    _loaded = true;
  }

  /// Adds [entry] (redacted, then trimmed to the cap). When
  /// [mirror] is false the external mirror write is skipped — used
  /// by [ErrorLogService.recordSync], which already mirrored
  /// synchronously, so the mirror never receives a duplicate line.
  Future<void> add(ErrorLogEntry entry, {bool mirror = true}) async {
    if (!_loaded) await load();
    final safe = entry.redacted();
    _entries.add(safe);
    if (_entries.length > kMaxLogEntries) {
      _entries = _entries.sublist(_entries.length - kMaxLogEntries);
    }
    await _persist();
    if (mirror) await _mirror(safe);
  }

  Future<void> _persist() async {
    try {
      await _storage.saveJsonEntries(_entries.map((e) => e.toJson()).toList());
    } catch (_) {
      // Storage failure must never crash the app.
    }
  }

  Future<void> _mirror(ErrorLogEntry entry) async {
    final mirror = _externalMirrorFile;
    if (mirror == null) return;
    try {
      await mirror.parent.create(recursive: true);
      await mirror.writeAsString(
        '${entry.toJsonLine()}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Mirror failure must never crash the app.
    }
  }

  /// Synchronous mirror write, for use inside FlutterError/zone
  /// handlers where the process may die before an async write flushes.
  /// Best-effort only; never throws.
  void mirrorSync(ErrorLogEntry entry) {
    final mirror = _externalMirrorFile;
    if (mirror == null) return;
    try {
      mirror.parent.createSync(recursive: true);
      mirror.writeAsStringSync(
        '${entry.redacted().toJsonLine()}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Never throw from the logger.
    }
  }

  /// Clears only when [confirmed] is true. The Diagnostics screen
  /// passes true only after the user taps confirm in its dialog.
  /// Returns true when the log was actually cleared.
  Future<bool> confirmAndClear({required bool confirmed}) async {
    if (!confirmed) return false;
    _entries = <ErrorLogEntry>[];
    await _persist();
    return true;
  }

  Future<void> clear() => confirmAndClear(confirmed: true);

  List<ErrorLogEntry> filter({
    ErrorCategory? category,
    ErrorSeverity? severity,
    String? query,
  }) {
    final needle = (query ?? '').trim().toLowerCase();
    return newestFirst.where((entry) {
      if (category != null && entry.category != category) return false;
      if (severity != null && entry.severity != severity) return false;
      if (needle.isNotEmpty) {
        final haystack = '${entry.message} ${entry.stackTrace ?? ''}'
            .toLowerCase();
        if (!haystack.contains(needle)) return false;
      }
      return true;
    }).toList();
  }

  /// Human-readable export. The caller writes/shares it only after
  /// user confirmation (see the Diagnostics screen).
  String exportTxt() {
    final buffer = StringBuffer();
    buffer.writeln('EstudyanteGO error log export');
    buffer.writeln('Entries: ${_entries.length}');
    buffer.writeln('Exported: ${utcNowIso()}');
    buffer.writeln('---');
    for (final entry in newestFirst) {
      buffer.writeln(
        '[${entry.timestampUtc}] '
        '${entry.severity.name.toUpperCase()} '
        '${entry.category.name}'
        '${entry.startupStage == null ? '' : ' stage=${entry.startupStage}'} '
        'id=${entry.id}',
      );
      buffer.writeln('  ${entry.message}');
      if (entry.stackTrace != null && entry.stackTrace!.isNotEmpty) {
        buffer.writeln('  Stack:');
        for (final line in entry.stackTrace!.split('\n')) {
          buffer.writeln('    $line');
        }
      }
      buffer.writeln(
        '  App ${entry.appVersion}+${entry.buildNumber} | '
        'Android ${entry.androidVersion} | Device ${entry.deviceModel}',
      );
      buffer.writeln('---');
    }
    return buffer.toString();
  }

  /// Machine-readable export: a JSON array of entry objects.
  String exportJson() {
    return const JsonEncoder.withIndent('  ')
        .convert(newestFirst.map((e) => e.toJson()).toList());
  }
}
