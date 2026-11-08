// Study tab — second tab in the top nav (preview parity, Nov 6, 2026;
// color + design port from the preview's Study tab, Nov 7, 2026).
//
// The DESIGN is the preview's (fares-phone-preview Study CSS, dark
// default + light theme): per-panel title + heart/star chips, Quiz |
// Summary pills, blue/green/amber quiz deck cards, gradient GWA
// card, tinted file-type tiles, note cards with subject tags, a
// green + FAB, and a floating bottom pill nav (Grades | Files |
// Notes | Review). The CONTENT is the app's own real data only —
// the preview's sample quizzes, grades, files, notes and its ❤️ 15
// are never hardcoded here:
//
// * Grades — the user's subjects (StudentStorage) + their own
//   recorded grades (GradeRecord). A fresh install shows GWA "—"
//   and "No grade yet" until the user records one.
// * Files — file metadata the user added (StudyFile: name, size,
//   type, folder). Nothing is seeded: folders start at 0 files and
//   the storage bar at 0 B of 5 GB. Only metadata is stored, never
//   file bytes.
// * Notes — the real notes from NotesScreen (StudentStorage),
//   searchable; tapping one opens NotesScreen for full CRUD.
// * Review — the real quizzes (StudentStorage) and the real study
//   entry points: Flashcards, Quiz, and AI Quiz. Quiz shows the
//   deck cards; Summary shows the same decks as summary cards
//   (icon + title + teaser + chevron), exactly as the preview's
//   #stReviewSummary does. The stats view the port first built
//   in Summary (Quizzes completed/saved, Average score, Notes
//   saved, Recent attempts) has no counterpart anywhere in the
//   preview's Review tab, so it is gone — not moved elsewhere.
//   The preview's Drag & Drop and Identification modes have no
//   app equivalent and are NOT faked with a substitute.
//
// Real-data mappings for the preview's chips (the preview's ❤️ 15
// is a hardcoded sample):
// * ❤️ = the user's favorited-notes count (Note.favorite, toggled
//   in NotesScreen). 0 with no favorites — never invented.
// * ⭐ = the real points balance from the shell's
//   PointsWalletController (wired in main.dart; null in widget
//   tests, where the chip honestly shows 0 pts).
//
// Deviations from the preview, with reasons:
// * The preview's Summary cards show a prose description excerpt
//   as the teaser; Quiz stores no summary/description text, so
//   the teaser is the deck's real facts instead (subject ·
//   question count · difficulty) — never invented. Tapping a
//   Summary card opens the quizzes list, where the deck's
//   content lives; the app has no standalone summary reader.
// * Quiz deck cards show the quiz's subject where the preview
//   shows a date ("Oct 16"): Quiz stores no creation date, and
//   the last-attempt date would mean something else, so it is
//   not shown as a date.
// * The preview's FAB opens a "What do you want to make?" sheet;
//   the app has no such sheet, so the FAB goes straight to the
//   panel's real create flow (Grades → grade form, Files → file
//   picker, Notes → Notes, Review → AI Quiz).
// * The preview's Review screen has no "Pick how to study" entry
//   cards; the app keeps Flashcards / Quiz / AI Quiz below the
//   deck list — they are the only way to take a quiz or open
//   flashcards, so dropping them would remove real functionality.
// * The header title follows the active panel (Grades / Files /
//   Notes / Review). The preview's static markup only shows the
//   default 'Review' title; the switch is inferred from its
//   #stTitle script hook (unverified).
// * Light-theme deck gradient stops are derived from the preview's
//   light hues at the dark theme's alphas (the inspection reported
//   light hues but not light gradient stops); the light border
//   color is derived from the light text color at 0.08 (the
//   preview's light theme does not override --line). The GWA
//   gradient card keeps the dark gradient in light theme (white
//   text on the brand gradient stays readable; no light variant
//   was reported).
// * The "Add file" header button and the "Open notes" button are
//   gone — the panel-aware FAB is now the create entry (same
//   destination). Subject rows drop the 'No code' placeholder
//   (the preview shows code + name only when a code exists).
// * The bottom pill nav's four buttons share the pill width
//   equally (Expanded) and the pill caps at 400px with 16px
//   side margins. The preview's pill is content-sized, but its
//   buttons overflow a 390px phone by ~100px (widget_test, Nov 7)
//   — equal widths keep the 13px labels and guarantee the fit
//   on narrow phones instead of shrinking the text.
//
// No schema changes: grades + files are additive SharedPreferences
// keys; existing records are untouched.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'ai_quiz_generate_screen.dart';
import 'app_layout.dart';
import 'friend_cloud_repository.dart';
import 'ios_components.dart';
import 'onboarding/auth_service.dart';
import 'points_wallet_repository.dart';
import 'shared_study_files.dart';
import 'student/notes_screen.dart';
import 'student/student_data.dart';

/// 5 GB study-files quota, matching the preview's storage bar.
const _studyFilesQuotaBytes = 5 * 1024 * 1024 * 1024;

const _studyFolders = ['Lectures', 'Activities', 'Reviewers'];

/// One deck accent: the hue color plus the two gradient stops
/// (CSS 155deg: top-left toward bottom-right).
typedef _DeckHue = ({Color hue, Color from, Color to});

/// Preview Study tokens (fares-phone-preview Study CSS vars).
/// Dark is the preview's default; light is its light theme. The
/// page background itself comes from the app theme (#0c1410 dark),
/// which already matches the preview.
class _StudyTokens {
  const _StudyTokens({
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.muted,
    required this.faint,
    required this.line,
    required this.brand,
    required this.brandDeep,
    required this.brandSoft,
    required this.accent,
    required this.gold,
    required this.sheetBg,
    required this.ok,
    required this.bad,
    required this.blue,
    required this.green,
    required this.amber,
    required this.violet,
    required this.heart,
    required this.deckHues,
  });

  static const dark = _StudyTokens(
    surface: Color(0xFF13211A),
    surface2: Color(0xFF1A2C22),
    surface3: Color(0xFF223829),
    text: Color(0xFFEEF5F1),
    muted: Color(0xFF9DB4A8),
    faint: Color(0xFF6F8A7C),
    line: Color.fromRGBO(238, 245, 241, 0.09),
    brand: Color(0xFF16A34A),
    brandDeep: Color(0xFF14532D),
    brandSoft: Color.fromRGBO(22, 163, 74, 0.16),
    accent: Color(0xFF34D399),
    gold: Color(0xFFF5C04E),
    sheetBg: Color(0xFF101D16),
    ok: Color(0xFF4ADE80),
    bad: Color(0xFFFF8296),
    blue: Color(0xFF6DB1F7),
    green: Color(0xFF4ADE80),
    amber: Color(0xFFF7B955),
    violet: Color(0xFFBDA8FF),
    heart: Color(0xFFFB4D6D),
    deckHues: [
      (
        hue: Color(0xFF6DB1F7),
        from: Color.fromRGBO(47, 127, 224, 0.26),
        to: Color.fromRGBO(47, 127, 224, 0.08),
      ),
      (
        hue: Color(0xFF4ADE80),
        from: Color.fromRGBO(22, 163, 74, 0.26),
        to: Color.fromRGBO(22, 163, 74, 0.08),
      ),
      (
        hue: Color(0xFFF7B955),
        from: Color.fromRGBO(245, 165, 36, 0.24),
        to: Color.fromRGBO(245, 165, 36, 0.07),
      ),
    ],
  );

  static const light = _StudyTokens(
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF4F0),
    surface3: Color(0xFFE2EDE6),
    text: Color(0xFF10231A),
    muted: Color(0xFF55705F),
    faint: Color(0xFF82998A),
    line: Color.fromRGBO(16, 35, 26, 0.08),
    brand: Color(0xFF087C4B),
    brandDeep: Color(0xFF064E36),
    brandSoft: Color.fromRGBO(8, 124, 75, 0.1),
    accent: Color(0xFF087C4B),
    gold: Color(0xFFB97F10),
    sheetBg: Color(0xFFFFFFFF),
    ok: Color(0xFF12805C),
    bad: Color(0xFFD43A54),
    blue: Color(0xFF1F6AD0),
    green: Color(0xFF12805C),
    amber: Color(0xFFB97F10),
    violet: Color(0xFF7C5CD6),
    heart: Color(0xFFFB4D6D),
    deckHues: [
      (
        hue: Color(0xFF1F6AD0),
        from: Color.fromRGBO(31, 106, 208, 0.26),
        to: Color.fromRGBO(31, 106, 208, 0.08),
      ),
      (
        hue: Color(0xFF12805C),
        from: Color.fromRGBO(18, 128, 92, 0.26),
        to: Color.fromRGBO(18, 128, 92, 0.08),
      ),
      (
        hue: Color(0xFFB97F10),
        from: Color.fromRGBO(185, 127, 16, 0.24),
        to: Color.fromRGBO(185, 127, 16, 0.07),
      ),
    ],
  );

  static _StudyTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color text;
  final Color muted;
  final Color faint;
  final Color line;
  final Color brand;
  final Color brandDeep;
  final Color brandSoft;
  final Color accent;
  final Color gold;
  final Color sheetBg;
  final Color ok;
  final Color bad;
  final Color blue;
  final Color green;
  final Color amber;
  final Color violet;
  final Color heart;
  final List<_DeckHue> deckHues;
}

/// Grade-pill backgrounds (translucent; same in both themes).
const _gradeExcellentBg = Color.fromRGBO(47, 191, 113, 0.16);
const _gradeGoodBg = Color.fromRGBO(47, 127, 224, 0.16);
const _gradePassingBg = Color.fromRGBO(245, 165, 36, 0.15);
const _gradeFailedBg = Color.fromRGBO(244, 80, 106, 0.15);

/// File-type icon tile backgrounds (translucent; same in both themes).
const _tilePdfBg = Color.fromRGBO(244, 80, 106, 0.14);
const _tileDocBg = Color.fromRGBO(47, 127, 224, 0.15);
const _tilePptBg = Color.fromRGBO(245, 165, 36, 0.14);
const _tileImgBg = Color.fromRGBO(47, 191, 113, 0.14);

/// Note-tag backgrounds (translucent; same in both themes).
const _tagBlueBg = Color.fromRGBO(47, 127, 224, 0.14);
const _tagGreenBg = Color.fromRGBO(47, 191, 113, 0.13);
const _tagAmberBg = Color.fromRGBO(245, 165, 36, 0.13);
const _tagVioletBg = Color.fromRGBO(154, 123, 255, 0.14);

/// Heart-chip background (translucent; same in both themes).
const _heartChipBg = Color.fromRGBO(251, 77, 109, 0.13);

/// Floating-layer shadows from the preview (same in both themes).
const _navShadow = BoxShadow(
  color: Color.fromRGBO(0, 0, 0, 0.4),
  blurRadius: 34,
  offset: Offset(0, 14),
);
const _fabShadow = BoxShadow(
  color: Color.fromRGBO(0, 0, 0, 0.4),
  blurRadius: 28,
  offset: Offset(0, 12),
);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// "Nov 4" — the preview's note-card date format.
String _monthDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';

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

/// File-type label for the details dialog ('PDF', 'Document', ...).
String _fileKindLabel(String kind) {
  switch (kind) {
    case 'pdf':
      return 'PDF';
    case 'doc':
      return 'Document';
    case 'ppt':
      return 'Slides';
    case 'img':
      return 'Image';
    default:
      return 'File';
  }
}

/// GWA standing band (preview legend): 1.00–1.50 Excellent,
/// 1.75–2.25 Good, 2.50–3.00 Passing, 5.00 Failed. Values between
/// the printed bands take the nearest better-or-equal band edge.
/// Also the band for a single grade's pill.
String _gwaStanding(double gwa) {
  if (gwa <= 1.50) return 'Excellent';
  if (gwa <= 2.25) return 'Good';
  if (gwa <= 3.00) return 'Passing';
  return 'Failed';
}

class StudyTab extends StatefulWidget {
  const StudyTab({
    super.key,
    this.walletController,
    this.visible = true,
    this.currentUser,
    this.friendCloudRepository,
    this.sharedFileRepository,
  });

  /// The shell's points wallet (same controller the Student and
  /// Account tabs read). Null in widget tests — the ⭐ chip then
  /// honestly shows 0 pts.
  final PointsWalletController? walletController;

  /// Whether this tab is the selected one. The shell passes
  /// `selectedIndex == 1`; the tab reloads when it becomes
  /// visible (see didUpdateWidget) so a subject added in
  /// Student → Classes & Timetable appears in Grades without an
  /// app restart (Fares × Map audit, Nov 7, 2026: cross-tab
  /// staleness). True by default (widget tests).
  final bool visible;

  /// The signed-in user (the shell's AuthUser). Null in widget
  /// tests and when signed out — sharing then honestly says so
  /// instead of inventing a sender, and "Shared with me" stays
  /// hidden.
  final AuthUser? currentUser;

  /// Cloud friends (accepted friend requests only). Null when
  /// Firebase is not configured — the share sheet then says
  /// sharing is not available, never a fake friend list.
  final FriendCloudRepository? friendCloudRepository;

  /// Shared-file storage (Firestore vs Local, chosen by the shell
  /// the same way as the Fares tab repos). Null in widget tests
  /// that do not wire it — the shared section then stays hidden.
  final SharedStudyFileRepository? sharedFileRepository;

  @override
  State<StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends State<StudyTab> {
  String _panel = 'grades';
  int _semester = 1;
  String _reviewMode = 'quiz';
  String _fileFilter = 'all';
  /// Folder tapped in the Files panel, or null for all folders.
  String? _selectedFolder;
  String _noteQuery = '';

  List<Subject> _subjects = [];
  List<GradeRecord> _grades = [];
  List<StudyFile> _files = [];
  List<Note> _notes = [];
  List<Quiz> _quizzes = [];

  /// Files shared TO this user (newest first). Empty when signed
  /// out, when no repository is wired, or when nobody shared
  /// anything — never invented.
  List<SharedStudyFile> _sharedWithMe = [];

  @override
  void initState() {
    super.initState();
    widget.walletController?.addListener(_onWalletChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant StudyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Becoming visible again (e.g. back from the Student tab):
    // reload the shared StudentStorage lists so edits made in
    // another tab show here at once. A rebuild while already
    // visible (oldWidget.visible) does NOT reload — _load is a
    // storage read, not a reaction to a parent rebuild.
    if (oldWidget.visible || !widget.visible) return;
    _load();
  }

  @override
  void dispose() {
    widget.walletController?.removeListener(_onWalletChanged);
    super.dispose();
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  /// Real points balance from the wallet (⭐ chip). 0 when no
  /// controller is wired (widget tests) — never invented.
  int get _points => widget.walletController?.balance ?? 0;

  /// Favorited notes (❤️ chip). The preview's 15 is a hardcoded
  /// sample; the real value is the user's own favorited-note count.
  int get _favoriteCount => _notes.where((n) => n.favorite).length;

  String get _panelTitle => switch (_panel) {
        'files' => 'Files',
        'notes' => 'Notes',
        'review' => 'Review',
        _ => 'Grades',
      };

  Future<void> _load() async {
    final subjects =
        await StudentStorage.loadList(StudentStorage.subjectsKey);
    final grades = await StudentStorage.loadList(StudentStorage.gradesKey);
    final files =
        await StudentStorage.loadList(StudentStorage.studyFilesKey);
    final notes = await StudentStorage.loadList(StudentStorage.notesKey);
    final quizzes =
        await StudentStorage.loadList(StudentStorage.quizzesKey);
    final shared = await _loadSharedWithMe();
    if (!mounted) return;
    setState(() {
      _subjects = subjects.map(Subject.fromJson).toList();
      _grades = grades.map(GradeRecord.fromJson).toList();
      _files = files.map(StudyFile.fromJson).toList()
        ..sort((a, b) => b.added.compareTo(a.added));
      _notes = notes.map(Note.fromJson).toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));
      _quizzes = quizzes.map(Quiz.fromJson).toList();
      _sharedWithMe = shared;
    });
  }

  /// Files shared TO the signed-in user, newest first. Empty when
  /// signed out or when no repository is wired. Reads never throw:
  /// a storage failure loads as no shares, never a fake list.
  Future<List<SharedStudyFile>> _loadSharedWithMe() async {
    final user = widget.currentUser;
    final repo = widget.sharedFileRepository;
    if (user == null || repo == null) return const [];
    try {
      return await repo.fetchSharedWithMe(user.uid);
    } catch (_) {
      return const [];
    }
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

  /// The + FAB goes straight to the panel's real create flow (the
  /// preview's "What do you want to make?" sheet has no app
  /// equivalent). Grades has no "add subject" flow inside Study —
  /// subjects come from the Student tab — so its FAB opens the
  /// grade form for the first subject with no grade this semester.
  Future<void> _onFab() async {
    if (_panel == 'files') {
      await _addFile();
    } else if (_panel == 'notes') {
      await _open(const NotesScreen());
    } else if (_panel == 'review') {
      await _open(const AiQuizGenerateScreen());
    } else {
      await _fabGrades();
    }
  }

  Future<void> _fabGrades() async {
    if (_subjects.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add subjects from the Student tab → Classes & Timetable first.',
          ),
        ),
      );
      return;
    }
    final ungraded = _subjects.where((s) => _gradeFor(s.id) == null);
    await _openGradeForm(
        ungraded.isEmpty ? _subjects.first : ungraded.first);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _StudyTokens.of(context);
    return Stack(
      children: [
        ListView(
          // 118px bottom padding clears the floating pill nav +
          // FAB, exactly like the preview's #screen-study.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 118),
          children: [
            _panelHeader(tokens),
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
                'files' =>
                  _filesPanel(context, tokens, key: const ValueKey('files')),
                'notes' =>
                  _notesPanel(context, tokens, key: const ValueKey('notes')),
                'review' => _reviewPanel(context, tokens,
                    key: const ValueKey('review')),
                _ => _gradesPanel(context, tokens,
                    key: const ValueKey('grades')),
              },
            ),
          ],
        ),
        Positioned(
          right: 18,
          bottom: 84,
          child: _fab(tokens),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _bottomNav(tokens),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------- shared bits

  /// Preview header row: panel title left, ❤️ / ⭐ chips right.
  /// Title is Plus Jakarta Sans 30px / 800, letter-spacing -0.02em.
  Widget _panelHeader(_StudyTokens tokens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _panelTitle,
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: tokens.text,
            ),
          ),
        ),
        _chip(
          key: const ValueKey('study-hearts-chip'),
          icon: Icons.favorite,
          iconColor: tokens.heart,
          background: _heartChipBg,
          label: '$_favoriteCount',
          textColor: tokens.bad,
        ),
        const SizedBox(width: 8),
        _chip(
          key: const ValueKey('study-points-chip'),
          icon: Icons.star,
          iconColor: tokens.gold,
          background: tokens.brandSoft,
          label: '$_points pts',
          textColor: tokens.accent,
        ),
      ],
    );
  }

  /// Preview chip: 12.5px bold, padding 6px 11px, radius 999px.
  Widget _chip({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required Color background,
    required String label,
    required Color textColor,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Preview surface card: Study surface, hairline border, no
  /// elevation shadow (the app's shared CardTheme is #202B25 in
  /// dark mode — the preview's Study surfaces are #13211a etc.).
  Widget _studyCard(_StudyTokens tokens, Widget child,
      {double radius = 15, EdgeInsetsGeometry? padding, Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? tokens.line),
      ),
      padding: padding,
      child: child,
    );
  }

  /// Honest empty-state card (same surface language).
  Widget _emptyCard(_StudyTokens tokens, String title, String subtitle) {
    return _studyCard(
      tokens,
      ListTile(
        title: Text(title, style: TextStyle(color: tokens.text)),
        subtitle: Text(subtitle, style: TextStyle(color: tokens.muted)),
      ),
    );
  }

  /// Preview + FAB: 56px circle, brand fill, '+' 20px.
  Widget _fab(_StudyTokens tokens) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tokens.brand,
        boxShadow: const [_fabShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _onFab,
          child: const Center(
            child: Icon(Icons.add, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Preview bottom pill nav: sheet-bg pill, radius 999, padding
  /// 6px, gap 4px; inactive buttons muted, active button brand
  /// fill with white text. Order: Grades | Files | Notes | Review.
  /// The four buttons share the pill width equally (Expanded):
  /// the preview's content-sized pill overflows a 390px phone
  /// by ~100px (widget_test, Nov 7), so equal widths — not
  /// smaller text — keep the 13px labels and guarantee the fit
  /// on narrow phones. Deviation from the preview, listed in
  /// the file header.
  Widget _bottomNav(_StudyTokens tokens) {
    const entries = [
      ('grades', 'Grades', Icons.workspace_premium_outlined),
      ('files', 'Files', Icons.folder_outlined),
      ('notes', 'Notes', Icons.note_alt_outlined),
      ('review', 'Review', Icons.help_outline),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tokens.sheetBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.line),
        boxShadow: const [_navShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _navButton(
                tokens,
                value: entries[i].$1,
                label: entries[i].$2,
                icon: entries[i].$3,
                active: _panel == entries[i].$1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Preview nav button: 44px tall, 13px bold, icon 15px;
  /// active gets the brand fill + 14px side padding.
  Widget _navButton(
    _StudyTokens tokens, {
    required String value,
    required String label,
    required IconData icon,
    required bool active,
  }) {
    final color = active ? Colors.white : tokens.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('study-nav-$value'),
        onTap: () => setState(() => _panel = value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          padding:
              EdgeInsets.symmetric(horizontal: active ? 14 : 10),
          decoration: BoxDecoration(
            color: active ? tokens.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Preview segmented control (.st-seg): surface-2 container,
  /// radius 15px, padding 4px, gap 4px; the active button is
  /// surface-3 with accent text — NOT a solid green fill.
  Widget _studySeg(
    _StudyTokens tokens, {
    required List<(String, String)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(options[i].$1),
                  borderRadius: BorderRadius.circular(11),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 9, horizontal: 6),
                    decoration: BoxDecoration(
                      color: options[i].$1 == selected
                          ? tokens.surface3
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      options[i].$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: options[i].$1 == selected
                            ? tokens.accent
                            : tokens.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------- Grades

  Widget _gradesPanel(BuildContext context, _StudyTokens tokens,
      {required Key key}) {
    final gwa = _gwa;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your standing for A.Y. 2026–2027, computed from the subjects below.',
          style: TextStyle(fontSize: 13.5, color: tokens.muted),
        ),
        const SizedBox(height: AppSpacing.s12),
        _studySeg(
          tokens,
          options: const [('1', '1st Semester'), ('2', '2nd Semester')],
          selected: '$_semester',
          onSelected: (v) => setState(() => _semester = int.parse(v)),
        ),
        const SizedBox(height: AppSpacing.s16),
        Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            gradient: LinearGradient(
              // CSS 140deg: top-left toward bottom-right.
              begin: Alignment(-0.643, -0.766),
              end: Alignment(0.643, 0.766),
              stops: [0.0, 0.55, 1.0],
              colors: [
                Color(0xFF14532D),
                Color(0xFF16A34A),
                Color(0xFF34D399),
              ],
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GENERAL WEIGHTED AVERAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    gwa == null ? '—' : gwa.toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gwa == null ? '—' : _gwaStanding(gwa),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        Text(
                          gwa == null
                              ? '—'
                              : '$_gwaUnits units · $_gradedCount '
                                  'graded',
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (_subjects.isEmpty)
          _emptyCard(
            tokens,
            'No subjects yet.',
            'Add subjects from the Student tab → Classes & Timetable, then record grades here.',
          )
        else
          for (var i = 0; i < _subjects.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _subjectRow(tokens, _subjects[i]),
          ],
        const SizedBox(height: AppSpacing.s12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _LegendDot(tokens.ok, '1.00 – 1.50 Excellent'),
            _LegendDot(tokens.blue, '1.75 – 2.25 Good'),
            _LegendDot(tokens.amber, '2.50 – 3.00 Passing'),
            _LegendDot(tokens.bad, '5.00 Failed'),
          ],
        ),
      ],
    );
  }

  /// Preview subject row: code 11px / 800 in blue, name 14px,
  /// grade as a band-colored pill; Add grade / Edit stays.
  Widget _subjectRow(_StudyTokens tokens, Subject subject) {
    final grade = _gradeFor(subject.id);
    return _studyCard(
      tokens,
      Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subject.code.isNotEmpty)
                    Text(
                      subject.code,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: tokens.blue,
                      ),
                    ),
                  Text(
                    subject.name,
                    style: TextStyle(fontSize: 14, color: tokens.text),
                  ),
                ],
              ),
            ),
            if (grade == null)
              Text(
                'No grade yet',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: tokens.muted),
              )
            else
              _gradePill(tokens, grade.grade),
            const SizedBox(width: AppSpacing.s8),
            TextButton(
              onPressed: () => _openGradeForm(subject),
              child: Text(grade == null ? 'Add grade' : 'Edit'),
            ),
          ],
        ),
      ),
    );
  }

  /// Preview grade pill: band-tinted background, band-hue text.
  Widget _gradePill(_StudyTokens tokens, double grade) {
    final (Color, Color) colors = switch (_gwaStanding(grade)) {
      'Excellent' => (_gradeExcellentBg, tokens.ok),
      'Good' => (_gradeGoodBg, tokens.blue),
      'Passing' => (_gradePassingBg, tokens.amber),
      _ => (_gradeFailedBg, tokens.bad),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        grade.toStringAsFixed(2),
        style: TextStyle(fontWeight: FontWeight.w700, color: colors.$2),
      ),
    );
  }

  // ------------------------------------------------------------ Files

  Widget _filesPanel(BuildContext context, _StudyTokens tokens,
      {required Key key}) {
    final used = _files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
    final filtered = _files
        .where((f) => _fileFilter == 'all' || f.kind == _fileFilter)
        .where((f) => _selectedFolder == null || f.folder == _selectedFolder)
        .toList();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _studyCard(
          tokens,
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Study files',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: tokens.text)),
                    Text(
                      '${_formatBytes(used)} of 5 GB used',
                      style: TextStyle(
                          fontSize: 12.5, color: tokens.muted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                _storageBar(tokens, used),
              ],
            ),
          ),
          radius: 17,
        ),
        const SizedBox(height: AppSpacing.s12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _fileFilters.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _filterPill(
                    tokens, _fileFilters[i].$1, _fileFilters[i].$2),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Text('FOLDERS',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.muted)),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            for (var i = 0; i < _studyFolders.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _folderCard(tokens, _studyFolders[i])),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        Text('RECENT FILES',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.muted)),
        const SizedBox(height: AppSpacing.s8),
        if (filtered.isEmpty)
          _emptyCard(
            tokens,
            _selectedFolder == null
                ? 'No files yet.'
                : 'No files in $_selectedFolder yet.',
            'Add a PDF, document, slides, or image to keep it here.',
          )
        else
          for (var i = 0; i < filtered.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _fileRow(context, tokens, filtered[i]),
          ],
        // Files other users shared with this user (metadata
        // snapshots, never file bytes). The section only shows
        // while there is at least one share — an empty "Shared
        // with me" is not a state worth a permanent header.
        if (_sharedWithMe.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          Text('SHARED WITH ME',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.muted)),
          const SizedBox(height: AppSpacing.s8),
          for (var i = 0; i < _sharedWithMe.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _sharedFileRow(context, tokens, _sharedWithMe[i]),
          ],
        ],
      ],
    );
  }

  static const _fileFilters = [
    ('all', 'All'),
    ('pdf', 'PDF'),
    ('doc', 'Docs'),
    ('ppt', 'Slides'),
    ('img', 'Images'),
  ];

  /// Preview storage bar: surface-3 track, gradient fill
  /// #14532d → #34d399.
  Widget _storageBar(_StudyTokens tokens, int used) {
    final fraction = (used / _studyFilesQuotaBytes).clamp(0.0, 1.0);
    return Container(
      height: 8,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: tokens.surface3,
        borderRadius: BorderRadius.circular(999),
      ),
      child: fraction <= 0
          ? null
          : FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  gradient: LinearGradient(
                    colors: [Color(0xFF14532D), Color(0xFF34D399)],
                  ),
                ),
              ),
            ),
    );
  }

  /// Preview filter pill: inactive surface-2 + muted text, active
  /// brand fill + white text.
  Widget _filterPill(_StudyTokens tokens, String value, String label) {
    final active = _fileFilter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _fileFilter = value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? tokens.brand : tokens.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: active ? tokens.brand : tokens.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: active ? Colors.white : tokens.muted,
            ),
          ),
        ),
      ),
    );
  }

  /// Preview folder card: amber folder icon, file count below.
  /// Tapping filters the file list to that folder (tap again to
  /// clear); the active folder gets a brand border.
  Widget _folderCard(_StudyTokens tokens, String folder) {
    final active = _selectedFolder == folder;
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              setState(() => _selectedFolder = active ? null : folder),
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Icon(Icons.folder, color: tokens.amber),
                const SizedBox(height: AppSpacing.s4),
                Text(folder,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: tokens.text)),
                Text(
                  '${_files.where((f) => f.folder == folder).length} files',
                  style: TextStyle(fontSize: 12.5, color: tokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
      borderColor: active ? tokens.brand : null,
    );
  }

  /// Preview file row: tinted file-type icon tile, name, size ·
  /// folder; the three-dot menu and the delete button stay.
  /// Tapping the row (ripple, same pattern as _entryCard) opens
  /// the file details — the menu and trash buttons never open the
  /// details. The menu (⋮) offers Details, Rename file, Share
  /// this file and Delete; the trash deletes after the same
  /// confirmation as the menu's Delete.
  Widget _fileRow(BuildContext context, _StudyTokens tokens, StudyFile file) {
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showFileDetails(context, tokens, file),
          borderRadius: BorderRadius.circular(15),
          child: ListTile(
            leading: _fileTile(tokens, file.kind),
            title: Text(file.name, style: TextStyle(color: tokens.text)),
            subtitle: Text(
              '${_formatBytes(file.sizeBytes)} · ${file.folder}',
              style: TextStyle(color: tokens.muted),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'More options',
                  icon: Icon(Icons.more_vert, color: tokens.muted),
                  onPressed: () => _showFileMenu(tokens, file),
                ),
                IconButton(
                  tooltip: 'Remove file',
                  icon: Icon(Icons.delete_outline, color: tokens.muted),
                  onPressed: () => _deleteFile(file),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Three-dot menu for one file row: Details, Rename file, Share
  /// this file, Delete. An iOS action sheet (the overflow-menu
  /// pattern) — the file name is the title. The sheet pops the
  /// picked action first, then the caller runs it, so the next
  /// dialog never stacks on top of the sheet. The State's own
  /// context is used throughout (like _addFile), never a context
  /// passed in as a parameter, so the mounted guard below covers
  /// every use after an await.
  Future<void> _showFileMenu(_StudyTokens tokens, StudyFile file) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(file.name),
        message: Text(
          '${_formatBytes(file.sizeBytes)} · ${file.folder}',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('details'),
            child: const Text('Details'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('rename'),
            child: const Text('Rename file'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('share'),
            child: const Text('Share this file'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop('delete'),
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'details':
        await _showFileDetails(context, tokens, file);
      case 'rename':
        await _showRenameFileDialog(tokens, file);
      case 'share':
        await _showShareFileSheet(tokens, file);
      case 'delete':
        await _deleteFile(file);
    }
  }

  /// Delete confirmation (all users): the file's name is in the
  /// dialog and Delete is iOS red. Every delete — the trash icon
  /// and the menu's Delete — goes through here first.
  Future<bool> _confirmDeleteFile(
      BuildContext context, StudyFile file) async {
    final confirmed = await showIosAlert<bool>(
      context: context,
      title: 'Delete file?',
      message: '"${file.name}" will be deleted. This cannot be undone.',
      actions: const [
        IosAlertAction<bool>('Cancel', value: false, isDefault: true),
        IosAlertAction<bool>('Delete', value: true, isDestructive: true),
      ],
    );
    return confirmed ?? false;
  }

  /// Deletes one file after confirmation. The sender's shares of
  /// the file go with it, so a share never points at a file that
  /// no longer exists; a failed share cleanup never blocks the
  /// delete itself.
  Future<void> _deleteFile(StudyFile file) async {
    if (!await _confirmDeleteFile(context, file)) return;
    final user = widget.currentUser;
    final repo = widget.sharedFileRepository;
    setState(() => _files.removeWhere((f) => f.id == file.id));
    await _saveFiles();
    if (user != null && repo != null) {
      try {
        await repo.deleteSharesForFile(file.id, user);
      } catch (_) {
        // The file is already deleted; a failed share cleanup is
        // not fatal and never re-adds the file.
      }
    }
  }

  /// Renames one file. Same dialog shape as the stop rename in
  /// map_tab.dart (Material AlertDialog + inline error — forms
  /// stay Material, per ios_components): pre-filled name,
  /// non-empty, at most 100 characters. The kind is re-derived
  /// from the new extension when the new name has one (a ".pdf"
  /// renamed to ".docx" filters as a Document); a name with no
  /// extension keeps the old kind.
  Future<void> _showRenameFileDialog(
      _StudyTokens tokens, StudyFile file) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) =>
          _RenameFileDialog(initialName: file.name),
    );
    if (result == null || !mounted) return;
    final ext = result.contains('.') ? result.split('.').last : '';
    final renamed = file.copyWith(
      name: result,
      kind: ext.isEmpty ? null : _fileKindForExtension(ext),
    );
    setState(() {
      final index = _files.indexWhere((f) => f.id == file.id);
      if (index >= 0) _files[index] = renamed;
    });
    try {
      await _saveFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File renamed.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not rename the file.')),
      );
    }
  }

  /// Shares one file with ONE friend (user-to-user only). The
  /// recipient is picked from the user's cloud friends (accepted
  /// friend requests — the only friends with a UID a share can be
  /// addressed to). Local friends have no UID and never appear
  /// here. The shared record is the file's metadata snapshot
  /// (name, size, type, folder, added date) — never file bytes,
  /// and never a public link.
  Future<void> _showShareFileSheet(
      _StudyTokens tokens, StudyFile file) async {
    final user = widget.currentUser;
    final cloud = widget.friendCloudRepository;
    final repo = widget.sharedFileRepository;
    if (user == null) {
      await showIosMessage(
        context: context,
        title: 'Sign in to share',
        message: 'Sign in to share this file with a friend.',
      );
      return;
    }
    if (cloud == null || repo == null) {
      await showIosMessage(
        context: context,
        title: 'Sharing is not available',
        message: 'Sharing is not available right now.',
      );
      return;
    }
    final friend = await showIosSheet<CloudFriend>(
      context: context,
      builder: (sheetContext) {
        return FutureBuilder<List<CloudFriend>>(
          future: cloud.fetchFriends(user.uid),
          builder: (sheetContext, snapshot) {
            final friends = snapshot.data ?? const <CloudFriend>[];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share "${file.name}"',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a friend. Only they can see this file.',
                      style: TextStyle(fontSize: 13, color: tokens.muted),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator())
                    else if (snapshot.hasError)
                      Text(
                        'Could not load your friends. Try again later.',
                        style: TextStyle(color: tokens.muted),
                      )
                    else if (friends.isEmpty)
                      Text(
                        'No friends yet. Add a friend from the Friends tab first.',
                        style: TextStyle(color: tokens.muted),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final f in friends)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: tokens.brand,
                                  child: Text(
                                    f.displayName.isEmpty
                                        ? '?'
                                        : f.displayName[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  f.displayName,
                                  style: TextStyle(color: tokens.text),
                                ),
                                subtitle: Text(
                                  f.code,
                                  style: TextStyle(color: tokens.muted),
                                ),
                                onTap: () =>
                                    Navigator.of(sheetContext).pop(f),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (friend == null || !mounted) return;
    try {
      await repo.share(
        SharedStudyFile(
          id: const Uuid().v4(),
          fileId: file.id,
          name: file.name,
          sizeBytes: file.sizeBytes,
          kind: file.kind,
          folder: file.folder,
          added: file.added,
          fromUid: user.uid,
          fromName: user.displayName ?? user.email,
          toUid: friend.uid,
          sharedAt: DateTime.now(),
        ),
        user,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shared with ${friend.displayName}.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share this file.')),
      );
    }
  }

  /// One file shared TO this user: the sender's name is in the
  /// subtitle. Tapping opens the same details dialog (with a
  /// "Shared by" row); the trash removes the share from this
  /// user's view after confirmation — the sender's file is never
  /// touched.
  Widget _sharedFileRow(
      BuildContext context, _StudyTokens tokens, SharedStudyFile share) {
    final file = StudyFile(
      id: share.fileId,
      name: share.name,
      sizeBytes: share.sizeBytes,
      kind: share.kind,
      folder: share.folder,
      added: share.added,
    );
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showFileDetails(context, tokens, file,
              sharedBy: share.fromName),
          borderRadius: BorderRadius.circular(15),
          child: ListTile(
            leading: _fileTile(tokens, share.kind),
            title: Text(share.name, style: TextStyle(color: tokens.text)),
            subtitle: Text(
              'Shared by ${share.fromName} · ${_formatBytes(share.sizeBytes)} · ${share.folder}',
              style: TextStyle(color: tokens.muted),
            ),
            trailing: IconButton(
              tooltip: 'Remove shared file',
              icon: Icon(Icons.delete_outline, color: tokens.muted),
              onPressed: () => _removeSharedFile(share),
            ),
          ),
        ),
      ),
    );
  }

  /// Removes a file shared TO this user from their "Shared with
  /// me" list (the share record is deleted; the sender's original
  /// file is never touched). The recipient confirms first, like
  /// every other delete here.
  Future<void> _removeSharedFile(SharedStudyFile share) async {
    final confirmed = await showIosAlert<bool>(
      context: context,
      title: 'Remove shared file?',
      message:
          '"${share.name}" will be removed from Shared with me. The original file is not affected.',
      actions: const [
        IosAlertAction<bool>('Cancel', value: false, isDefault: true),
        IosAlertAction<bool>('Remove', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true || !mounted) return;
    final user = widget.currentUser;
    final repo = widget.sharedFileRepository;
    if (user == null || repo == null) return;
    try {
      await repo.delete(share.id, user);
      if (!mounted) return;
      setState(() => _sharedWithMe.removeWhere((s) => s.id == share.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove this file.')),
      );
    }
  }

  /// File details: metadata only (name, type, size, folder, added
  /// date) — files store no content, so there is nothing to open.
  /// Entrance is a fade + gentle scale whose duration follows
  /// _animDuration (zero under reduced motion).
  Future<void> _showFileDetails(
      BuildContext context, _StudyTokens tokens, StudyFile file,
      {String? sharedBy}) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close file details',
      transitionDuration: _animDuration(context),
      pageBuilder: (context, animation, secondaryAnimation) => AlertDialog(
        title: Text(file.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(tokens, 'Type', _fileKindLabel(file.kind)),
            _detailRow(tokens, 'Size', _formatBytes(file.sizeBytes)),
            _detailRow(tokens, 'Folder', file.folder),
            _detailRow(tokens, 'Added',
                '${_monthDay(file.added)}, ${file.added.year}'),
            if (sharedBy != null)
              _detailRow(tokens, 'Shared by', sharedBy),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
    );
  }

  /// One label/value row in the file details dialog.
  Widget _detailRow(_StudyTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(color: tokens.muted, fontSize: 13)),
          ),
          Expanded(
            child:
                Text(value, style: TextStyle(color: tokens.text, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// Preview file-type icon tile: 40px, tinted background, hue icon.
  Widget _fileTile(_StudyTokens tokens, String kind) {
    final (Color, Color) colors = switch (kind) {
      'pdf' => (_tilePdfBg, tokens.bad),
      'doc' => (_tileDocBg, tokens.blue),
      'ppt' => (_tilePptBg, tokens.amber),
      'img' => (_tileImgBg, tokens.ok),
      _ => (tokens.surface3, tokens.muted),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_fileKindIcon(kind), size: 20, color: colors.$2),
    );
  }

  // ------------------------------------------------------------ Notes

  Widget _notesPanel(BuildContext context, _StudyTokens tokens,
      {required Key key}) {
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
            hintStyle: TextStyle(color: tokens.faint),
            prefixIcon: Icon(Icons.search, color: tokens.faint),
            filled: true,
            fillColor: tokens.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: tokens.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: tokens.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: tokens.accent),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (filtered.isEmpty)
          _emptyCard(
            tokens,
            'No notes yet.',
            'Write your first note to see it here.',
          )
        else
          for (var i = 0; i < filtered.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _noteCard(tokens, filtered[i]),
          ],
      ],
    );
  }

  /// Preview note card: title 15px bold, 2-line clamped excerpt,
  /// footer with subject tag + date ("Nov 4"). Tapping opens
  /// NotesScreen for full CRUD.
  Widget _noteCard(_StudyTokens tokens, Note note) {
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _open(const NotesScreen()),
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
                if (note.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: tokens.muted),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (note.subject.isNotEmpty)
                      _tagPill(tokens, note.subject),
                    const Spacer(),
                    Text(
                      _monthDay(note.updated),
                      style:
                          TextStyle(fontSize: 11.5, color: tokens.faint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      radius: 17,
    );
  }

  /// Preview note tag: tinted pill in the subject's color. The
  /// color is a deterministic hash of the subject string, so a
  /// subject keeps its color across restarts.
  Widget _tagPill(_StudyTokens tokens, String subject) {
    final (Color, Color) colors = _tagColors(tokens, subject);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        subject,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: colors.$2,
        ),
      ),
    );
  }

  (Color, Color) _tagColors(_StudyTokens tokens, String subject) {
    final slot =
        subject.codeUnits.fold<int>(0, (sum, c) => sum + c) % 4;
    return switch (slot) {
      0 => (_tagBlueBg, tokens.blue),
      1 => (_tagGreenBg, tokens.ok),
      2 => (_tagAmberBg, tokens.amber),
      _ => (_tagVioletBg, tokens.violet),
    };
  }

  // ----------------------------------------------------------- Review

  Widget _reviewPanel(BuildContext context, _StudyTokens tokens,
      {required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _studySeg(
          tokens,
          options: const [('quiz', 'Quiz'), ('summary', 'Summary')],
          selected: _reviewMode,
          onSelected: (s) => setState(() => _reviewMode = s),
        ),
        const SizedBox(height: AppSpacing.s16),
        if (_reviewMode == 'quiz') ...[
          if (_quizzes.isEmpty)
            _emptyCard(
              tokens,
              'No quizzes yet.',
              'Create one with AI or add a quiz from your notes.',
            )
          else
            for (var i = 0; i < _quizzes.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _deckCard(tokens, _quizzes[i], i),
            ],
          // The preview's Review screen has no entry cards; the
          // app keeps them below the decks — they are the only way
          // to take a quiz or open flashcards.
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Pick how to study',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: tokens.text),
          ),
          const SizedBox(height: AppSpacing.s8),
          _entryCard(
            tokens,
            icon: Icons.style_outlined,
            title: 'Flashcards',
            subtitle: 'Flip through questions one at a time',
            onTap: () => _open(const NotesScreen(initialTab: 'cards')),
          ),
          const SizedBox(height: 8),
          _entryCard(
            tokens,
            icon: Icons.quiz_outlined,
            title: 'Quiz',
            subtitle: 'Answer multiple-choice, get scored',
            onTap: () => _open(const NotesScreen(initialTab: 'quizzes')),
          ),
          const SizedBox(height: 8),
          _entryCard(
            tokens,
            icon: Icons.auto_awesome_outlined,
            title: 'AI Quiz',
            subtitle:
                'Pick a PDF or photo of your notes and the app takes it from there',
            onTap: () => _open(const AiQuizGenerateScreen()),
          ),
        ] else ...[
          // The preview's Summary shows the same decks as summary
          // cards (icon + title + teaser + chevron) — not the stats
          // view the port first built here. The stats (Quizzes
          // completed/saved, Average score, Notes saved) and the
          // Recent attempts list have no counterpart anywhere in
          // the preview's Review tab, so they are gone — not moved
          // elsewhere.
          if (_quizzes.isEmpty)
            _emptyCard(
              tokens,
              'No quizzes yet.',
              'Create one with AI or add a quiz from your notes.',
            )
          else
            for (var i = 0; i < _quizzes.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _summaryCard(tokens, _quizzes[i], i),
            ],
        ],
      ],
    );
  }

  /// Preview quiz deck card: tinted gradient, MULTIPLE CHOICE
  /// label in the deck hue, title, subject (where the preview
  /// shows a date — Quiz stores no creation date), big question
  /// count in the deck hue. Deck hues cycle blue → green → amber.
  /// Tapping opens the quizzes list, as before.
  Widget _deckCard(_StudyTokens tokens, Quiz quiz, int index) {
    final hue = tokens.deckHues[index % tokens.deckHues.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              // CSS 155deg: top-left toward bottom-right.
              begin: const Alignment(-0.423, -0.906),
              end: const Alignment(0.423, 0.906),
              colors: [hue.from, hue.to],
            ),
          ),
          child: InkWell(
            onTap: () => _open(const NotesScreen(initialTab: 'quizzes')),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MULTIPLE CHOICE',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: hue.hue,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          quiz.title,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: tokens.text,
                          ),
                        ),
                        if (quiz.subject.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            quiz.subject,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tokens.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${quiz.questions.length}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: hue.hue,
                        ),
                      ),
                      Text(
                        'questions',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Preview summary card: the same deck gradient as [_deckCard]
  /// (hues cycle blue → green → amber), but a list icon + title +
  /// teaser + chevron instead of the big question count — this is
  /// what the preview's #stReviewSummary renders. The teaser is
  /// the deck's real facts (subject · question count ·
  /// difficulty): Quiz stores no prose summary/description, so
  /// no teaser text is invented. Tapping opens the quizzes list,
  /// where the deck's content lives — the app has no standalone
  /// summary reader.
  Widget _summaryCard(_StudyTokens tokens, Quiz quiz, int index) {
    final hue = tokens.deckHues[index % tokens.deckHues.length];
    final teaser =
        '${quiz.subject.isEmpty ? 'No subject' : quiz.subject} · '
        '${quiz.questions.length} questions · '
        '${quizDifficultyLabel(quiz.difficulty)}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              // CSS 155deg: top-left toward bottom-right.
              begin: const Alignment(-0.423, -0.906),
              end: const Alignment(0.423, 0.906),
              colors: [hue.from, hue.to],
            ),
          ),
          child: InkWell(
            onTap: () => _open(const NotesScreen(initialTab: 'quizzes')),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.list_alt, size: 22, color: hue.hue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quiz.title,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: tokens.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          teaser,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.chevron_right, color: tokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Study entry card (Flashcards / Quiz / AI Quiz): brand-soft
  /// icon tile, title, subtitle, chevron.
  Widget _entryCard(
    _StudyTokens tokens, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: tokens.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: tokens.text),
                      ),
                      Text(
                        subtitle,
                        style:
                            TextStyle(fontSize: 12.5, color: tokens.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: tokens.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// Rename dialog for one file. A StatefulWidget so the
/// TextEditingController is owned by the dialog itself and disposed
/// only when the dialog subtree unmounts (after the pop animation):
/// disposing it right after `await showDialog` returns is too
/// early — the route is still in the overlay animating out, its
/// dependencies change on pop, and the rebuilding TextField reads
/// the disposed controller. The error is State too, so it survives
/// the dialog rebuilding (an error held in the showDialog builder
/// closure resets on every outer rebuild).
class _RenameFileDialog extends StatefulWidget {
  const _RenameFileDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<_RenameFileDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: 'File name'),
            textCapitalization: TextCapitalization.none,
            autofocus: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();
            final problem = validateFileName(name);
            if (problem != null) {
              setState(() => _error = problem);
              return;
            }
            Navigator.pop(context, name);
          },
          child: const Text('Save'),
        ),
      ],
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
