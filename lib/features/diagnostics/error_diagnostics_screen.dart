// EstudyanteGO — Error Diagnostics screen (Admin/Developer only).
//
// GATING (open decision, see REPORT.md): there is NO existing
// admin/developer gate in the repo, and this change deliberately does
// NOT invent a new auth role. The screen is therefore NOT wired into
// any navigation, tab, or route in this change — all six bottom tabs
// and all existing navigation are untouched. [kDiagnosticsScreenEnabled]
// is OFF by default. The app shell may wire [ErrorDiagnosticsScreen]
// (via [diagnosticsRoute]) behind whatever developer gate the project
// later approves; until then the screen is unreachable in the app,
// even though its code ships and its logic is tested. Do NOT flip
// this flag on without that gate decision.
//
// Features: latest errors (newest first), filter by category and
// severity, search messages, full stack trace detail, copy details,
// export TXT or JSON (confirmation dialog first, then a share sheet
// for a file the user can inspect), clear with confirmation, Retry
// Initialization button, Safe Mode switch (skips ONLY nonessential
// services, listed on the screen). No automatic upload exists.
import 'dart:io';
import '../top_popup.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ios_components.dart';
import 'error_log_entry.dart';
import 'error_log_service.dart';
import 'error_log_store.dart';

/// Developer gate flag. OFF by default (see header). The parent must
/// decide the real gate before wiring this screen anywhere.
const bool kDiagnosticsScreenEnabled = false;

/// Route helper for the app shell, to use ONLY behind an approved
/// developer gate. Returns null when the flag is off, so an
/// accidental wiring cannot expose the screen.
Route<void>? diagnosticsRoute({
  ErrorLogService? service,
  VoidCallback? onRetryInitialization,
  ValueChanged<bool>? onSafeModeChanged,
}) {
  if (!kDiagnosticsScreenEnabled) return null;
  return MaterialPageRoute<void>(
    builder: (_) => ErrorDiagnosticsScreen(
      service: service ?? ErrorLogService.instance,
      onRetryInitialization: onRetryInitialization,
      onSafeModeChanged: onSafeModeChanged,
    ),
  );
}

class ErrorDiagnosticsScreen extends StatefulWidget {
  const ErrorDiagnosticsScreen({
    super.key,
    required this.service,
    this.onRetryInitialization,
    this.onSafeModeChanged,
  });

  final ErrorLogService service;
  final VoidCallback? onRetryInitialization;
  final ValueChanged<bool>? onSafeModeChanged;

  @override
  State<ErrorDiagnosticsScreen> createState() => _ErrorDiagnosticsScreenState();
}

class _ErrorDiagnosticsScreenState extends State<ErrorDiagnosticsScreen> {
  ErrorCategory? _categoryFilter;
  ErrorSeverity? _severityFilter;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  ErrorLogStore? get _store => widget.service.store;

  List<ErrorLogEntry> get _visible {
    final store = _store;
    if (store == null) return const <ErrorLogEntry>[];
    return store.filter(
      category: _categoryFilter,
      severity: _severityFilter,
      query: _query.isEmpty ? null : _query,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showDetail(ErrorLogEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${entry.category.name} · ${entry.severity.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('ID: ${entry.id}'),
              Text('Time: ${entry.timestampUtc}'),
              if (entry.startupStage != null)
                Text('Stage: ${entry.startupStage}'),
              Text(
                'App ${entry.appVersion}+${entry.buildNumber} | '
                'Android ${entry.androidVersion} | '
                'Device ${entry.deviceModel}',
              ),
              const SizedBox(height: 12),
              SelectableText(entry.message),
              if (entry.stackTrace != null &&
                  entry.stackTrace!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'Stack trace:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText(entry.stackTrace!),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: entry.toJsonLine()));
              if (context.mounted) {
                TopPopup.show(context, message: 'Error details copied.');
              }
            },
            child: const Text('Copy details'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final confirmed = await showIosAlert<bool>(
      context: context,
      title: title,
      message: message,
      actions: const [
        IosAlertAction<bool>('Cancel', value: false),
        IosAlertAction<bool>('Confirm', value: true, isDefault: true),
      ],
    );
    return confirmed ?? false;
  }

  Future<void> _export({required bool asJson}) async {
    final store = _store;
    if (store == null) return;
    final confirmed = await _confirm(
      asJson ? 'Export logs as JSON?' : 'Export logs as TXT?',
      'This creates a log file you can inspect before sharing it. '
      'Logs are never uploaded automatically.',
    );
    if (!confirmed || !mounted) return;
    try {
      final dir =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final name = asJson
          ? 'estudyantego-errors.json'
          : 'estudyantego-errors.txt';
      final file = File('${dir.path}/$name');
      await file.writeAsString(asJson ? store.exportJson() : store.exportTxt());
      if (!mounted) return;
      await Share.shareXFiles(<XFile>[
        XFile(file.path),
      ], text: 'EstudyanteGO error log export');
    } catch (_) {
      if (mounted) {
        TopPopup.show(context, message: 'Export failed.');
      }
    }
  }

  Future<void> _clear() async {
    final store = _store;
    if (store == null) return;
    final confirmed = await _confirm(
      'Clear all logs?',
      'This permanently deletes all stored error log entries. '
          'This cannot be undone.',
    );
    if (!confirmed) return;
    await store.confirmAndClear(confirmed: true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final safeMode = widget.service.safeMode;
    return Scaffold(
      appBar: AppBar(title: const Text('Error Diagnostics')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search error messages',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButton<ErrorCategory?>(
                        value: _categoryFilter,
                        isExpanded: true,
                        hint: const Text('All categories'),
                        items: <DropdownMenuItem<ErrorCategory?>>[
                          const DropdownMenuItem<ErrorCategory?>(
                            value: null,
                            child: Text('All categories'),
                          ),
                          for (final c in ErrorCategory.values)
                            DropdownMenuItem<ErrorCategory?>(
                              value: c,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryFilter = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<ErrorSeverity?>(
                        value: _severityFilter,
                        isExpanded: true,
                        hint: const Text('All severities'),
                        items: <DropdownMenuItem<ErrorSeverity?>>[
                          const DropdownMenuItem<ErrorSeverity?>(
                            value: null,
                            child: Text('All severities'),
                          ),
                          for (final s in ErrorSeverity.values)
                            DropdownMenuItem<ErrorSeverity?>(
                              value: s,
                              child: Text(s.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _severityFilter = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: () => _export(asJson: false),
                      icon: const Icon(Icons.description),
                      label: const Text('Export TXT'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _export(asJson: true),
                      icon: const Icon(Icons.data_object),
                      label: const Text('Export JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete),
                      label: const Text('Clear logs'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await widget.service.retryInitialization();
                        if (widget.onRetryInitialization != null) {
                          widget.onRetryInitialization!();
                        }
                        if (mounted) {
                          TopPopup.show(context, message: 'Retry requested. See the newest log ' 'entries for the result.',);
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Initialization'),
                    ),
                  ],
                ),
                IosSwitchRow(
                  title: const Text('Safe Mode'),
                  subtitle: const Text(
                    'Skips only nonessential services: App Check, ads, '
                    'notification prompt, AI services. Never skips auth, '
                    'profile, onboarding, prefs, or Firebase core.',
                  ),
                  value: safeMode,
                  onChanged: (value) {
                    widget.service.safeMode = value;
                    widget.onSafeModeChanged?.call(value);
                    setState(() {});
                  },
                ),
                Text(
                  'Showing ${visible.length} entr'
                  '${visible.length == 1 ? 'y' : 'ies'} '
                  '(latest first, cap ${kMaxLogEntries}). '
                  'Logs stay on this device unless you export them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No errors recorded yet.'))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return ListTile(
                        title: Text(
                          entry.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entry.timestampUtc} · '
                          '${entry.category.name} · '
                          '${entry.severity.name}'
                          '${entry.startupStage == null ? '' : ' · ${entry.startupStage}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetail(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
