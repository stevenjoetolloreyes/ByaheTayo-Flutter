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
//   the storage bar at 0 B of the user's plan limit. Only metadata
//   is stored, never file bytes.
// * Notes — the real notes (StudentStorage), searchable; tapping
//   one opens its full-screen view page for full CRUD.
// * Review — the real quizzes (StudentStorage) and the real study
//   entry points: Flashcards and Quiz only (AI Quiz is deleted —
//   it duplicated Quiz). Tapping Flashcards opens the dedicated
//   Flashcards Page; tapping Quiz opens the dedicated Quiz Page.
//   The old "Review Notes & Quizzes" screen (NotesScreen, with its
//   Notes/Flashcards/Quizzes tabs) is deleted. The Notes panel
//   (Study tab → Notes) is a separate, untouched panel — see below.
//   Quiz shows the deck cards; Summary shows the same decks as
//   summary cards (icon + title + teaser + chevron), exactly as the
//   preview's #stReviewSummary does. The stats view the port first
//   built in Summary (Quizzes completed/saved, Average score, Notes
//   saved, Recent attempts) has no counterpart anywhere in the
//   preview's Review tab, so it is gone — not moved elsewhere.
//   The preview's Drag & Drop and Identification modes have no
//   app equivalent and are NOT faked with a substitute.
// * AI — EstudyanteGO AI, the app's own on-device assistant (no
//   Gemini, no external API, offline, no quota). It is its own
//   tab in the bottom pill (Grades | Files | Notes | Review | AI),
//   NOT a row inside Review. The AI screen is Chat only (no Notes
//   Lab tab). It reads files on-device and its generated questions
//   land in the same deck the Flashcards and Quiz pages share.
//
// Real-data mappings for the preview's chips (the preview's ❤️ 15
// is a hardcoded sample):
// * ❤️ = the user's favorited-notes count (Note.favorite, toggled
//   in the note view page). 0 with no favorites — never invented.
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
//
// Minecraft restyle (Feature 3, Nov 10, 2026): the panels keep
// the preview's layout and the app's real data, but the surfaces
// are blocky now — 3px ink borders, hard shadows, Baloo 2
// headings, grass/dirt accents (see minecraft_theme.dart). The
// Review panel gains the preview's 'Flashcard Chests' (one chest
// per subject deck, with the REAL card count, mastered count and
// mastery %) and the 'AI Quiz Forge' card ('Forge a Quiz' opens
// the AI panel; the XP chip is the REAL max: up to 5 forged
// questions × 10 pts per correct answer). No Repeat option, no
// invented numbers, no new flows.
import 'package:file_picker/file_picker.dart';

import 'top_popup.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'app_layout.dart';
import 'app_rating.dart';
import 'estudyantego_ai.dart';
import 'friend_cloud_repository.dart';
import 'ios_components.dart';
import 'minecraft_tap_animation.dart';
import 'minecraft_theme.dart';
import 'onboarding/splash_sound.dart';
import 'onboarding/auth_service.dart';
import 'points_wallet_repository.dart';
import 'shared_study_files.dart';
import 'student/ai_screen.dart';
import 'student/flashcards_page.dart';
import 'student/note_create_sheet.dart';
import 'student/note_detail_page.dart';
import 'student/quiz_page.dart';
import 'student/student_data.dart';
import 'subscription_membership.dart';

/// Files storage is limited by the user's admin-assigned
/// subscription plan (Free 2 GB, Standard 12 GB, Pro 30 GB — see
/// [subscriptionStorageLimitBytes]). There is no fixed quota: the
/// bar and the add-flow check both read the plan limit, and usage
/// is the real local sum of the stored files' [StudyFile.sizeBytes]
/// (see [studyFilesUsedBytes]).

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
    brand: MinecraftColors.grassGreen,
    brandDeep: MinecraftColors.deepLeaves,
    brandSoft: Color.fromRGBO(88, 204, 2, 0.16),
    accent: MinecraftColors.emerald,
    gold: MinecraftColors.gold,
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
        from: Color.fromRGBO(88, 204, 2, 0.26),
        to: Color.fromRGBO(88, 204, 2, 0.08),
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
    brand: MinecraftColors.deepLeaves,
    brandDeep: MinecraftColors.grassDeep,
    brandSoft: Color.fromRGBO(47, 122, 18, 0.1),
    accent: MinecraftColors.deepLeaves,
    gold: MinecraftColors.goldDark,
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

/// Total stored-files size: the real local sum of the files'
/// [StudyFile.sizeBytes]. Never invented — an empty list is 0.
/// The Files panel and the add-flow check both use this one sum.
int studyFilesUsedBytes(List<StudyFile> files) =>
    files.fold<int>(0, (sum, f) => sum + f.sizeBytes);

/// Whether adding a file of [newFileBytes] fits within [plan]'s
/// storage limit ([subscriptionStorageLimitBytes]). The check runs
/// on every add attempt, against the real current usage
/// ([usedBytes]). Exactly at the limit fits; 1 byte over does not.
bool studyFileAddFits({
  required int usedBytes,
  required int newFileBytes,
  required SubscriptionPlanId plan,
}) => usedBytes + newFileBytes <= subscriptionStorageLimitBytes(plan);

/// Honest over-limit message for a blocked add: names the plan and
/// its real limit. Upgrades are assigned by the admin — there is no
/// self-serve upgrade in the app, so the message says to ask the
/// admin instead of offering a Subscribe action.
String studyFileOverLimitMessage({required SubscriptionPlanId plan}) {
  final p = subscriptionPlanForId(plan);
  return "You're on the ${p.name} plan (${p.storageGB} GB) and this "
      'file would take you over your limit. '
      'Ask the admin to upgrade your plan.';
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
    this.plan = SubscriptionPlanId.free,
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

  /// The user's subscription plan, from the local profile the
  /// shell loaded (a cached copy of the admin-assigned `plan`
  /// field on the user's Firestore `student_profiles` document).
  /// The shell passes it in; the tab never reads or writes the
  /// plan itself. Defaults to [SubscriptionPlanId.free] in widget
  /// tests and when signed out — a plan is never invented. Drives
  /// the Files storage bar limit and the add-flow enforcement
  /// check.
  final SubscriptionPlanId plan;

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

  /// True while the Notes + menu is open — the FAB's + rotates 45°
  /// (the preview's open-menu state).
  bool _notesMenuOpen = false;

  List<Subject> _subjects = [];
  List<GradeRecord> _grades = [];
  List<StudyFile> _files = [];
  List<Note> _notes = [];
  List<Quiz> _quizzes = [];

  /// The user's saved flashcards (for the AI chat context and the
  /// shared deck). Loaded here so the AI panel can count them.
  List<Flashcard> _cards = [];

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
    'ai' => 'EstudyanteGO AI',
    _ => 'Grades',
  };

  Future<void> _load() async {
    final subjects = await StudentStorage.loadList(StudentStorage.subjectsKey);
    final grades = await StudentStorage.loadList(StudentStorage.gradesKey);
    final files = await StudentStorage.loadList(StudentStorage.studyFilesKey);
    final notes = await StudentStorage.loadList(StudentStorage.notesKey);
    final quizzes = await StudentStorage.loadList(StudentStorage.quizzesKey);
    final cards = await StudentStorage.loadList(StudentStorage.flashcardsKey);
    final shared = await _loadSharedWithMe();
    // Semester fix (Nov 13, 2026): stored subjects from the bad
    // schedule scan carry room numbers as codes ("CC105") and
    // fragments ("Coding", "Vigan") as names, and have no
    // semester — repair them into the verified 1st-term meetings
    // (ids kept, so recorded grades stay attached) and drop
    // entries that name no real class. Persisted only when the
    // migration actually changed something, so clean data is
    // never rewritten.
    final migrated = migrateStoredSubjects(
      subjects.map(Subject.fromJson).toList(),
      grades.map(GradeRecord.fromJson).toList(),
    );
    if (migrated.changed) {
      await StudentStorage.saveList(
        StudentStorage.subjectsKey,
        migrated.subjects.map((s) => s.toJson()).toList(),
      );
      await StudentStorage.saveList(
        StudentStorage.gradesKey,
        migrated.grades.map((g) => g.toJson()).toList(),
      );
    }
    if (!mounted) return;
    setState(() {
      _subjects = migrated.subjects;
      _grades = migrated.grades;
      _files = files.map(StudyFile.fromJson).toList()
        ..sort((a, b) => b.added.compareTo(a.added));
      _notes = notes.map(Note.fromJson).toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));
      _quizzes = quizzes.map(Quiz.fromJson).toList();
      _cards = cards.map(Flashcard.fromJson).toList();
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
    StudentStorage.gradesKey,
    _grades.map((g) => g.toJson()).toList(),
  );

  Future<void> _saveFiles() => StudentStorage.saveList(
    StudentStorage.studyFilesKey,
    _files.map((f) => f.toJson()).toList(),
  );

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

  /// Subjects for the selected semester, one row per subject
  /// code: a subject has two meeting entries (e.g. CT101 Mon +
  /// Tue/Thu), but Grades shows one row per subject. The first
  /// stored meeting is the row's representative, so a grade
  /// recorded on it stays attached. Subjects with no code fall
  /// back to their id, so they are never merged together.
  /// 2nd Semester is empty until 2nd-semester subjects exist —
  /// the 1st-semester list is never copied across.
  List<Subject> get _gradeSubjects {
    final seen = <String>{};
    final out = <Subject>[];
    for (final s in _subjects) {
      if (s.semester != _semester) continue;
      final code = s.code.trim().toUpperCase();
      final key = code.isEmpty ? 'id:${s.id}' : 'code:$code';
      if (seen.add(key)) out.add(s);
    }
    return out;
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
      text: existing == null ? '' : existing.grade.toStringAsFixed(2),
    );
    final unitsController = TextEditingController(
      text: existing == null ? '3' : '${existing.units}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add grade' : 'Edit grade'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: gradeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
                TopPopup.show(
                  context,
                  message: 'Enter a grade from 1.00 to 5.00.',
                );
                return;
              }
              if (units == null || units < 1 || units > 12) {
                TopPopup.show(context, message: 'Enter units from 1 to 12.');
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
        (g) => g.subjectId == subject.id && g.semester == _semester,
      );
      _grades.add(
        GradeRecord(
          subjectId: subject.id,
          grade: grade,
          units: units,
          semester: _semester,
        ),
      );
    });
    await _saveGrades();
    if (mounted) {
      TopPopup.show(context, message: 'Grade saved.');
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
    final ext = picked.name.contains('.') ? picked.name.split('.').last : '';
    // file_picker 13 reports size via length() (async) with a
    // sync fallback; unknown size stores as 0, never guessed.
    final sizeBytes = await picked.length() ?? picked.lengthSync() ?? 0;
    if (!mounted) return;
    // Storage enforcement (admin-assigned plan): the add is
    // checked against the real current usage on EVERY attempt.
    // Over the plan limit the file is NOT saved and the user gets
    // an honest message naming the plan and its limit, plus the
    // admin-upgrade prompt — never a self-serve Subscribe offer.
    if (!studyFileAddFits(
      usedBytes: studyFilesUsedBytes(_files),
      newFileBytes: sizeBytes,
      plan: widget.plan,
    )) {
      TopPopup.show(
        context,
        title: 'Storage limit reached',
        message: studyFileOverLimitMessage(plan: widget.plan),
      );
      return;
    }
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
      TopPopup.show(context, message: 'Added ${picked.name} to $folder.');
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // Notes / quizzes / attempts may have changed while the screen
    // was open — reload so the tab never shows stale counts.
    await _load();
  }

  /// Opening a quiz / flashcard / AI-quiz flow counts as "starting
  /// a review" for the app-rating prompt (a real user action).
  Future<void> _openReview(Widget screen) async {
    AppRatingTracker.instance.recordAction(AppRatingAction.startedReview);
    await _open(screen);
  }

  /// The + FAB goes straight to the panel's real create flow (the
  /// preview's "What do you want to make?" sheet has no app
  /// equivalent). Grades has no "add subject" flow inside Study —
  /// subjects come from the Student tab — so its FAB opens the
  /// grade form for the first subject with no grade this semester.
  /// Review opens the Quiz Page (AI Quiz is deleted). The AI panel
  /// has no FAB — its chat has its own input and + attach menu.
  Future<void> _onFab() async {
    if (_panel == 'files') {
      await _addFile();
    } else if (_panel == 'notes') {
      await _openNoteCreateMenu();
    } else if (_panel == 'review') {
      await _openReview(QuizPage(walletController: widget.walletController));
    } else if (_panel == 'ai') {
      return;
    } else {
      await _fabGrades();
    }
  }

  /// The Notes + menu (Nov 8): Add notes / Camera / Photos /
  /// Videos / Files. The created note is saved here — the Study tab
  /// owns the notes list; the menu only returns the note.
  Future<void> _openNoteCreateMenu() async {
    setState(() => _notesMenuOpen = true);
    final created = await showNoteCreateMenu(context);
    if (!mounted) return;
    setState(() => _notesMenuOpen = false);
    if (created == null) return;
    setState(() => _notes.insert(0, created));
    await _saveNotes();
    if (mounted) {
      TopPopup.show(context, message: 'Note saved!');
    }
  }

  /// Persist the notes list (same shape as the note view page).
  Future<void> _saveNotes() => StudentStorage.saveList(
    StudentStorage.notesKey,
    _notes.map((n) => n.toJson()).toList(),
  );

  /// Open a note in its full-screen view page; when the page
  /// returns an edited note, replace it in the list and save.
  Future<void> _openNoteDetail(Note note) async {
    // Rating prompt (Nov 9): opening a note to read it is a real
    // action — opening notes.
    AppRatingTracker.instance.recordAction(AppRatingAction.openedNotes);
    final updated = await Navigator.of(
      context,
    ).push<Note>(MaterialPageRoute(builder: (_) => NoteDetailPage(note: note)));
    if (updated == null || !mounted) return;
    setState(() {
      final idx = _notes.indexWhere((n) => n.id == updated.id);
      if (idx >= 0) {
        _notes[idx] = updated;
      } else {
        _notes.insert(0, updated);
      }
    });
    await _saveNotes();
  }

  Future<void> _fabGrades() async {
    final gradeSubjects = _gradeSubjects;
    if (gradeSubjects.isEmpty) {
      if (!mounted) return;
      TopPopup.show(
        context,
        message:
            'Add subjects from the Student tab → Classes & Timetable first.',
      );
      return;
    }
    final ungraded = gradeSubjects.where((s) => _gradeFor(s.id) == null);
    await _openGradeForm(
      ungraded.isEmpty ? gradeSubjects.first : ungraded.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _StudyTokens.of(context);
    // The AI panel is a chat, not a scrolling list: its messages
    // scroll inside the panel while the quick replies + input stay
    // pinned above the bottom pill nav, so it gets a Column
    // layout instead of the ListView the other panels share. The
    // FAB is hidden here — the chat has its own input and +
    // attach menu.
    if (_panel == 'ai') {
      return Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _panelHeader(tokens),
              ),
              const SizedBox(height: AppSpacing.s16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _aiPanel(tokens),
                ),
              ),
              // Clears the floating bottom pill nav.
              const SizedBox(height: 84),
            ],
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
                'files' => _filesPanel(
                  context,
                  tokens,
                  key: const ValueKey('files'),
                ),
                'notes' => _notesPanel(
                  context,
                  tokens,
                  key: const ValueKey('notes'),
                ),
                'review' => _reviewPanel(
                  context,
                  tokens,
                  key: const ValueKey('review'),
                ),
                _ => _gradesPanel(
                  context,
                  tokens,
                  key: const ValueKey('grades'),
                ),
              },
            ),
          ],
        ),
        // No FAB on the Review panel (Nov 9): the Review screen
        // (Quiz tab + Summary tab) has no floating + button — the
        // deck list, Flashcards/Quiz rows, and bottom nav stay.
        if (_panel != 'review')
          Positioned(right: 18, bottom: 84, child: _fab(tokens)),
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

  /// The EstudyanteGO AI chat panel. Questions the AI generates
  /// from a file land in the SAME deck the Flashcards and Quiz
  /// pages share: they are saved here as a new quiz named after
  /// the file, so the Review panel shows them at once.
  Widget _aiPanel(_StudyTokens tokens) {
    return AiChatPanel(
      notes: _notes,
      quizzes: _quizzes,
      cards: _cardsForAi(),
      subjects: _subjects.map((s) => s.name).toList(),
      points: _points,
      onQuestionsGenerated: (questions, sourceName) async {
        final baseName = sourceName.contains('.')
            ? sourceName.substring(0, sourceName.lastIndexOf('.'))
            : sourceName;
        setState(() {
          _quizzes.insert(
            0,
            Quiz(
              id: newId(),
              title: baseName,
              subject: '',
              timeLimitSec: 0,
              questions: questions,
            ),
          );
        });
        await _saveQuizzes();
      },
    );
  }

  /// Flashcards for the AI chat context: the user's real cards.
  /// (The sample deck is a display-only fallback in the
  /// Flashcards page, not part of the AI's working data.)
  List<Flashcard> _cardsForAi() => _cards;

  /// Flashcard decks grouped by subject, in first-appearance
  /// order (Minecraft restyle, Feature 3): the preview's
  /// 'Flashcard Chests' are decks saved per subject, and the real
  /// cards already carry a subject — so the decks are the live
  /// groups, never invented, never seeded. Cards with no subject
  /// group under 'No subject'.
  List<({String subject, List<Flashcard> cards})> get _flashcardDecks {
    final order = <String>[];
    final bySubject = <String, List<Flashcard>>{};
    for (final card in _cards) {
      final subject = card.subject.isEmpty ? 'No subject' : card.subject;
      if (!bySubject.containsKey(subject)) {
        bySubject[subject] = [];
        order.add(subject);
      }
      bySubject[subject]!.add(card);
    }
    return [for (final s in order) (subject: s, cards: bySubject[s]!)];
  }

  /// Cards in [cards] marked 'remembered' in flip mode — the
  /// live mastery count for a chest card.
  static int _deckMastered(List<Flashcard> cards) =>
      cards.where((c) => c.studyStatus == 'remembered').length;

  /// The AI Quiz Forge's XP chip, derived from the app's own
  /// numbers — never the preview's sample: the forge crafts at
  /// most [kAiMaxQuestionsPerSet] questions and a correct answer
  /// earns [kQuizPointsPerCorrect] points, so a perfect forged
  /// quiz is worth at most this much XP.
  static int get _forgeMaxXp => kAiMaxQuestionsPerSet * kQuizPointsPerCorrect;

  Future<void> _saveQuizzes() => StudentStorage.saveList(
    StudentStorage.quizzesKey,
    _quizzes.map((q) => q.toJson()).toList(),
  );

  // ------------------------------------------------------- shared bits

  /// Minecraft header row (Feature 3): Baloo 2 panel title left,
  /// blocky ❤️ / ⭐ chips right.
  Widget _panelHeader(_StudyTokens tokens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _panelTitle,
            style: MinecraftText.heading(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 30,
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
          background: MinecraftColors.gold.withValues(alpha: 0.25),
          label: '$_points pts',
          textColor: tokens.accent,
        ),
      ],
    );
  }

  /// Blocky chip (Feature 3): 2.5px ink border, 8px corners,
  /// Baloo 2 label.
  Widget _chip({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required Color background,
    required String label,
    required Color textColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.chipBorderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: MinecraftText.button(color: textColor, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Blocky surface card (Minecraft restyle, Feature 3): 3px ink
  /// border + hard shadow in light, 1px dark border in dark
  /// ([MinecraftDecorations.blockCardFor]) — the same shell the
  /// Student tab's hub cards use, so the two tabs match. The
  /// [radius] and [borderColor] overrides stay for callers that
  /// need them (folder active state).
  Widget _studyCard(
    _StudyTokens tokens,
    Widget child, {
    double radius = 15,
    EdgeInsetsGeometry? padding,
    Color? borderColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration:
          MinecraftDecorations.blockCardFor(
            Theme.of(context).brightness,
            color: borderColor == null
                ? null
                : (isDark ? MinecraftColors.darkCard : Colors.white),
          ).copyWith(
            borderRadius: BorderRadius.circular(radius),
            border: borderColor == null
                ? null
                : Border.all(
                    color: borderColor,
                    width: MinecraftShapes.cardBorderWidth,
                  ),
          ),
      padding: padding,
      child: child,
    );
  }

  /// Honest empty-state card (same blocky surface language).
  Widget _emptyCard(_StudyTokens tokens, String title, String subtitle) {
    return _studyCard(
      tokens,
      ListTile(
        title: Text(
          title,
          style: MinecraftText.title(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: MinecraftText.body(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// Blocky + FAB (Feature 3): 58px grass block, 3.5px ink
  /// border, hard shadow. The + still rotates 45° while the
  /// Notes menu is open.
  Widget _fab(_StudyTokens tokens) {
    return MinecraftFabButton(
      tooltip: 'Add',
      onPressed: _onFab,
      child: AnimatedRotation(
        turns: _notesMenuOpen ? 0.125 : 0,
        duration: const Duration(milliseconds: 200),
        child: const Icon(Icons.add, size: 24, color: Colors.white),
      ),
    );
  }

  /// Blocky bottom pill nav (Feature 3): 3px ink border + hard
  /// shadow, grass-green active button, Baloo 2 labels. Order:
  /// Grades | Files | Notes | Review | AI. The five buttons still
  /// share the pill width equally (Expanded) so the labels fit
  /// on narrow phones.
  Widget _bottomNav(_StudyTokens tokens) {
    const entries = [
      ('grades', 'Grades', Icons.workspace_premium_outlined),
      ('files', 'Files', Icons.folder_outlined),
      ('notes', 'Notes', Icons.note_alt_outlined),
      ('review', 'Review', Icons.help_outline),
      ('ai', 'AI', Icons.auto_awesome_outlined),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? MinecraftColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.cardBorderWidth,
        ),
        boxShadow: isDark ? null : const [MinecraftShapes.cardShadow],
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

  /// Blocky nav button: 44px tall, Baloo 2 13px, icon 15px;
  /// active gets the grass fill + white text.
  Widget _navButton(
    _StudyTokens tokens, {
    required String value,
    required String label,
    required IconData icon,
    required bool active,
  }) {
    final color = active
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('study-nav-$value'),
        onTap: () => setState(() => _panel = value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: active ? 14 : 10),
          decoration: BoxDecoration(
            color: active ? MinecraftColors.grassGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: active
                ? Border.all(
                    color: MinecraftColors.border,
                    width: MinecraftShapes.chipBorderWidth,
                  )
                : null,
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
                  style: MinecraftText.button(color: color, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Blocky segmented control (Feature 3): 3px ink border,
  /// 14px corners; the active segment is a grass fill with white
  /// Baloo 2 text.
  Widget _studySeg(
    _StudyTokens tokens, {
    required List<(String, String)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? MinecraftColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
        ),
        boxShadow: isDark ? null : const [MinecraftShapes.cardShadow],
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
                      vertical: 9,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: options[i].$1 == selected
                          ? MinecraftColors.grassGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      options[i].$2,
                      textAlign: TextAlign.center,
                      style: MinecraftText.button(
                        color: options[i].$1 == selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
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

  Widget _gradesPanel(
    BuildContext context,
    _StudyTokens tokens, {
    required Key key,
  }) {
    final gwa = _gwa;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your standing for A.Y. 2026–2027, computed from the subjects below.',
          style: MinecraftText.body(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? MinecraftColors.darkBorder
                  : MinecraftColors.border,
              width: Theme.of(context).brightness == Brightness.dark
                  ? 1
                  : MinecraftShapes.cardBorderWidth,
            ),
            boxShadow: Theme.of(context).brightness == Brightness.dark
                ? null
                : const [MinecraftShapes.cardShadow],
            gradient: const LinearGradient(
              // CSS 140deg: top-left toward bottom-right.
              begin: Alignment(-0.643, -0.766),
              end: Alignment(0.643, 0.766),
              stops: [0.0, 0.55, 1.0],
              colors: [Color(0xFF14532D), Color(0xFF16A34A), Color(0xFF34D399)],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GENERAL WEIGHTED AVERAGE',
                style: MinecraftText.button(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.s8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    gwa == null ? '—' : gwa.toStringAsFixed(2),
                    style: MinecraftText.heading(
                      color: Colors.white,
                      fontSize: 44,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gwa == null ? '—' : _gwaStanding(gwa),
                          style: MinecraftText.title(color: Colors.white),
                        ),
                        Text(
                          gwa == null
                              ? '—'
                              : '$_gwaUnits units · $_gradedCount '
                                    'graded',
                          style: MinecraftText.body(color: Colors.white),
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
        else if (_gradeSubjects.isEmpty)
          _emptyCard(
            tokens,
            'No subjects yet for ${_semester == 1 ? '1st' : '2nd'} Semester.',
            'Add ${_semester == 1 ? '1st' : '2nd'} Semester subjects from the Student tab → Classes & Timetable.',
          )
        else
          for (var i = 0; i < _gradeSubjects.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _subjectRow(tokens, _gradeSubjects[i]),
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

  /// Blocky subject row (Feature 3): Baloo 2 code + name, the
  /// grade as a blocky band-colored pill; Add grade / Edit stays.
  Widget _subjectRow(_StudyTokens tokens, Subject subject) {
    final grade = _gradeFor(subject.id);
    return _studyCard(
      tokens,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subject.code.isNotEmpty)
                    Text(
                      subject.code,
                      style: MinecraftText.button(
                        color: tokens.blue,
                        fontSize: 12,
                      ),
                    ),
                  Text(
                    subject.name,
                    style: MinecraftText.title(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (grade == null)
              Text(
                'No grade yet',
                style: MinecraftText.button(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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

  /// Blocky grade pill (Feature 3): band-tinted background,
  /// band-hue Baloo 2 text, 2.5px ink border.
  Widget _gradePill(_StudyTokens tokens, double grade) {
    final (Color, Color) colors = switch (_gwaStanding(grade)) {
      'Excellent' => (_gradeExcellentBg, tokens.ok),
      'Good' => (_gradeGoodBg, tokens.blue),
      'Passing' => (_gradePassingBg, tokens.amber),
      _ => (_gradeFailedBg, tokens.bad),
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.chipBorderWidth,
        ),
      ),
      child: Text(
        grade.toStringAsFixed(2),
        style: MinecraftText.button(color: colors.$2),
      ),
    );
  }

  // ------------------------------------------------------------ Files

  Widget _filesPanel(
    BuildContext context,
    _StudyTokens tokens, {
    required Key key,
  }) {
    final used = studyFilesUsedBytes(_files);
    final plan = subscriptionPlanForId(widget.plan);
    final limitBytes = subscriptionStorageLimitBytes(widget.plan);
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
                    Text(
                      'Study files',
                      style: MinecraftText.title(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${_formatBytes(used)} of ${plan.storageGB} GB used — ${plan.name} plan',
                      style: MinecraftText.caption(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                _storageBar(tokens, used, limitBytes),
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
                _filterPill(tokens, _fileFilters[i].$1, _fileFilters[i].$2),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(
          'FOLDERS',
          style: MinecraftText.button(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
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
        Text(
          'RECENT FILES',
          style: MinecraftText.button(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
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
          Text(
            'SHARED WITH ME',
            style: MinecraftText.button(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
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

  /// Blocky storage bar (Feature 3): cream track with a 3px ink
  /// border, grass gradient fill. [limitBytes] is the user's real
  /// plan limit — the fill fraction is real usage over that limit.
  Widget _storageBar(_StudyTokens tokens, int used, int limitBytes) {
    final fraction = limitBytes <= 0
        ? 0.0
        : (used / limitBytes).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 14,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: MinecraftColors.cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.cardBorderWidth,
        ),
      ),
      child: fraction <= 0
          ? null
          : FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                  gradient: LinearGradient(
                    colors: [Color(0xFF14532D), Color(0xFF34D399)],
                  ),
                ),
              ),
            ),
    );
  }

  /// Blocky filter pill (Feature 3): inactive white/dark + ink
  /// border + muted Baloo 2 text, active grass fill + white text.
  Widget _filterPill(_StudyTokens tokens, String value, String label) {
    final active = _fileFilter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _fileFilter = value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? MinecraftColors.grassGreen
                : (isDark ? MinecraftColors.darkCard : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? MinecraftColors.border
                  : (isDark
                        ? MinecraftColors.darkBorder
                        : MinecraftColors.border),
              width: MinecraftShapes.chipBorderWidth,
            ),
          ),
          child: Text(
            label,
            style: MinecraftText.button(
              color: active
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  /// Blocky folder card (Feature 3): grass folder badge, Baloo 2
  /// name, file count below. Tapping filters the file list to
  /// that folder (tap again to clear); the active folder gets a
  /// grass border.
  Widget _folderCard(_StudyTokens tokens, String folder) {
    final active = _selectedFolder == folder;
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedFolder = active ? null : folder),
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const MinecraftIconBadge(
                  icon: Icons.folder,
                  backgroundColor: MinecraftColors.gold,
                  iconColor: MinecraftColors.ink,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  folder,
                  style: MinecraftText.button(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${_files.where((f) => f.folder == folder).length} files',
                  style: MinecraftText.caption(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      borderColor: active ? MinecraftColors.grassGreen : null,
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
            title: Text(
              file.name,
              style: MinecraftText.title(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              '${_formatBytes(file.sizeBytes)} · ${file.folder}',
              style: MinecraftText.body(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
        message: Text('${_formatBytes(file.sizeBytes)} · ${file.folder}'),
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
  Future<bool> _confirmDeleteFile(BuildContext context, StudyFile file) async {
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
    _StudyTokens tokens,
    StudyFile file,
  ) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => _RenameFileDialog(initialName: file.name),
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
      TopPopup.show(context, message: 'File renamed.');
    } catch (_) {
      if (!mounted) return;
      TopPopup.show(context, message: 'Could not rename the file.');
    }
  }

  /// Shares one file with ONE friend (user-to-user only). The
  /// recipient is picked from the user's cloud friends (accepted
  /// friend requests — the only friends with a UID a share can be
  /// addressed to). Local friends have no UID and never appear
  /// here. The shared record is the file's metadata snapshot
  /// (name, size, type, folder, added date) — never file bytes,
  /// and never a public link.
  Future<void> _showShareFileSheet(_StudyTokens tokens, StudyFile file) async {
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
                                onTap: () => Navigator.of(sheetContext).pop(f),
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
      TopPopup.show(context, message: 'Shared with ${friend.displayName}.');
    } catch (_) {
      if (!mounted) return;
      TopPopup.show(context, message: 'Could not share this file.');
    }
  }

  /// One file shared TO this user: the sender's name is in the
  /// subtitle. Tapping opens the same details dialog (with a
  /// "Shared by" row); the trash removes the share from this
  /// user's view after confirmation — the sender's file is never
  /// touched.
  Widget _sharedFileRow(
    BuildContext context,
    _StudyTokens tokens,
    SharedStudyFile share,
  ) {
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
          onTap: () =>
              _showFileDetails(context, tokens, file, sharedBy: share.fromName),
          borderRadius: BorderRadius.circular(15),
          child: ListTile(
            leading: _fileTile(tokens, share.kind),
            title: Text(
              share.name,
              style: MinecraftText.title(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              'Shared by ${share.fromName} · ${_formatBytes(share.sizeBytes)} · ${share.folder}',
              style: MinecraftText.body(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
      TopPopup.show(context, message: 'Could not remove this file.');
    }
  }

  /// File details: metadata only (name, type, size, folder, added
  /// date) — files store no content, so there is nothing to open.
  /// Entrance is a fade + gentle scale whose duration follows
  /// _animDuration (zero under reduced motion).
  Future<void> _showFileDetails(
    BuildContext context,
    _StudyTokens tokens,
    StudyFile file, {
    String? sharedBy,
  }) {
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
            _detailRow(
              tokens,
              'Added',
              '${_monthDay(file.added)}, ${file.added.year}',
            ),
            if (sharedBy != null) _detailRow(tokens, 'Shared by', sharedBy),
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
            child: Text(
              label,
              style: TextStyle(color: tokens.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: tokens.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Blocky file-type icon tile (Feature 3): 40px, tinted
  /// background, 2.5px ink border, hue icon.
  Widget _fileTile(_StudyTokens tokens, String kind) {
    final (Color, Color) colors = switch (kind) {
      'pdf' => (_tilePdfBg, tokens.bad),
      'doc' => (_tileDocBg, tokens.blue),
      'ppt' => (_tilePptBg, tokens.amber),
      'img' => (_tileImgBg, tokens.ok),
      _ => (tokens.surface3, tokens.muted),
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.chipBorderWidth,
        ),
      ),
      child: Icon(_fileKindIcon(kind), size: 20, color: colors.$2),
    );
  }

  // ------------------------------------------------------------ Notes

  Widget _notesPanel(
    BuildContext context,
    _StudyTokens tokens, {
    required Key key,
  }) {
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
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? MinecraftColors.darkBorder
                    : MinecraftColors.border,
                width: MinecraftShapes.cardBorderWidth,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? MinecraftColors.darkBorder
                    : MinecraftColors.border,
                width: MinecraftShapes.cardBorderWidth,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: MinecraftColors.grassGreen,
                width: MinecraftShapes.cardBorderWidth,
              ),
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

  /// Blocky note card (Feature 3): Baloo 2 title, 2-line clamped
  /// excerpt, footer with subject tag + date ("Nov 4"). Tapping
  /// opens the note's full-screen view page (Nov 8).
  Widget _noteCard(_StudyTokens tokens, Note note) {
    return _studyCard(
      tokens,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openNoteDetail(note),
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: MinecraftText.title(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (note.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MinecraftText.body(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (note.subject.isNotEmpty) _tagPill(tokens, note.subject),
                    const Spacer(),
                    Text(
                      _monthDay(note.updated),
                      style: MinecraftText.caption(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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

  /// Blocky note tag (Feature 3): tinted pill in the subject's
  /// color with a 2.5px ink border. The color is a deterministic
  /// hash of the subject string, so a subject keeps its color
  /// across restarts.
  Widget _tagPill(_StudyTokens tokens, String subject) {
    final (Color, Color) colors = _tagColors(tokens, subject);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.chipBorderWidth,
        ),
      ),
      child: Text(
        subject,
        style: MinecraftText.button(color: colors.$2, fontSize: 12),
      ),
    );
  }

  (Color, Color) _tagColors(_StudyTokens tokens, String subject) {
    final slot = subject.codeUnits.fold<int>(0, (sum, c) => sum + c) % 4;
    return switch (slot) {
      0 => (_tagBlueBg, tokens.blue),
      1 => (_tagGreenBg, tokens.ok),
      2 => (_tagAmberBg, tokens.amber),
      _ => (_tagVioletBg, tokens.violet),
    };
  }

  // ----------------------------------------------------------- Review

  Widget _reviewPanel(
    BuildContext context,
    _StudyTokens tokens, {
    required Key key,
  }) {
    final decks = _flashcardDecks;
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
            _emptyCard(tokens, 'No quizzes yet.', 'Add a quiz from your notes.')
          else
            for (var i = 0; i < _quizzes.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _deckCard(tokens, _quizzes[i], i),
            ],
          // Flashcard Chests (Minecraft restyle, Feature 3): the
          // preview's deck list — one chest per subject deck with
          // the REAL card count, mastered count, and mastery %.
          // Tapping a chest opens the Flashcards page. With no
          // cards yet, a single chest keeps the entry point.
          const SizedBox(height: AppSpacing.s16),
          const MinecraftSectionHeader(
            icon: Icons.inventory_2_outlined,
            title: 'Flashcard Chests',
            iconColor: MinecraftColors.gold,
          ),
          const SizedBox(height: AppSpacing.s8),
          if (decks.isEmpty)
            _flashcardChestCard(
              tokens,
              title: 'Flashcards',
              details: 'No flashcards yet — add your first card.',
              total: 0,
              mastered: 0,
            )
          else
            for (var i = 0; i < decks.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _flashcardChestCard(
                tokens,
                title: decks[i].subject,
                details:
                    '${decks[i].cards.length} card${decks[i].cards.length == 1 ? '' : 's'} · ${_deckMastered(decks[i].cards)} mastered',
                total: decks[i].cards.length,
                mastered: _deckMastered(decks[i].cards),
                index: i,
              ),
            ],
          // AI Quiz Forge (Minecraft restyle, Feature 3): the
          // preview's forge card. The button switches to the AI
          // panel, where the generation lives ('Make a quiz from
          // my notes' / file attach) — the same flow, no new
          // feature. The XP chip is the REAL max (see
          // [_forgeMaxXp]), never the preview's sample.
          const SizedBox(height: AppSpacing.s16),
          const MinecraftSectionHeader(
            icon: Icons.handyman_outlined,
            title: 'AI Quiz Forge',
            iconColor: MinecraftColors.purple,
          ),
          const SizedBox(height: AppSpacing.s8),
          _forgeCard(tokens),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Pick how to study',
            style: MinecraftText.heading(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          _entryCard(
            tokens,
            icon: Icons.quiz_outlined,
            title: 'Quiz',
            subtitle: 'Answer multiple-choice, get scored',
            onTap: () => _openReview(
              QuizPage(walletController: widget.walletController),
            ),
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
            _emptyCard(tokens, 'No quizzes yet.', 'Add a quiz from your notes.')
          else
            for (var i = 0; i < _quizzes.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _summaryCard(tokens, _quizzes[i], i),
            ],
        ],
      ],
    );
  }

  /// One flashcard chest (Feature 3): the preview's deck card —
  /// a box / box-open badge by mastery, the subject as the deck
  /// title, the REAL card count and mastered count, and the REAL
  /// mastery % chip. Tapping opens the Flashcards page. The
  /// badge opens (gold) at 50% mastery or more — the preview's
  /// 75% deck is open, its 29% and 22% decks are closed — and
  /// stays a closed box below that.
  Widget _flashcardChestCard(
    _StudyTokens tokens, {
    required String title,
    required String details,
    required int total,
    required int mastered,
    int? index,
  }) {
    final pct = total == 0 ? 0 : (mastered * 100 / total).round();
    final open = total > 0 && pct >= 50;
    return MinecraftQuestCard(
      key: index == null ? null : Key('flashcard-chest-$index'),
      badgeIcon: open ? Icons.inbox : Icons.inventory_2,
      badgeColor: open ? MinecraftColors.gold : MinecraftColors.purple,
      badgeIconColor: open ? MinecraftColors.ink : Colors.white,
      title: title,
      details: details,
      chip: MinecraftStatusChip('$pct%'),
      onTap: () => _openReview(const FlashcardsPage()),
    );
  }

  /// The AI Quiz Forge card (Feature 3): the preview's forge —
  /// 'Turn notes into a quiz', the real description, and a
  /// 'Forge a Quiz' button with the REAL max XP chip
  /// ([_forgeMaxXp]). Tapping switches to the AI panel, where
  /// the forge lives — the same generation flow, no new feature.
  Widget _forgeCard(_StudyTokens tokens) {
    return MinecraftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MinecraftIconBadge(
                icon: Icons.handyman_outlined,
                backgroundColor: MinecraftColors.purple,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Turn notes into a quiz',
                  style: MinecraftText.title(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              MinecraftStatusChip('+$_forgeMaxXp XP'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the AI or attach a file — the forge crafts up to $kAiMaxQuestionsPerSet questions with explanations from your own material.',
            style: MinecraftText.body(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: MinecraftBlockButton(
              label: 'Forge a Quiz',
              icon: Icons.handyman_outlined,
              // Feature 6: forging a quiz plays the forge clanks.
              sound: MinecraftSoundKind.forge,
              onPressed: () => setState(() => _panel = 'ai'),
            ),
          ),
        ],
      ),
    );
  }

  /// Blocky quiz deck card (Feature 3): tinted gradient, 3px ink
  /// border, hard shadow, Baloo 2 title and big question count.
  /// MULTIPLE CHOICE label in the deck hue, title, subject (where
  /// the preview shows a date — Quiz stores no creation date),
  /// big question count in the deck hue. Deck hues cycle blue →
  /// green → amber. Tapping opens the quizzes list, as before.
  Widget _deckCard(_StudyTokens tokens, Quiz quiz, int index) {
    final hue = tokens.deckHues[index % tokens.deckHues.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? MinecraftColors.darkBorder
                  : MinecraftColors.border,
              width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
            ),
            borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
            gradient: LinearGradient(
              // CSS 155deg: top-left toward bottom-right.
              begin: const Alignment(-0.423, -0.906),
              end: const Alignment(0.423, 0.906),
              colors: [hue.from, hue.to],
            ),
            boxShadow: isDark ? null : const [MinecraftShapes.cardShadow],
          ),
          child: InkWell(
            onTap: () => _openReview(
              QuizPage(walletController: widget.walletController),
            ),
            borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
            // Feature 5: tap squash + ring/bits. The wrapper only
            // observes the pointer; the InkWell still owns the tap.
            child: MinecraftTapAnimation(
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
                            style: MinecraftText.button(
                              color: hue.hue,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            quiz.title,
                            style: MinecraftText.title(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          if (quiz.subject.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              quiz.subject,
                              style: MinecraftText.body(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                          style: MinecraftText.heading(
                            color: hue.hue,
                            fontSize: 32,
                          ),
                        ),
                        Text(
                          'questions',
                          style: MinecraftText.caption(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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
      ),
    );
  }

  /// Blocky summary card (Feature 3): the same deck gradient as
  /// [_deckCard] (hues cycle blue → green → amber), 3px ink
  /// border, hard shadow, Baloo 2 title — but a list icon + title
  /// + teaser + chevron instead of the big question count. The
  /// teaser is the deck's real facts (subject · question count ·
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? MinecraftColors.darkBorder
                  : MinecraftColors.border,
              width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
            ),
            borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
            gradient: LinearGradient(
              // CSS 155deg: top-left toward bottom-right.
              begin: const Alignment(-0.423, -0.906),
              end: const Alignment(0.423, 0.906),
              colors: [hue.from, hue.to],
            ),
            boxShadow: isDark ? null : const [MinecraftShapes.cardShadow],
          ),
          child: InkWell(
            onTap: () => _openReview(
              QuizPage(walletController: widget.walletController),
            ),
            borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
            // Feature 5: tap squash + ring/bits. The wrapper only
            // observes the pointer; the InkWell still owns the tap.
            child: MinecraftTapAnimation(
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
                            style: MinecraftText.title(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            teaser,
                            style: MinecraftText.body(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
      ),
    );
  }

  /// Blocky study entry card (Feature 3): grass icon badge,
  /// Baloo 2 title, subtitle, chevron.
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
                MinecraftIconBadge(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: MinecraftText.title(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: MinecraftText.body(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
