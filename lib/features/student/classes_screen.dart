// Classes & Timetable — subject schedule manager (local only).
//
// Conflict detection blocks saving a subject that overlaps another
// subject on the same weekday. "Reminders" surface as the Upcoming
// section (this app has no push-notification plugin, so reminders
// appear in-app, not as system notifications).
import 'package:flutter/material.dart';

import '../app_layout.dart';
import '../ios_components.dart';
import 'student_data.dart';

const _subjectColors = [
  0xFF16A34A,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFEA580C,
  0xFFDB2777,
  0xFF0D9488,
  0xFFDC2626,
  0xFFCA8A04,
];

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  List<Subject> _subjects = [];
  List<AssignmentItem> _items = [];
  String _view = 'today';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subjects =
        await StudentStorage.loadList(StudentStorage.subjectsKey);
    final items =
        await StudentStorage.loadList(StudentStorage.assignmentsKey);
    if (!mounted) return;
    setState(() {
      _subjects = subjects.map(Subject.fromJson).toList();
      _items = items.map(AssignmentItem.fromJson).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
    });
  }

  Future<void> _saveSubjects() => StudentStorage.saveList(
      StudentStorage.subjectsKey, _subjects.map((s) => s.toJson()).toList());
  Future<void> _saveItems() => StudentStorage.saveList(
      StudentStorage.assignmentsKey, _items.map((i) => i.toJson()).toList());

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _subjectName(String id) {
    for (final s in _subjects) {
      if (s.id == id) return s.name;
    }
    return 'Subject';
  }

  Future<void> _openSubjectForm({Subject? existing}) async {
    final result = await showModalBottomSheet<Subject>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubjectForm(
        existing: existing,
        subjects: _subjects,
      ),
    );
    if (result == null) return;
    setState(() {
      _subjects.removeWhere((s) => s.id == result.id);
      _subjects.add(result);
    });
    await _saveSubjects();
    _snack(existing == null ? 'Subject added.' : 'Subject updated.');
  }

  Future<void> _deleteSubject(Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete subject?'),
        content: Text(
            '${s.name} and its assignments and exams will also be removed.'),
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
    setState(() {
      _subjects.removeWhere((x) => x.id == s.id);
      _items.removeWhere((i) => i.subjectId == s.id);
    });
    await _saveSubjects();
    await _saveItems();
  }

  Future<void> _openItemForm() async {
    if (_subjects.isEmpty) {
      _snack('Add a subject first, then attach deadlines to it.');
      return;
    }
    final result = await showModalBottomSheet<AssignmentItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemForm(subjects: _subjects),
    );
    if (result == null) return;
    setState(() {
      _items.add(result);
      _items.sort((a, b) => a.due.compareTo(b.due));
    });
    await _saveItems();
    _snack(result.kind == 'exam' ? 'Exam added.' : 'Assignment added.');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = nextClass(_subjects, now);
    final todays = classesOnDay(_subjects, now.weekday);
    final upcoming =
        _items.where((i) => !i.done).toList()..sort((a, b) => a.due.compareTo(b.due));
    final done = _items.where((i) => i.done).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Classes & Timetable')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSubjectForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add subject'),
      ),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          if (next != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.upcoming_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text('Upcoming: ${next.subject.name}'),
                subtitle: Text(
                    '${weekdayName(next.date.weekday)} · ${formatMinutes(next.subject.startMin)}–${formatMinutes(next.subject.endMin)}${next.subject.room.isEmpty ? '' : ' · ${next.subject.room}'}'),
              ),
            )
          else
            const Card(
              child: ListTile(
                title: Text('No upcoming classes.'),
                subtitle: Text('Add a subject to build your timetable.'),
              ),
            ),
          const SizedBox(height: AppLayout.headerGap),
          IosSegmentedControl<String>(
            segments: const [
              IosSegment(value: 'today', label: 'Today'),
              IosSegment(value: 'week', label: 'Week'),
            ],
            groupValue: _view,
            onValueChanged: (value) => setState(() => _view = value),
          ),
          const SizedBox(height: AppLayout.cardGap),
          if (_view == 'today') ...[
            if (todays.isEmpty)
              const Card(
                  child: ListTile(title: Text('No classes today.')))
            else
              for (final s in todays) _subjectTile(s),
          ] else ...[
            for (var day = 1; day <= 7; day++)
              if (classesOnDay(_subjects, day).isNotEmpty) ...[
                Text(weekdayName(day),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.s4),
                for (final s in classesOnDay(_subjects, day))
                  _subjectTile(s),
                const SizedBox(height: AppLayout.cardGap),
              ],
            if (_subjects.isEmpty)
              const Card(
                  child: ListTile(title: Text('No subjects yet.'))),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Assignments & Exams',
                    style:
                        AppText.sectionTitle),
              ),
              TextButton(onPressed: _openItemForm, child: const Text('Add')),
            ],
          ),
          if (upcoming.isEmpty && done.isEmpty)
            const Card(
                child: ListTile(title: Text('No assignments or exams yet.')))
          else ...[
            for (final i in upcoming) _itemTile(i),
            if (done.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              for (final i in done) _itemTile(i),
            ],
          ],
          const SizedBox(height: 72),
        ],
      ),
    );
  }

  Widget _subjectTile(Subject s) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(s.color),
          child: Text(
            s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(s.name),
        subtitle: Text(
            '${s.code.isEmpty ? '' : '${s.code} · '}${formatMinutes(s.startMin)}–${formatMinutes(s.endMin)}${s.teacher.isEmpty ? '' : ' · ${s.teacher}'}${s.room.isEmpty ? '' : ' · ${s.room}'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _openSubjectForm(existing: s),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteSubject(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(AssignmentItem i) {
    return Card(
      child: ListTile(
        leading: Icon(
            i.kind == 'exam' ? Icons.quiz_outlined : Icons.assignment_outlined),
        title: Text(
          i.title,
          style: i.done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
            '${_subjectName(i.subjectId)} · ${i.kind == 'exam' ? 'Exam' : 'Assignment'} · due ${formatDate(i.due)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: i.done,
              onChanged: (v) async {
                setState(() {
                  final idx = _items.indexWhere((x) => x.id == i.id);
                  if (idx >= 0) {
                    _items[idx] = AssignmentItem(
                      id: i.id,
                      subjectId: i.subjectId,
                      title: i.title,
                      kind: i.kind,
                      due: i.due,
                      done: v ?? false,
                    );
                  }
                });
                await _saveItems();
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                setState(() => _items.removeWhere((x) => x.id == i.id));
                await _saveItems();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectForm extends StatefulWidget {
  const _SubjectForm({this.existing, required this.subjects});

  final Subject? existing;
  final List<Subject> subjects;

  @override
  State<_SubjectForm> createState() => _SubjectFormState();
}

class _SubjectFormState extends State<_SubjectForm> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _teacher = TextEditingController();
  final _room = TextEditingController();
  final _days = <int>{};
  int _startMin = 8 * 60;
  int _endMin = 9 * 60;
  int _color = _subjectColors.first;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _code.text = e.code;
      _teacher.text = e.teacher;
      _room.text = e.room;
      _days.addAll(e.days);
      _startMin = e.startMin;
      _endMin = e.endMin;
      _color = e.color;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _teacher.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: (isStart ? _startMin : _endMin) ~/ 60,
          minute: (isStart ? _startMin : _endMin) % 60),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMin = minutes;
      } else {
        _endMin = minutes;
      }
    });
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
              widget.existing == null ? 'Add subject' : 'Edit subject',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppLayout.cardGap),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Subject name')),
            const SizedBox(height: AppSpacing.s8),
            TextField(
                controller: _code,
                decoration:
                    const InputDecoration(labelText: 'Subject code')),
            const SizedBox(height: AppSpacing.s8),
            TextField(
                controller: _teacher,
                decoration: const InputDecoration(labelText: 'Teacher')),
            const SizedBox(height: AppSpacing.s8),
            TextField(
                controller: _room,
                decoration:
                    const InputDecoration(labelText: 'Classroom / location')),
            const SizedBox(height: AppLayout.cardGap),
            const Text('Days',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 6,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(weekdayName(day)),
                    selected: _days.contains(day),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _days.add(day);
                      } else {
                        _days.remove(day);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Start: ${formatMinutes(_startMin)}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () => _pickTime(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('End: ${formatMinutes(_endMin)}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const Text('Color',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              children: [
                for (final c in _subjectColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      backgroundColor: Color(c),
                      radius: _color == c ? 20 : 16,
                      child: _color == c
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppLayout.headerGap),
            FilledButton(
              onPressed: () {
                if (_name.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter a subject name.')));
                  return;
                }
                if (_days.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Pick at least one day.')));
                  return;
                }
                if (_endMin <= _startMin) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('End time must be after start time.')));
                  return;
                }
                final candidate = Subject(
                  id: widget.existing?.id ?? newId(),
                  name: _name.text.trim(),
                  code: _code.text.trim(),
                  teacher: _teacher.text.trim(),
                  room: _room.text.trim(),
                  days: _days.toList()..sort(),
                  startMin: _startMin,
                  endMin: _endMin,
                  color: _color,
                );
                final conflict = findConflict(widget.subjects, candidate,
                    excludeId: widget.existing?.id);
                if (conflict != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Schedule conflict with $conflict. Pick another time.')));
                  return;
                }
                Navigator.pop(context, candidate);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.subjects});

  final List<Subject> subjects;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late String _subjectId;
  final _title = TextEditingController();
  String _kind = 'assignment';
  DateTime _due = DateTime.now();

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjects.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
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
          const Text('Add deadline',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppLayout.cardGap),
          DropdownButtonFormField<String>(
            value: _subjectId,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: [
              for (final s in widget.subjects)
                DropdownMenuItem(value: s.id, child: Text(s.name))
            ],
            onChanged: (v) {
              if (v != null) setState(() => _subjectId = v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: AppSpacing.s8),
          IosSegmentedControl<String>(
            segments: const [
              IosSegment(value: 'assignment', label: 'Assignment'),
              IosSegment(value: 'exam', label: 'Exam'),
            ],
            groupValue: _kind,
            onValueChanged: (value) => setState(() => _kind = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Due: ${formatDate(_due)}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _due,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _due = picked);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a title.')));
                return;
              }
              Navigator.pop(
                context,
                AssignmentItem(
                  id: newId(),
                  subjectId: _subjectId,
                  title: _title.text.trim(),
                  kind: _kind,
                  due: _due,
                  done: false,
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
