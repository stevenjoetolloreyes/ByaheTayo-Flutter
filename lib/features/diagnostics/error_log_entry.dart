// EstudyanteGO — structured error-log entry (ONE logging system).
//
// This file is pure Dart (no Flutter imports) so the entry model,
// redaction, and JSON format can be unit-tested without a device,
// Firebase, or any plugin. It is the single format used by:
//   * the Dart logger (FlutterError + zone + startup stages),
//   * the native MainActivity handler (which writes the same JSON
//     fields from Kotlin), and
//   * the Error Diagnostics screen (view / filter / export).
//
// Privacy rule (enforced by [ErrorLogEntry.redact]): values keyed or
// labelled as passwords, tokens, API keys, secrets, authorisation
// material, or card data are replaced with "[REDACTED]" before the
// entry is stored. Stack traces, file paths, class names, and widget
// names are NOT sensitive and are kept, because without them a crash
// cannot be diagnosed. Nothing in this file performs any network
// upload; logs stay local unless the user explicitly exports them.
import 'dart:convert';
import 'dart:math';

/// Stable category names. These are the values the Diagnostics screen
/// filters on, so they must not be renamed casually.
enum ErrorCategory {
  flutterFramework,
  asyncUnhandled,
  platform,
  firebaseInit,
  pluginInit,
  startup,
  startupTimeout,
  fatalCrash,
  native,
  other,
}

/// Severity, lowest to highest. `fatal` means the process died or the
/// app could not continue; `error` means a feature failed but the app
/// kept running; `warning`/`info` are diagnostic only.
enum ErrorSeverity { info, warning, error, fatal }

/// App version shown on every entry. This mirrors `version:` in
/// pubspec.yaml. There is deliberately NO package_info_plus dependency
/// in this change: adding one is an open decision for the parent (see
/// REPORT.md). Until then this constant must be bumped together with
/// pubspec.yaml, and the value is honest about its source.
const String kDiagnosticsAppVersion = '3.5.1';
const String kDiagnosticsAppBuildNumber = '2';

/// One structured log entry. All fields are JSON-safe.
class ErrorLogEntry {
  ErrorLogEntry({
    required this.id,
    required this.timestampUtc,
    required this.category,
    required this.message,
    this.stackTrace,
    this.startupStage,
    this.appVersion = kDiagnosticsAppVersion,
    this.buildNumber = kDiagnosticsAppBuildNumber,
    this.androidVersion = 'unknown',
    this.deviceModel = 'unknown',
    this.severity = ErrorSeverity.error,
  });

  final String id;
  final String timestampUtc;
  final ErrorCategory category;
  final String message;
  final String? stackTrace;
  final String? startupStage;
  final String appVersion;
  final String buildNumber;
  final String androidVersion;
  final String deviceModel;
  final ErrorSeverity severity;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'timestampUtc': timestampUtc,
      'category': category.name,
      'message': message,
      'stackTrace': stackTrace,
      'startupStage': startupStage,
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'androidVersion': androidVersion,
      'deviceModel': deviceModel,
      'severity': severity.name,
    };
  }

  factory ErrorLogEntry.fromJson(Map<String, dynamic> json) {
    ErrorCategory categoryFrom(String? name) {
      for (final value in ErrorCategory.values) {
        if (value.name == name) return value;
      }
      return ErrorCategory.other;
    }

    ErrorSeverity severityFrom(String? name) {
      for (final value in ErrorSeverity.values) {
        if (value.name == name) return value;
      }
      return ErrorSeverity.error;
    }

    return ErrorLogEntry(
      id: json['id'] as String? ?? '',
      timestampUtc: json['timestampUtc'] as String? ?? '',
      category: categoryFrom(json['category'] as String?),
      message: json['message'] as String? ?? '',
      stackTrace: json['stackTrace'] as String?,
      startupStage: json['startupStage'] as String?,
      appVersion: json['appVersion'] as String? ?? kDiagnosticsAppVersion,
      buildNumber: json['buildNumber'] as String? ?? kDiagnosticsAppBuildNumber,
      androidVersion: json['androidVersion'] as String? ?? 'unknown',
      deviceModel: json['deviceModel'] as String? ?? 'unknown',
      severity: severityFrom(json['severity'] as String?),
    );
  }

  String toJsonLine() => jsonEncode(toJson());

  // -----------------------------------------------------------------
  // Redaction. Applied to message AND stack trace, before storage.
  // -----------------------------------------------------------------

  /// Key names whose values must never be stored. Matching is
  /// case-insensitive and substring-based on purpose: a key such as
  /// `authToken`, `api_key`, or `userPassword` must all match.
  static const List<String> _sensitiveKeys = <String>[
    'password',
    'passwd',
    'pwd',
    'token',
    'api_key',
    'apikey',
    'api-key',
    'secret',
    'authorization',
    'auth_token',
    'id_token',
    'refresh_token',
    'access_token',
    'session_key',
    'private_key',
    'client_secret',
    'card_number',
    'cardnumber',
    'cvv',
    'pin_code',
  ];

  static final RegExp _keyValuePattern = RegExp(
    r'''(['"]?)(password|passwd|pwd|token|api[_-]?key|secret|authorization|auth[_-]?token|id[_-]?token|refresh[_-]?token|access[_-]?token|session[_-]?key|private[_-]?key|client[_-]?secret|card[_-]?number|cvv)\1\s*[:=]\s*['"]?[^\s,'"}\]]+['"]?''',
    caseSensitive: false,
  );

  static final RegExp _bearerPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9._\-]+',
    caseSensitive: false,
  );

  /// Returns [text] with sensitive values replaced by `[REDACTED]`.
  /// Non-sensitive content (stack frames, file paths, class and widget
  /// names, error types) is preserved untouched.
  static String redact(String text) {
    var out = text;
    out = out.replaceAllMapped(_keyValuePattern, (match) {
      final key = match.group(2) ?? 'value';
      return '$key: [REDACTED]';
    });
    out = out.replaceAll(_bearerPattern, 'Bearer [REDACTED]');
    // A bare key on its own line followed by a value on the next line
    // (common in pretty-printed maps) is also scrubbed — but ONLY
    // that two-line shape. An earlier form of this loop matched any
    // line starting with a sensitive key and wiped the rest of the
    // line, destroying stack paths on the same line; it is fixed
    // here to require the value to be on the following line.
    for (final key in _sensitiveKeys) {
      final pattern = RegExp(
        '^(\\s*$key\\s*[:=]\\s*)\n\\s*[^\\s]+',
        caseSensitive: false,
        multiLine: true,
      );
      out = out.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    return out;
  }

  /// A redacted copy of this entry (id/timestamp/category/severity and
  /// all non-sensitive fields unchanged).
  ErrorLogEntry redacted() {
    return ErrorLogEntry(
      id: id,
      timestampUtc: timestampUtc,
      category: category,
      message: redact(message),
      stackTrace: stackTrace == null ? null : redact(stackTrace!),
      startupStage: startupStage,
      appVersion: appVersion,
      buildNumber: buildNumber,
      androidVersion: androidVersion,
      deviceModel: deviceModel,
      severity: severity,
    );
  }
}

/// Default ID generator. Injectable in tests via [ErrorLogService]
///-style factories; production code uses this one. It needs no
/// dependency: timestamp + randomness is unique enough for a local
/// diagnostic log (collisions would only merge two local entries).
String defaultEntryId() {
  final random = Random.secure();
  final suffix = List<int>.generate(
    8,
    (_) => random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
}

String utcNowIso() => DateTime.now().toUtc().toIso8601String();
