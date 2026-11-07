// Study tab — second tab in the top nav (preview parity, Nov 6, 2026).
//
// The preview's Study tab carries Grades, Files, Notes and Review
// behind its own pill sub-navigation. The shape is the preview's;
// the CONTENT is the app's own real data only:
//
// * Grades — the user's subjects (StudentStorage) + their own
//   recorded grades (GradeRecord, new in student_data.dart). The
//   preview's GWA 1.58 / 8 subjects are SAMPLE from a separate
//   study-app preview and are never hardcoded here: a fresh install
//   shows GWA "—" and "No grade yet" until the user records one.
// * Files — file metadata the user added (StudyFile: name, size,
//   type, folder). Nothing is seeded: folders start at 0 files and
//   the storage bar at 0 B of 5 GB. Only metadata is stored, never
//   file bytes.
// * Notes — the real notes from NotesScreen (StudentStorage),
//   searchable; tapping one opens NotesScreen for full CRUD.
// * Review — the real quizzes + attempts (StudentStorage) and the
//   real study entry points: Flashcards, Quiz, and AI Quiz. The
//   preview's Drag & Drop and Identification modes have no app
//   equivalent and are NOT faked with a substitute (see the
//   integration report's deviations).
//
// No schema changes: grades + files are new additive
// SharedPreferences keys; existing records are untouched.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'ai_quiz_generate_screen.dart';
import 'app_layout.dart';
import 'student/notes_screen.dart';
import 'student/student_data.dart';

/// 5 GB study-files quota, matching the preview's storage bar.
const _studyFilesQuotaBytes = 5 * 1024 * 1024 * 1024;

const _studyFolders = ['Lectures', 'Activities', 'Reviewers'];

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _fileKindForExtension(String ext) {
  switch (ext.toLowerCase()) {
    case 'pdf':
      return 'pdf';
    case 'doc':
    case 'docx':
    case 'txt':
      return 'doc';
    case 'ppt':
    case 'pptx':
      return 'ppt';
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return 'img';
    default:
      return 'other';
  }
}

IconData _fileKindIcon(String kind) {
  switch (kind) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
      return Icons.description_outlined;
    case 'ppt':
      return Icons.slideshow_outlined;
    case 'img':
      return Icons.image_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

/// GWA standing band (preview legend): 1.00–1.50 Excellent,
/// 1.75–2.25 Good, 2.50–3.00 Passing, 5.00 Failed. Values between
/// the printed bands take the nearest better-or-equal band edge.
String _gwaStanding(double gwa) {
  if (gwa <= 1.50) return 'Excellent';
  if (gwa <= 2.25) return 'Good';
  if (gwa <= 3.00) return 'Passing';
  return 'Failed';
}

class StudyTab extends StatefulWidget {
  const StudyTab({super.key});

  @override
  State<StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends State<StudyTab> {
  String _panel = 'grades';
  int _semester = 1;
  String _reviewMode = 'quiz';
  String _fileFilter = 'all';
  String _noteQuery = '';

  List<Subject> _subjects = [];
  List<GradeRecord> _grades = [];
  List<StudyFile> _files = [];
  List<Note> _notes = [];
  List<Quiz> _quizzes = [];
  List<QuizAttempt> _attempts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subjects =
        await StudentStorage.loadList(StudentStorage.subjectsKey);
    final grades = await StudentStorage.loadList(StudentStorage.gradesKey);
    final files =
        await StudentStorage.loadList(StudentStorage.studyFilesKey);
    final notes = await StudentStorage.loadList(StudentStorage.notesKey);
    final quizzes =
        await StudentStorage.loadList(StudentStorage.quizzesKey);
    final attempts =
        await StudentStorage.loadList(StudentStorage.attemptsKey);
    if (!mounted) return;
    setState(() {
      _subjects = subjects.map(Subject.fromJson).toList();
      _grades = grades.map(GradeRecord.fromJson).toList();
      _files = files.map(StudyFile.fromJson).toList()
        ..sort((a, b) => b.added.compareTo(a.added));
      _notes = notes.map(Note.fromJson).toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));
      _quizzes = quizzes.map(Quiz.fromJson).toList();
      _attempts = attempts.map(QuizAttempt.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _saveGrades() => StudentStorage.saveList(
      StudentStorage.gradesKey, _grades.map((g) => g.toJson()).toList());

  Future<void> _saveFiles() => StudentStorage.saveList(
      StudentStorage.studyFilesKey, _files.map((f) => f.toJson()).toList());

  /// Animation length for panel switches; zero when the user asked
  /// for reduced motion (preview animations are fast/subtle and
  /// reduced-motion aware).
  Duration _animDuration(BuildContext context) =>
      MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180);

  GradeRecord? _gradeFor(String subjectId) {
    for (final g in _grades) {
      if (g.subjectId == subjectId && g.semester == _semester) return g;
    }
    return null;
  }

  /// Weighted GWA for the selected semester, or null when no grade
  /// is recorded for it — shown as "—", never invented.
  double? get _gwa {
    var weighted = 0.0;
    var units = 0;
    for (final g in _grades) {
      if (g.semester != _semester) continue;
      weighted += g.grade * g.units;
      units += g.units;
    }
    if (units == 0) return null;
    return weighted / units;
  }

  int get _gwaUnits {
    var units = 0;
    for (final g in _grades) {
      if (g.semester == _semester) units += g.units;
    }
    return units;
  }

  int get _gradedCount {
    var n = 0;
    for (final g in _grades) {
      if (g.semester == _semester) n++;
    }
    return n;
  }

  Future<void> _openGradeForm(Subject subject) async {
    final existing = _gradeFor(subject.id);
    final gradeController = TextEditingController(
        text: existing == null ? '' : existing.grade.toStringAsFixed(2));
    final unitsController = TextEditingController(
        text: existing == null ? '3' : '${existing.units}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add grade' : 'Edit grade'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: gradeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Grade (1.00 – 5.00)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: unitsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Units',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              '${_semester == 1 ? '1st' : '2nd'} Semester · '
              '1.00 is the highest grade, 5.00 is failed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final grade = double.tryParse(gradeController.text.trim());
              final units = int.tryParse(unitsController.text.trim());
              if (grade == null || grade < 1.0 || grade > 5.0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Enter a grade from 1.00 to 5.00.')),
                );
                return;
              }
              if (units == null || units < 1 || units > 12) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter units from 1 to 12.')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final grade = double.parse(gradeController.text.trim());
    final units = int.parse(unitsController.text.trim());
    setState(() {
      _grades.removeWhere(
          (g) => g.subjectId == subject.id && g.semester == _semester);
      _grades.add(GradeRecord(
          subjectId: subject.id,
          grade: grade,
          units: units,
          semester: _semester));
    });
    await _saveGrades();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Grade saved.')));
    }
  }

  Future<void> _addFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'txt',
        'ppt',
        'pptx',
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
      ],
    );
    if (picked == null || !mounted) return;
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Save to folder'),
        children: [
          for (final f in _studyFolders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f),
              child: Text(f),
            ),
        ],
      ),
    );
    if (folder == null || !mounted) return;
    final ext = picked.name.contains('.')
        ? picked.name.split('.').last
        : '';
    // file_picker 13 reports size via length() (async) with a
    // sync fallback; unknown size stores as 0, never guessed.
    final sizeBytes =
        await picked.length() ?? picked.lengthSync() ?? 0;
    if (!mounted) return;
    setState(() {
      _files.insert(
        0,
        StudyFile(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: picked.name,
          sizeBytes: sizeBytes,
          kind: _fileKindForExtension(ext),
          folder: folder,
          added: DateTime.now(),
        ),
      );
    });
    await _saveFiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${picked.name} to $folder.')));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    // Notes / quizzes / attempts may have changed while the screen
    // was open — reload so the tab never shows stale counts.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: AppLayout.pagePaddingTab,
      children: [
        Text('Study',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.s4),
        Text(
          'Grades, files, notes, and review — your real study data.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.s16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'grades', label: Text('Grades')),
            ButtonSegment(value: 'files', label: Text('Files')),
            ButtonSegment(value: 'notes', label: Text('Notes')),
            ButtonSegment(value: 'review', label: Text('Review')),
          ],
          selected: {_panel},
          onSelectionChanged: (s) => setState(() => _panel = s.first),
        ),
        const SizedBox(height: AppSpacing.s16),
        AnimatedSwitcher(
          duration: _animDuration(context),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: switch (_panel) {
            'files' => _filesPanel(context, key: const ValueKey('files')),
            'notes' => _notesPanel(context, key: const ValueKey('notes')),
            'review' =>
              _reviewPanel(context, key: const ValueKey('review')),
            _ => _gradesPanel(context, key: const ValueKey('grades')),
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------- Grades

  Widget _gradesPanel(BuildContext context, {required Key key}) {
    final gwa = _gwa;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your standing for A.Y. 2026–2027, computed from the subjects below.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.s12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1st Semester')),
            ButtonSegment(value: 2, label: Text('2nd Semester')),
          ],
          selected: {_semester},
          onSelectionChanged: (s) => setState(() => _semester = s.first),
        ),
        const SizedBox(height: AppSpacing.s16),
        Card(
          child: Padding(
            padding: AppLayout.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GENERAL WEIGHTED AVERAGE',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      gwa == null ? '—' : gwa.toStringAsFixed(2),
                      style: const TextStyle(
                          fontSize: 40, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gwa == null ? '—' : _gwaStanding(gwa),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            gwa == null
                                ? '—'
                                : '$_gwaUnits units · $_gradedCount '
                                    'graded',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (_subjects.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No subjects yet.'),
              subtitle: Text(
                  'Add subjects from the Student tab → Classes & Timetable, then record grades here.'),
            ),
          )
        else
          for (final subject in _subjects)
            Card(
              child: ListTile(
                title: Text(subject.name),
                subtitle: Text(
                    subject.code.isEmpty ? 'No code' : subject.code),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _gradeFor(subject.id) == null
                          ? 'No grade yet'
                          : _gradeFor(subject.id)!
                              .grade
                              .toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    TextButton(
                      onPressed: () => _openGradeForm(subject),
                      child: Text(_gradeFor(subject.id) == null
                          ? 'Add grade'
                          : 'Edit'),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: const [
            _LegendDot(Color(0xFF4ADE80), '1.00 – 1.50 Excellent'),
            _LegendDot(Color(0xFF6DB1F7), '1.75 – 2.25 Good'),
            _LegendDot(Color(0xFFF7B955), '2.50 – 3.00 Passing'),
            _LegendDot(Color(0xFFFF8296), '5.00 Failed'),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Files

  Widget _filesPanel(BuildContext context, {required Key key}) {
    final used = _files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
    final filtered = _fileFilter == 'all'
        ? _files
        : _files.where((f) => f.kind == _fileFilter).toList();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: AppLayout.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Study files',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${_formatBytes(used)} of 5 GB used',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                LinearProgressIndicator(
                  value: (used / _studyFilesQuotaBytes).clamp(0.0, 1.0),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const [
                ('all', 'All'),
                ('pdf', 'PDF'),
                ('doc', 'Docs'),
                ('ppt', 'Slides'),
                ('img', 'Images'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(entry.$2),
                    selected: _fileFilter == entry.$1,
                    onSelected: (_) =>
                        setState(() => _fileFilter = entry.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        const Text('FOLDERS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            for (final folder in _studyFolders)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(Icons.folder_outlined),
                          const SizedBox(height: AppSpacing.s4),
                          Text(folder,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          Text(
                            '${_files.where((f) => f.folder == folder).length} files',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        Row(
          children: [
            const Expanded(
              child: Text('RECENT FILES',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: _addFile,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add file'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        if (filtered.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No files yet.'),
              subtitle: Text(
                  'Add a PDF, document, slides, or image to keep it here.'),
            ),
          )
        else
          for (final file in filtered)
            Card(
              child: ListTile(
                leading: Icon(_fileKindIcon(file.kind)),
                title: Text(file.name),
                subtitle: Text(
                    '${_formatBytes(file.sizeBytes)} · ${file.folder}'),
                trailing: IconButton(
                  tooltip: 'Remove file',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    setState(() =>
                        _files.removeWhere((f) => f.id == file.id));
                    await _saveFiles();
                  },
                ),
              ),
            ),
      ],
    );
  }

  // ------------------------------------------------------------ Notes

  Widget _notesPanel(BuildContext context, {required Key key}) {
    final query = _noteQuery.toLowerCase();
    final filtered = _notes.where((n) {
      if (query.isEmpty) return true;
      return n.title.toLowerCase().contains(query) ||
          n.body.toLowerCase().contains(query);
    }).toList();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _noteQuery = v),
          decoration: InputDecoration(
            hintText: 'Search notes',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (filtered.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No notes yet.'),
              subtitle:
                  Text('Write your first note to see it here.'),
            ),
          )
        else
          for (final note in filtered)
            Card(
              child: ListTile(
                title: Text(note.title),
                subtitle: Text(note.subject.isEmpty
                    ? 'No subject'
                    : note.subject),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(const NotesScreen()),
              ),
            ),
        const SizedBox(height: AppSpacing.s12),
        FilledButton.icon(
          onPressed: () => _open(const NotesScreen()),
          icon: const Icon(Icons.note_outlined),
          label: const Text('Open notes'),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- Review

  Widget _reviewPanel(BuildContext context, {required Key key}) {
    final avg = _attempts.isEmpty
        ? null
        : _attempts
                .map((a) => a.total > 0 ? a.score / a.total * 100 : 0.0)
                .reduce((a, b) => a + b) /
            _attempts.length;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'quiz', label: Text('Quiz')),
            ButtonSegment(value: 'summary', label: Text('Summary')),
          ],
          selected: {_reviewMode},
          onSelectionChanged: (s) => setState(() => _reviewMode = s.first),
        ),
        const SizedBox(height: AppSpacing.s16),
        if (_reviewMode == 'quiz') ...[
          const Text('Pick how to study',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.s8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.style_outlined),
              title: const Text('Flashcards'),
              subtitle:
                  const Text('Flip through questions one at a time'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _open(const NotesScreen(initialTab: 'cards')),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.quiz_outlined),
              title: const Text('Quiz'),
              subtitle: const Text(
                  'Answer multiple-choice, get scored'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _open(const NotesScreen(initialTab: 'quizzes')),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI Quiz'),
              subtitle: const Text(
                  'Pick a PDF or photo of your notes and the app takes it from there'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const AiQuizGenerateScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          const Text('Your quizzes',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.s8),
          if (_quizzes.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No quizzes yet.'),
                subtitle: Text(
                    'Create one with AI or add a quiz from your notes.'),
              ),
            )
          else
            for (final quiz in _quizzes)
              Card(
                child: ListTile(
                  title: Text(quiz.title),
                  subtitle: Text(
                      '${quiz.questions.length} questions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _open(const NotesScreen(initialTab: 'quizzes')),
                ),
              ),
        ] else ...[
          Card(
            child: Padding(
              padding: AppLayout.cardPadding,
              child: Column(
                children: [
                  _summaryRow('Quizzes completed', '${_attempts.length}'),
                  _summaryRow('Quizzes saved', '${_quizzes.length}'),
                  _summaryRow(
                    'Average score',
                    avg == null ? '—' : '${avg.toStringAsFixed(1)}%',
                  ),
                  _summaryRow('Notes saved', '${_notes.length}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          const Text('Recent attempts',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.s8),
          if (_attempts.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No quiz attempts yet.'),
                subtitle: Text('Take a quiz to see your results here.'),
              ),
            )
          else
            for (final attempt in _attempts.take(5))
              Card(
                child: ListTile(
                  title: Text(attempt.quizTitle),
                  subtitle: Text(
                      '${attempt.score}/${attempt.total}'),
                ),
              ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
