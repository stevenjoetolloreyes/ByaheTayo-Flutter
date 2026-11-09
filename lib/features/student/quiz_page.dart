// Quiz Page — one of the two dedicated Review pages.
//
// The old "Review Notes & Quizzes" screen (NotesScreen) is gone.
// This page owns quizzes only: the quiz list, taking a quiz
// (multiple-choice with right/wrong feedback and a scored results
// screen that awards 10 pts per correct answer to the header
// chips), quiz history, and the + menu.
//
// The + is an ICON ONLY (floating circular button, bottom right —
// no label). Tapping it expands a floating menu with two buttons:
// "Add Question manually" (a form: question, choices A–D, correct
// answer) and "Files" (the on-device AI: pick a PDF or photo of
// notes, the AI reads it and generates questions; a "reading your
// file" state shows first, then the questions are added, the
// count updates, and a confirmation card names the file). The +
// rotates to a close icon while the menu is open. The control
// hides during a quiz and on the results screen (those are
// separate pushed screens, so the FAB is not there).
//
// Data is the user's own saved quizzes (StudentStorage.quizzesKey).
// While the user has none, the built-in "Computer Basics" sample
// quiz shows instead, clearly labelled "Sample" — it is never
// written to storage, and it disappears as soon as the user adds
// their first real quiz. Taking the sample quiz earns points but
// saves no attempt (the quiz itself is not saved).
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ai_quiz_service.dart';
import '../estudyantego_ai.dart';
import '../points_wallet_repository.dart';
import '../top_popup.dart';
import '../app_layout.dart';
import '../ios_components.dart';
import 'note_extract_service.dart';
import 'student_data.dart';

/// Points earned per correct quiz answer.
const int kQuizPointsPerCorrect = 10;

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    this.walletController,
    this.aiGenerator,
    this.extractor,
  });

  /// The shell's points wallet, so a finished quiz adds points
  /// to the header chips. Null in widget tests — points are then
  /// simply not awarded.
  final PointsWalletController? walletController;

  /// On-device AI (injectable so tests can use a fake).
  final AiQuizGenerator? aiGenerator;

  /// File text extractor (injectable so tests run without native
  /// plugins).
  final NoteExtractService? extractor;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  List<Quiz> _quizzes = [];
  List<QuizAttempt> _attempts = [];
  bool _loaded = false;

  /// True while the + floating menu is open — the + rotates 45°.
  bool _menuOpen = false;

  /// The file the AI just read, for the confirmation card.
  String? _lastGeneratedFile;
  int _lastGeneratedCount = 0;

  AiQuizGenerator get _ai =>
      widget.aiGenerator ?? OnDeviceAiQuizGenerator();

  NoteExtractService get _extractor =>
      widget.extractor ?? NoteExtractService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quizzes =
        await StudentStorage.loadList(StudentStorage.quizzesKey);
    final attempts =
        await StudentStorage.loadList(StudentStorage.attemptsKey);
    if (!mounted) return;
    setState(() {
      _quizzes = quizzes.map(Quiz.fromJson).toList();
      _attempts = attempts.map(QuizAttempt.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _loaded = true;
    });
  }

  Future<void> _saveQuizzes() => StudentStorage.saveList(
      StudentStorage.quizzesKey, _quizzes.map((q) => q.toJson()).toList());

  Future<void> _saveAttempts() => StudentStorage.saveList(
      StudentStorage.attemptsKey,
      _attempts.map((a) => a.toJson()).toList());

  /// Quizzes to show: the user's real quizzes, or the sample quiz
  /// while they have none.
  List<Quiz> get _visibleQuizzes =>
      _quizzes.isEmpty ? [sampleComputerBasicsDeck.quiz] : _quizzes;

  bool get _showingSample => _quizzes.isEmpty;

  Quiz? _quizForAttempt(QuizAttempt attempt) {
    for (final q in _quizzes) {
      if (attempt.quizId.isNotEmpty && q.id == attempt.quizId) return q;
      if (attempt.quizId.isEmpty && q.title == attempt.quizTitle) {
        return q;
      }
    }
    return null;
  }

  Future<void> _takeQuiz(Quiz quiz) async {
    final isSample = quiz.id == sampleComputerBasicsDeck.quiz.id;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _QuizRunner(
          quiz: quiz,
          aiGenerator: _ai,
          onAttemptSaved: (attempt) async {
            // 10 pts per correct answer, to the header chips.
            final earned = attempt.score * kQuizPointsPerCorrect;
            if (earned > 0) {
              await widget.walletController?.recordQuizPoints(earned);
            }
            if (isSample) return;
            if (!mounted) return;
            setState(() => _attempts.insert(0, attempt));
            await _saveAttempts();
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _openAddQuestion() async {
    setState(() => _menuOpen = false);
    final result = await showModalBottomSheet<_ManualQuestionResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddQuestionSheet(quizzes: _quizzes),
    );
    if (result == null) return;
    setState(() {
      final idx = _quizzes.indexWhere((q) => q.id == result.quizId);
      if (idx >= 0) {
        final old = _quizzes[idx];
        _quizzes[idx] = Quiz(
          id: old.id,
          title: old.title,
          subject: old.subject,
          timeLimitSec: old.timeLimitSec,
          questions: [...old.questions, result.question],
          difficulty: old.difficulty,
          randomize: old.randomize,
        );
      } else {
        _quizzes.add(Quiz(
          id: result.quizId,
          title: result.quizTitle,
          subject: '',
          timeLimitSec: 0,
          questions: [result.question],
        ));
      }
    });
    await _saveQuizzes();
    if (mounted) {
      TopPopup.show(context, message: 'Question added.');
    }
  }

  /// Files (AI): pick a PDF / photo / text file, read it
  /// on-device, generate up to 5 questions, and save them as a new
  /// quiz named after the file.
  Future<void> _openFilesAi() async {
    setState(() => _menuOpen = false);
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp',
        'txt',
        'md',
        'csv',
      ],
    );
    if (picked == null || !mounted) return;
    // "Reading your file" state.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Reading your file…')),
          ],
        ),
      ),
    );
    String error = '';
    List<AiQuizQuestion> generated = [];
    try {
      final file = File(picked.path!);
      final extracted = await _extractor.extract(file);
      if (extracted.outcome != NoteExtractOutcome.ok ||
          extracted.text.trim().isEmpty) {
        error = 'I could not read any text from that file. '
            'Try a clearer photo or a PDF with a text layer.';
      } else {
        final result = await _ai.generateFromText(
          extracted.text,
          questionCount: kAiMaxQuestionsPerSet,
        );
        if (result.succeeded) {
          generated = result.questions;
        } else {
          error = result.error ?? 'Could not generate questions.';
        }
      }
    } catch (_) {
      error = 'Could not read that file. Try again.';
    }
    if (!mounted) return;
    Navigator.pop(context); // Dismiss the "reading" dialog.
    if (generated.isEmpty) {
      TopPopup.show(context, message: error);
      return;
    }
    final baseName = picked.name.contains('.')
        ? picked.name.substring(0, picked.name.lastIndexOf('.'))
        : picked.name;
    final quiz = Quiz(
      id: newId(),
      title: baseName,
      subject: '',
      timeLimitSec: 0,
      questions: generated.map((q) => q.toQuizQuestion()).toList(),
    );
    setState(() {
      _quizzes.insert(0, quiz);
      _lastGeneratedFile = picked.name;
      _lastGeneratedCount = generated.length;
    });
    await _saveQuizzes();
    if (mounted) {
      TopPopup.show(
        context,
        message:
            'Added ${generated.length} question(s) from ${picked.name}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizzes = _visibleQuizzes;
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_menuOpen) ...[
            _menuButton(
              icon: Icons.edit_outlined,
              label: 'Add Question manually',
              onTap: _openAddQuestion,
            ),
            const SizedBox(height: 8),
            _menuButton(
              icon: Icons.folder_outlined,
              label: 'Files',
              badge: 'AI',
              onTap: _openFilesAi,
            ),
            const SizedBox(height: 12),
          ],
          _plusButton(),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppLayout.pagePaddingTab,
              children: [
                if (_showingSample)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Sample quiz'),
                      subtitle: const Text(
                          'Computer Basics — try it below. Add your '
                          'first question or file and this sample goes away.'),
                    ),
                  ),
                if (_showingSample) const SizedBox(height: AppSpacing.s8),
                if (_lastGeneratedFile != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle,
                          color: Colors.green),
                      title: Text(
                          'Added $_lastGeneratedCount question(s) from $_lastGeneratedFile'),
                      subtitle: const Text(
                          'The AI read your file and built questions from it.'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(
                            () => _lastGeneratedFile = null),
                      ),
                    ),
                  ),
                if (_lastGeneratedFile != null)
                  const SizedBox(height: AppSpacing.s8),
                if (quizzes.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No quizzes yet.'),
                      subtitle:
                          Text('Add a quiz from your notes.'),
                    ),
                  )
                else
                  for (final quiz in quizzes)
                    Card(
                      child: Padding(
                        padding: AppLayout.cardPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quiz.title,
                              style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (quiz.subject.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(quiz.subject,
                                  style: AppText.caption),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${quiz.questions.length} questions · '
                              'Multiple choice · 10 pts each',
                              style: AppText.caption,
                            ),
                            const SizedBox(height: AppSpacing.s8),
                            FilledButton.icon(
                              onPressed: () => _takeQuiz(quiz),
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('Start quiz'),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (_attempts.isNotEmpty) ...[
                  const SizedBox(height: AppLayout.headerGap),
                  const Text('Quiz history',
                      style: AppText.sectionTitle),
                  const SizedBox(height: AppSpacing.s8),
                  for (final attempt in _attempts)
                    Card(
                      child: ListTile(
                        title: Text(attempt.quizTitle),
                        subtitle: Text(
                            '${formatDate(attempt.date)} · ${attempt.percentage}%${attempt.durationSec > 0 ? ' · ${attempt.durationSec ~/ 60}m ${attempt.durationSec % 60}s' : ''}'),
                        trailing: Text(
                          '${attempt.score}/${attempt.total}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700),
                        ),
                        onTap: () {
                          final quiz = _quizForAttempt(attempt);
                          if (quiz == null) {
                            TopPopup.show(
                              context,
                              message:
                                  'That quiz is no longer saved, so its questions cannot be reviewed.',
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _AttemptReviewScreen(
                                  attempt: attempt, quiz: quiz),
                            ),
                          );
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 72),
              ],
            ),
    );
  }

  /// One floating-menu button (Add Question manually / Files):
  /// brand-soft pill with an icon, a label, and an optional AI badge.
  Widget _menuButton({
    required IconData icon,
    required String label,
    String? badge,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A2C22)
                : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(238, 245, 241, 0.12)
                  : const Color.fromRGBO(16, 35, 26, 0.12),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.3),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: const Color(0xFF34D399)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFFEEF5F1)
                      : const Color(0xFF10231A),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The + icon ONLY (floating circular button, bottom right — no
  /// label). Rotates 45° into a close icon while the menu is open.
  Widget _plusButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF16A34A),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.4),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _menuOpen = !_menuOpen),
          child: Center(
            child: AnimatedRotation(
              turns: _menuOpen ? 0.125 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.add, size: 24, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Result of the "Add Question manually" sheet: the question plus
/// which quiz it belongs to.
class _ManualQuestionResult {
  _ManualQuestionResult({
    required this.quizId,
    required this.quizTitle,
    required this.question,
  });

  final String quizId;
  final String quizTitle;
  final QuizQuestion question;
}

/// "Add Question manually": a form with a quiz picker, the
/// question, choices A–D, and the correct answer. Picking "New
/// quiz…" asks for a title and creates the quiz.
class _AddQuestionSheet extends StatefulWidget {
  const _AddQuestionSheet({required this.quizzes});

  final List<Quiz> quizzes;

  @override
  State<_AddQuestionSheet> createState() => _AddQuestionSheetState();
}

class _AddQuestionSheetState extends State<_AddQuestionSheet> {
  final _question = TextEditingController();
  final _options = List.generate(4, (_) => TextEditingController());
  final _newQuizTitle = TextEditingController();
  int _correct = 0;
  String _quizChoice = '';

  @override
  void initState() {
    super.initState();
    _quizChoice =
        widget.quizzes.isEmpty ? '__new__' : widget.quizzes.first.id;
  }

  @override
  void dispose() {
    _question.dispose();
    _newQuizTitle.dispose();
    for (final c in _options) {
      c.dispose();
    }
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add question manually',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppLayout.cardGap),
            DropdownButtonFormField<String>(
              value: _quizChoice,
              decoration: const InputDecoration(labelText: 'Quiz'),
              items: [
                for (final q in widget.quizzes)
                  DropdownMenuItem(value: q.id, child: Text(q.title)),
                const DropdownMenuItem(
                    value: '__new__', child: Text('New quiz…')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _quizChoice = v);
              },
            ),
            if (_quizChoice == '__new__') ...[
              const SizedBox(height: AppSpacing.s8),
              TextField(
                controller: _newQuizTitle,
                decoration: const InputDecoration(
                    labelText: 'New quiz title'),
              ),
            ],
            const SizedBox(height: AppSpacing.s8),
            TextField(
              controller: _question,
              decoration:
                  const InputDecoration(labelText: 'Question'),
            ),
            const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Radio<int>(
                      value: i,
                      groupValue: _correct,
                      onChanged: (v) => setState(() => _correct = v ?? 0),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _options[i],
                        decoration: InputDecoration(
                            labelText:
                                'Choice ${String.fromCharCode(65 + i)}'),
                      ),
                    ),
                  ],
                ),
              ),
            const Text('Pick the radio of the correct choice.'),
            const SizedBox(height: AppLayout.cardGap),
            FilledButton(
              onPressed: () {
                if (_question.text.trim().isEmpty) {
                  TopPopup.show(context, message: 'Enter a question.');
                  return;
                }
                if (_options.any((c) => c.text.trim().isEmpty)) {
                  TopPopup.show(context, message: 'Fill in all 4 choices.');
                  return;
                }
                final isNew = _quizChoice == '__new__';
                final title = isNew
                    ? _newQuizTitle.text.trim()
                    : widget.quizzes
                        .firstWhere((q) => q.id == _quizChoice)
                        .title;
                if (isNew && title.isEmpty) {
                  TopPopup.show(context, message: 'Enter a quiz title.');
                  return;
                }
                Navigator.pop(
                  context,
                  _ManualQuestionResult(
                    quizId:
                        isNew ? newId() : _quizChoice,
                    quizTitle: title,
                    question: QuizQuestion(
                      type: 'mcq',
                      question: _question.text.trim(),
                      options:
                          _options.map((c) => c.text.trim()).toList(),
                      correctIndex: _correct,
                      answer: _options[_correct].text.trim(),
                      explanation: '',
                    ),
                  ),
                );
              },
              child: const Text('Save question'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiz taking: one question at a time, multiple-choice with
/// right/wrong feedback on the results screen, a timer when the
/// quiz has one, and a scored results screen that awards points.
/// "Ask AI to Explain More" uses the on-device AI, which returns
/// the stored explanation (never an invented one).
class _QuizRunner extends StatefulWidget {
  const _QuizRunner({required this.quiz, this.onAttemptSaved, this.aiGenerator});

  final Quiz quiz;

  /// Called exactly once, when an attempt is submitted (including
  /// on timer expiry), so the parent can save it and award points
  /// before Done/Retake.
  final Future<void> Function(QuizAttempt attempt)? onAttemptSaved;

  /// On-device AI (production default). Tests can inject a fake.
  final AiQuizGenerator? aiGenerator;

  @override
  State<_QuizRunner> createState() => _QuizRunnerState();
}

class _QuizRunnerState extends State<_QuizRunner> {
  late Quiz _workingQuiz;
  late List<int> _selected;
  late List<String> _typed;
  int _index = 0;
  int _timeLeft = 0;
  Timer? _timer;
  bool _submitted = false;
  bool _attemptSaved = false;
  int _score = 0;
  int _durationSec = 0;
  late DateTime _startedAt;
  bool _showMistakesOnly = false;
  final Map<int, String> _aiExplanations = {};
  final Set<int> _aiLoading = {};

  AiQuizGenerator get _ai =>
      widget.aiGenerator ?? OnDeviceAiQuizGenerator();

  @override
  void initState() {
    super.initState();
    _startAttempt();
  }

  void _startAttempt() {
    _workingQuiz = shuffleQuizForAttempt(
      widget.quiz,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
    _selected = List.filled(_workingQuiz.questions.length, -1);
    _typed = List.filled(_workingQuiz.questions.length, '');
    _index = 0;
    _submitted = false;
    _attemptSaved = false;
    _score = 0;
    _durationSec = 0;
    _showMistakesOnly = false;
    _aiExplanations.clear();
    _aiLoading.clear();
    _startedAt = DateTime.now();
    _timer?.cancel();
    _timeLeft = _workingQuiz.timeLimitSec;
    if (_timeLeft > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_timeLeft <= 1) {
          _submit();
        } else if (mounted) {
          setState(() => _timeLeft--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _unansweredCount {
    var count = 0;
    for (var i = 0; i < _workingQuiz.questions.length; i++) {
      final q = _workingQuiz.questions[i];
      if (q.type == 'mcq' || q.type == 'tf') {
        if (_selected[i] < 0) count++;
      } else if (_typed[i].trim().isEmpty) {
        count++;
      }
    }
    return count;
  }

  List<String> get _givenAnswers {
    final given = <String>[];
    for (var i = 0; i < _workingQuiz.questions.length; i++) {
      final q = _workingQuiz.questions[i];
      if (q.type == 'mcq' || q.type == 'tf') {
        given.add(_selected[i] < 0 || _selected[i] >= q.options.length
            ? ''
            : q.options[_selected[i]]);
      } else {
        given.add(_typed[i].trim());
      }
    }
    return given;
  }

  List<bool> get _correctFlags {
    final flags = <bool>[];
    for (var i = 0; i < _workingQuiz.questions.length; i++) {
      flags.add(isQuestionCorrect(
        _workingQuiz.questions[i],
        selected: _selected[i],
        typed: _typed[i],
      ));
    }
    return flags;
  }

  void _submit() {
    if (_submitted) return;
    _timer?.cancel();
    final score = scoreQuiz(_workingQuiz, _selected, _typed);
    final finished = DateTime.now();
    setState(() {
      _submitted = true;
      _score = score;
      _durationSec = finished.difference(_startedAt).inSeconds;
      if (_durationSec < 0) _durationSec = 0;
    });
    _saveAttempt(finished);
  }

  Future<void> _saveAttempt(DateTime finished) async {
    if (_attemptSaved) return;
    _attemptSaved = true;
    final callback = widget.onAttemptSaved;
    if (callback == null) return;
    await callback(QuizAttempt(
      id: newId(),
      quizId: widget.quiz.id,
      quizTitle: widget.quiz.title,
      score: _score,
      total: _workingQuiz.questions.length,
      date: finished,
      startedAt: _startedAt,
      finishedAt: finished,
      correctFlags: _correctFlags,
      givenAnswers: _givenAnswers,
    ));
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _unansweredCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit quiz?'),
        content: Text(unanswered == 0
            ? 'You answered every question. Submit now?'
            : 'You have $unanswered unanswered question(s). Unanswered questions count as incorrect. Submit anyway?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep answering'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed == true) _submit();
  }

  Future<void> _askAiMore(int index, QuizQuestion q) async {
    if (_aiLoading.contains(index)) return;
    setState(() => _aiLoading.add(index));
    try {
      final text = await _ai.explainMore(
        question: q.question,
        correctAnswer: questionCorrectAnswer(q),
        explanation: q.explanation,
      );
      if (!mounted) return;
      setState(() {
        _aiExplanations[index] = text.trim().isEmpty
            ? (q.explanation.isNotEmpty
                ? q.explanation
                : 'No explanation available.')
            : text.trim();
        _aiLoading.remove(index);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiExplanations[index] = q.explanation.isNotEmpty
            ? q.explanation
            : 'No explanation available.';
        _aiLoading.remove(index);
      });
    }
  }

  String _timeText() {
    final m = _timeLeft ~/ 60;
    final s = _timeLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _durationText() {
    final m = _durationSec ~/ 60;
    final s = _durationSec % 60;
    return '${m}m ${s}s';
  }

  void _setFillLine(int questionIndex, int lineIndex, String value) {
    final lines = answerLines(_typed[questionIndex]);
    while (lines.length <= lineIndex) {
      lines.add('');
    }
    lines[lineIndex] = value.trim();
    _typed[questionIndex] = lines.join('\n');
  }

  void _setMatchLine(int questionIndex, int lineIndex, String? value) {
    if (value == null) return;
    final lines = answerLines(_typed[questionIndex]);
    while (lines.length <= lineIndex) {
      lines.add('');
    }
    lines[lineIndex] = value;
    _typed[questionIndex] = lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final quiz = _workingQuiz;
    if (_submitted) {
      final total = quiz.questions.length;
      final percentage = total > 0 ? ((_score * 100) / total).round() : 0;
      final correctCount = _score;
      final incorrectCount = total - _score < 0 ? 0 : total - _score;
      final earnedPts = _score * kQuizPointsPerCorrect;
      final visibleIndices = <int>[];
      for (var i = 0; i < total; i++) {
        if (_showMistakesOnly && _correctFlags[i]) continue;
        visibleIndices.add(i);
      }
      return Scaffold(
        appBar: AppBar(title: Text('Result · ${quiz.title}')),
        body: ListView(
          padding: AppLayout.pagePaddingTab,
          children: [
            Card(
              child: Padding(
                padding: AppLayout.cardPadding,
                child: Column(
                  children: [
                    Text('$_score/$total',
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w800)),
                    Text(
                        '$percentage% · $correctCount correct · $incorrectCount incorrect · ${_durationText()}'),
                    Text(
                        'Performance Summary: '
                        '${performanceSummaryForPct(percentage)}'),
                    if (earnedPts > 0)
                      Text(
                        'You earned $earnedPts pts',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF16A34A)),
                      ),
                    const Text('Your score'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All answers'),
                  selected: !_showMistakesOnly,
                  onSelected: (_) =>
                      setState(() => _showMistakesOnly = false),
                ),
                ChoiceChip(
                  label: const Text('Review Mistakes'),
                  selected: _showMistakesOnly,
                  onSelected: (_) =>
                      setState(() => _showMistakesOnly = true),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            if (visibleIndices.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No mistakes — great work!'),
                  subtitle: Text('Every answer was correct.'),
                ),
              ),
            for (final i in visibleIndices)
              Builder(builder: (_) {
                final q = quiz.questions[i];
                final correct = _correctFlags[i];
                final given = questionGivenAnswer(
                  q,
                  selected: _selected[i],
                  typed: _typed[i],
                );
                final right = questionCorrectAnswer(q);
                final aiText = _aiExplanations[i];
                final aiLoading = _aiLoading.contains(i);
                return Card(
                  child: Padding(
                    padding: AppLayout.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              correct ? Icons.check_circle : Icons.cancel,
                              color: correct ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            Expanded(
                              child: Text(q.question,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          correct ? 'Correct Answer' : 'Incorrect Answer',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: correct ? Colors.green : Colors.red),
                        ),
                        const SizedBox(height: 4),
                        Text('Your answer: $given'),
                        Text('Correct answer: $right'),
                        if (q.type == 'match') ...[
                          const SizedBox(height: 6),
                          for (var p = 0;
                              p < q.options.length;
                              p++) ...[
                            Builder(builder: (_) {
                              final pairs = matchPairResults(q, _typed[i]);
                              final pairOk =
                                  p < pairs.length && pairs[p];
                              final expected = p <
                                      expectedAnswerLines(q).length
                                  ? expectedAnswerLines(q)[p]
                                  : '';
                              final givenPair = p <
                                      answerLines(_typed[i]).length
                                  ? answerLines(_typed[i])[p]
                                  : '(no answer)';
                              return Text(
                                '${q.options[p]} → $givenPair${pairOk ? '' : ' (correct: $expected)'}',
                                style: TextStyle(
                                    color: pairOk
                                        ? Colors.green
                                        : Colors.red),
                              );
                            }),
                          ],
                        ],
                        if (q.explanation.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Why: ${q.explanation}',
                              style: AppText.caption),
                        ],
                        if (q.learningTip.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Tip: ${q.learningTip}',
                              style: AppText.caption),
                        ],
                        if (aiText != null) ...[
                          const SizedBox(height: 6),
                          Text('AI explanation: $aiText',
                              style: AppText.caption),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: aiLoading
                                  ? null
                                  : () => _askAiMore(i, q),
                              icon: aiLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 18),
                              label: const Text('Ask AI to Explain More'),
                            ),
                            if (!correct)
                              TextButton(
                                onPressed: () => setState(_startAttempt),
                                child: const Text('Try Again'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: AppLayout.cardGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _showMistakesOnly = false),
                    child: const Text('Review Answers'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(_startAttempt),
                    child: const Text('Retake Quiz'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final q = quiz.questions[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${quiz.title} · ${_index + 1}/${quiz.questions.length}'),
        actions: [
          if (quiz.timeLimitSec > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(_timeText(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: AppLayout.pagePaddingTab,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: quiz.questions.isEmpty
                  ? 0
                  : (_index + 1) / quiz.questions.length,
            ),
            const SizedBox(height: AppLayout.cardGap),
            Text(q.question, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: AppLayout.headerGap),
            if (q.type == 'id')
              TextFormField(
                key: ValueKey('typed-$_index'),
                initialValue: _typed[_index],
                decoration:
                    const InputDecoration(labelText: 'Your answer'),
                onChanged: (v) => _typed[_index] = v,
              )
            else if (q.type == 'enum')
              TextFormField(
                key: ValueKey('enum-$_index'),
                initialValue: _typed[_index],
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: 'Your answers, one per line',
                    hintText: 'Answer 1\nAnswer 2'),
                onChanged: (v) => _typed[_index] = v,
              )
            else if (q.type == 'fill')
              for (var b = 0;
                  b < '____'.allMatches(q.question).length;
                  b++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    key: ValueKey('fill-$_index-$b'),
                    initialValue: b < answerLines(_typed[_index]).length
                        ? answerLines(_typed[_index])[b]
                        : '',
                    decoration: InputDecoration(
                        labelText: 'Blank ${b + 1}'),
                    onChanged: (v) => _setFillLine(_index, b, v),
                  ),
                )
            else if (q.type == 'match')
              for (var li = 0; li < q.options.length; li++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(q.options[li])),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('match-$_index-$li'),
                          value: li < answerLines(_typed[_index]).length &&
                                  answerLines(_typed[_index])[li].isNotEmpty
                              ? answerLines(_typed[_index])[li]
                              : null,
                          hint: const Text('Choose'),
                          items: expectedAnswerLines(q)
                              .map((r) => DropdownMenuItem(
                                  value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) => setState(
                              () => _setMatchLine(_index, li, v)),
                        ),
                      ),
                    ],
                  ),
                )
            else
              for (var i = 0; i < q.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ChoiceChip(
                    label: Text(q.options[i]),
                    selected: _selected[_index] == i,
                    onSelected: (_) =>
                        setState(() => _selected[_index] = i),
                  ),
                ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() => _index--),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FilledButton(
                    onPressed: _index == quiz.questions.length - 1
                        ? _confirmSubmit
                        : () => setState(() => _index++),
                    child: Text(_index == quiz.questions.length - 1
                        ? 'Submit'
                        : 'Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Review of one past attempt: the score and every question with
/// the given vs correct answer.
class _AttemptReviewScreen extends StatelessWidget {
  const _AttemptReviewScreen({required this.attempt, required this.quiz});

  final QuizAttempt attempt;
  final Quiz quiz;

  @override
  Widget build(BuildContext context) {
    final flags = attempt.correctFlags;
    return Scaffold(
      appBar: AppBar(title: Text('Review · ${attempt.quizTitle}')),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          Card(
            child: ListTile(
              title: Text('${attempt.score}/${attempt.total}'),
              subtitle: Text(
                  '${formatDate(attempt.date)} · ${attempt.percentage}%'),
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          for (var i = 0; i < quiz.questions.length; i++)
            Builder(builder: (_) {
              final q = quiz.questions[i];
              final correct =
                  i < flags.length ? flags[i] : false;
              final given = i < attempt.givenAnswers.length
                  ? attempt.givenAnswers[i]
                  : '(no answer)';
              final right = questionCorrectAnswer(q);
              return Card(
                child: Padding(
                  padding: AppLayout.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            correct ? Icons.check_circle : Icons.cancel,
                            color:
                                correct ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          Expanded(
                            child: Text(q.question,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Your answer: $given'),
                      Text('Correct answer: $right'),
                      if (q.explanation.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Why: ${q.explanation}',
                            style: AppText.caption),
                      ],
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}
