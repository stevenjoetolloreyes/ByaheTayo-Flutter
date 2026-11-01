// Attendance Sheet — personal attendance tracker (local only).
//
// Records are entered MANUALLY by the student. Nothing here claims
// official school verification — there is no school integration.
// CSV export and a real PDF report (pdf package) share actual files
// via share_plus.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'student_data.dart';

const _statuses = ['present', 'absent', 'late', 'excused', 'half'];

String _statusLabel(String s) {
  switch (s) {
    case 'present':
      return 'Present';
    case 'absent':
      return 'Absent';
    case 'late':
      return 'Late';
    case 'excused':
      return 'Excused';
    case 'half':
      return 'Half-day';
    default:
      return s;
  }
}

Color _statusColor(BuildContext context, String s) {
  switch (s) {
    case 'present':
      return Colors.green;
    case 'absent':
      return Theme.of(context).colorScheme.error;
    case 'late':
      return Colors.orange;
    case 'excused':
      return Colors.blueGrey;
    case 'half':
      return Colors.teal;
    default:
      return Colors.grey;
  }
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRecord> _records = [];
  List<Subject> _subjects = [];
  double _goal = 90;
  String _subjectFilter = 'all';
  String _statusFilter = 'all';
  DateTime? _dateFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records =
        await StudentStorage.loadList(StudentStorage.attendanceKey);
    final subjects =
        await StudentStorage.loadList(StudentStorage.subjectsKey);
    final goal = await StudentStorage.loadDouble(
        StudentStorage.attendanceGoalKey, 90);
    if (!mounted) return;
    setState(() {
      _records = records.map(AttendanceRecord.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _subjects = subjects.map(Subject.fromJson).toList();
      _goal = goal;
    });
  }

  Future<void> _saveRecords() => StudentStorage.saveList(
      StudentStorage.attendanceKey,
      _records.map((r) => r.toJson()).toList());

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _openForm({AttendanceRecord? existing}) async {
    final result = await showModalBottomSheet<AttendanceRecord>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _AttendanceForm(subjects: _subjects, existing: existing),
    );
    if (result == null) return;
    setState(() {
      _records.removeWhere((r) => r.id == result.id);
      _records.insert(0, result);
      _records.sort((a, b) => b.date.compareTo(a.date));
    });
    await _saveRecords();
    _snack(existing == null ? 'Record added.' : 'Record updated.');
  }

  Future<void> _deleteRecord(AttendanceRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text('${r.subject} · ${formatDate(r.date)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _records.removeWhere((x) => x.id == r.id));
    await _saveRecords();
  }

  Future<void> _setGoal() async {
    final value = TextEditingController(text: _goal.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Attendance goal (%)'),
        content: TextField(
          controller: value,
          decoration: const InputDecoration(labelText: 'Target percent'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final parsed = double.tryParse(value.text) ?? 0;
    if (parsed < 0 || parsed > 100) {
      _snack('Goal must be between 0 and 100.');
      return;
    }
    setState(() => _goal = parsed);
    await StudentStorage.saveDouble(
        StudentStorage.attendanceGoalKey, parsed);
  }

  Future<void> _exportCsv() async {
    final rows = <List<String>>[
      ['date', 'subject', 'status', 'note', 'reason'],
      for (final r in _records)
        [
          r.date.toIso8601String().split('T').first,
          r.subject,
          r.status,
          r.note,
          r.reason,
        ],
    ];
    final file = File('${Directory.systemTemp.path}/attendance.csv');
    await file.writeAsString(toCsv(rows));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _exportPdf() async {
    try {
      final stats = attendanceStats(_records);
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (_) => [
            pw.Text('Attendance Report',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text(
                'Overall: ${stats.percent.toStringAsFixed(1)}% · Present ${stats.present} · Absent ${stats.absent} · Late ${stats.late} · Excused ${stats.excused} · Half-day ${stats.half} · Total ${stats.total}'),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Subject', 'Status', 'Note'],
              data: [
                for (final r in _records)
                  [
                    r.date.toIso8601String().split('T').first,
                    r.subject,
                    _statusLabel(r.status),
                    r.note,
                  ],
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Records are entered manually by the student and are not verified by the school.',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      );
      final bytes = await doc.save();
      final file =
          File('${Directory.systemTemp.path}/attendance-report.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      _snack('PDF export failed — try CSV export instead.');
    }
  }

  Map<String, List<AttendanceRecord>> _weeklyGroups(
      List<AttendanceRecord> records) {
    final groups = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      final monday = r.date.subtract(Duration(days: r.date.weekday - 1));
      final key =
          '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    return groups;
  }

  Map<String, List<AttendanceRecord>> _monthlyGroups(
      List<AttendanceRecord> records) {
    final groups = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      final key =
          '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _records.where((r) {
      if (_subjectFilter != 'all' && r.subject != _subjectFilter) {
        return false;
      }
      if (_statusFilter != 'all' && r.status != _statusFilter) {
        return false;
      }
      if (_dateFilter != null &&
          (r.date.year != _dateFilter!.year ||
              r.date.month != _dateFilter!.month ||
              r.date.day != _dateFilter!.day)) {
        return false;
      }
      return true;
    }).toList();
    final stats = attendanceStats(_records);
    final subjects = <String>{};
    for (final r in _records) {
      subjects.add(r.subject);
    }
    final weekly = _weeklyGroups(_records);
    final weeklyKeys = weekly.keys.toList()..sort((a, b) => b.compareTo(a));
    final monthly = _monthlyGroups(_records);
    final monthlyKeys = monthly.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Sheet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export CSV',
            onPressed: _records.isEmpty ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF report',
            onPressed: _records.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add record'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Records are entered manually by you — not verified by '
            'the school.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${stats.percent.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                          onPressed: _setGoal,
                          child: Text('Goal: ${_goal.toStringAsFixed(0)}%')),
                    ],
                  ),
                  LinearProgressIndicator(
                    value: (stats.percent / 100).clamp(0, 1).toDouble(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'Present ${stats.present} · Absent ${stats.absent} · Late ${stats.late} · Excused ${stats.excused} · Half-day ${stats.half} · Total ${stats.total}'),
                  const SizedBox(height: 4),
                  const Text(
                    'Present% = full presents + lates + half of half-days, over all records except excused ones.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _subjectFilter,
                  decoration: const InputDecoration(
                      labelText: 'Subject', isDense: true),
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All subjects')),
                    for (final s in subjects)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _subjectFilter = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                      labelText: 'Status', isDense: true),
                  items: [
                    const DropdownMenuItem(
                        value: 'all', child: Text('All statuses')),
                    for (final s in _statuses)
                      DropdownMenuItem(
                          value: s, child: Text(_statusLabel(s))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _statusFilter = v);
                  },
                ),
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_dateFilter == null
                ? 'Filter date: All dates'
                : 'Filter date: ${formatDate(_dateFilter!)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_dateFilter != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () => setState(() => _dateFilter = null),
                  ),
                const Icon(Icons.calendar_month),
              ],
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dateFilter ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _dateFilter = picked);
            },
          ),
          if (filtered.isEmpty)
            const Card(child: ListTile(title: Text('No records found.')))
          else
            for (final r in filtered)
              Card(
                child: ListTile(
                  leading: Icon(Icons.circle,
                      color: _statusColor(context, r.status), size: 16),
                  title: Text(r.subject),
                  subtitle: Text(
                      '${formatDate(r.date)} · ${_statusLabel(r.status)}${r.reason.isEmpty ? '' : ' · ${r.reason}'}${r.note.isEmpty ? '' : ' · ${r.note}'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _openForm(existing: r),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteRecord(r),
                      ),
                    ],
                  ),
                ),
              ),
          if (weeklyKeys.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Weekly summaries',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final k in weeklyKeys.take(8))
              Card(
                child: ListTile(
                  title: Text('Week of $k'),
                  subtitle: Text(
                      '${attendanceStats(weekly[k]!).percent.toStringAsFixed(1)}% · ${weekly[k]!.length} records'),
                ),
              ),
          ],
          if (monthlyKeys.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Monthly summaries',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final k in monthlyKeys)
              Card(
                child: ListTile(
                  title: Text(k),
                  subtitle: Text(
                      '${attendanceStats(monthly[k]!).percent.toStringAsFixed(1)}% · ${monthly[k]!.length} records'),
                ),
              ),
          ],
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _AttendanceForm extends StatefulWidget {
  const _AttendanceForm({required this.subjects, this.existing});

  final List<Subject> subjects;
  final AttendanceRecord? existing;

  @override
  State<_AttendanceForm> createState() => _AttendanceFormState();
}

class _AttendanceFormState extends State<_AttendanceForm> {
  late String _subjectPick;
  final _customSubject = TextEditingController();
  final _note = TextEditingController();
  final _reason = TextEditingController();
  String _status = 'present';
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _status = e.status;
      _date = e.date;
      _note.text = e.note;
      _reason.text = e.reason;
      final match = widget.subjects.where((s) => s.name == e.subject);
      if (match.isNotEmpty) {
        _subjectPick = match.first.id;
      } else {
        _subjectPick = 'custom';
        _customSubject.text = e.subject;
      }
    } else if (widget.subjects.isNotEmpty) {
      _subjectPick = widget.subjects.first.id;
    } else {
      _subjectPick = 'custom';
    }
  }

  @override
  void dispose() {
    _customSubject.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  String get _subjectName {
    if (_subjectPick == 'custom') return _customSubject.text.trim();
    for (final s in widget.subjects) {
      if (s.id == _subjectPick) return s.name;
    }
    return '';
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Add record' : 'Edit record',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _subjectPick,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                for (final s in widget.subjects)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
                const DropdownMenuItem(
                    value: 'custom', child: Text('Custom subject…')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _subjectPick = v);
              },
            ),
            if (_subjectPick == 'custom') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customSubject,
                decoration:
                    const InputDecoration(labelText: 'Subject name'),
              ),
            ],
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
            const Text('Status',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 6,
              children: [
                for (final s in _statuses)
                  ChoiceChip(
                    label: Text(_statusLabel(s)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_status == 'absent' || _status == 'excused') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                decoration:
                    const InputDecoration(labelText: 'Absence reason'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (_subjectName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Pick or type a subject.')));
                  return;
                }
                Navigator.pop(
                  context,
                  AttendanceRecord(
                    id: widget.existing?.id ?? newId(),
                    subject: _subjectName,
                    date: _date,
                    status: _status,
                    note: _note.text.trim(),
                    reason: (_status == 'absent' || _status == 'excused')
                        ? _reason.text.trim()
                        : '',
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
