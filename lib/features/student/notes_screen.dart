// Review Notes & Quizzes — learning center (local only).
//
// Notes are plain text (this app has no rich-text editor plugin, so
// no fake formatting toolbar). Attachments are not included: there is
// no image/file picker dependency in this app. What IS real: notes
// CRUD + favorites + search, flashcards with a study mode, and
// quizzes (MCQ / True-False / Identification / Enumeration /
// Matching / Fill in the Blanks) with a timer,
// automatic scoring, explanations, and saved history.
import 'dart:async';

import 'package:flutter/material.dart';

import '../ai_quiz_generate_screen.dart';
import '../ai_quiz_service.dart';
import '../app_layout.dart';
import 'student_data.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, this.initialTab = 'notes'});

  final String initialTab;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  List<Flashcard> _cards = [];
  List<Quiz> _quizzes = [];
  List<QuizAttempt> _attempts = [];
  String _tab = 'notes';
  String _query = '';
  bool _favsOnly = false;
  String _subjectFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _load();
  }

  Future<void> _load() async {
    final notes = await StudentStorage.loadList(StudentStorage.notesKey);
    final cards =
        await StudentStorage.loadList(StudentStorage.flashcardsKey);
    final quizzes =
        await StudentStorage.loadList(StudentStorage.quizzesKey);
    final attempts =
        await StudentStorage.loadList(StudentStorage.attemptsKey);
    if (!mounted) return;
    setState(() {
      _notes = notes.map(Note.fromJson).toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));
      _cards = cards.map(Flashcard.fromJson).toList();
      _quizzes = quizzes.map(Quiz.fromJson).toList();
      _attempts = attempts.map(QuizAttempt.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _saveNotes() => StudentStorage.saveList(
      StudentStorage.notesKey, _notes.map((n) => n.toJson()).toList());
  Future<void> _saveCards() => StudentStorage.saveList(
      StudentStorage.flashcardsKey, _cards.map((c) => c.toJson()).toList());
  Future<void> _saveQuizzes() => StudentStorage.saveList(
      StudentStorage.quizzesKey, _quizzes.map((q) => q.toJson()).toList());
  Future<void> _saveAttempts() => StudentStorage.saveList(
      StudentStorage.attemptsKey,
      _attempts.map((a) => a.toJson()).toList());

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  List<String> get _noteSubjects {
    final set = <String>{};
    for (final n in _notes) {
      if (n.subject.isNotEmpty) set.add(n.subject);
    }
    return set.toList()..sort();
  }

  Future<void> _openNoteForm({Note? existing}) async {
    final result = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteForm(existing: existing),
    );
    if (result == null) return;
    setState(() {
      _notes.removeWhere((n) => n.id == result.id);
      _notes.insert(0, result);
    });
    await _saveNotes();
    _snack(existing == null ? 'Note added.' : 'Note updated.');
  }

  Future<void> _deleteNote(Note n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(n.title),
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
    setState(() => _notes.removeWhere((x) => x.id == n.id));
    await _saveNotes();
  }

  Future<void> _openCardForm() async {
    final result = await showModalBottomSheet<Flashcard>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CardForm(),
    );
    if (result == null) return;
    setState(() => _cards.add(result));
    await _saveCards();
    _snack('Flashcard added.');
  }

  Future<void> _openQuizEditor({Quiz? existing}) async {
    final result = await Navigator.push<Quiz>(
      context,
      MaterialPageRoute(builder: (_) => _QuizEditor(existing: existing)),
    );
    if (result == null) return;
    setState(() {
      _quizzes.removeWhere((q) => q.id == result.id);
      _quizzes.add(result);
    });
    await _saveQuizzes();
    _snack(existing == null ? 'Quiz created.' : 'Quiz updated.');
  }

  Future<void> _takeQuiz(Quiz quiz) async {
    // The runner saves each finished attempt through this callback
    // as soon as it is submitted (not on Done), so Retake can
    // restart in place without losing the finished attempt.
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _QuizRunner(
          quiz: quiz,
          aiGenerator: FirebaseAiQuizGenerator(),
          onAttemptSaved: (attempt) async {
            if (!mounted) return;
            setState(() => _attempts.insert(0, attempt));
            await _saveAttempts();
          },
        ),
      ),
    );
  }

  Quiz? _quizForAttempt(QuizAttempt attempt) {
    for (final q in _quizzes) {
      if (attempt.quizId.isNotEmpty && q.id == attempt.quizId) return q;
      if (attempt.quizId.isEmpty && q.title == attempt.quizTitle) {
        return q;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _notes.where((n) {
      if (_favsOnly && !n.favorite) return false;
      if (_subjectFilter != 'all' && n.subject != _subjectFilter) {
        return false;
      }
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!n.title.toLowerCase().contains(q) &&
            !n.body.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Review Notes & Quizzes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tab == 'notes') {
            _openNoteForm();
          } else if (_tab == 'cards') {
            _openCardForm();
          } else {
            _openQuizEditor();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(
            _tab == 'notes' ? 'Add note' : _tab == 'cards' ? 'Add card' : 'New quiz'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'notes', label: Text('Notes')),
                ButtonSegment(value: 'cards', label: Text('Flashcards')),
                ButtonSegment(value: 'quizzes', label: Text('Quizzes')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          if (_tab == 'notes')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search notes…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        selected: _favsOnly,
                        onSelected: (v) => setState(() => _favsOnly = v),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _subjectFilter,
                          decoration: const InputDecoration(
                              labelText: 'Subject', isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: 'all', child: Text('All subjects')),
                            for (final s in _noteSubjects)
                              DropdownMenuItem(value: s, child: Text(s)),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _subjectFilter = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: AppLayout.pagePaddingTab,
              children: [
                if (_tab == 'notes') ...[
                  if (filteredNotes.isEmpty)
                    const Card(
                        child: ListTile(title: Text('No notes found.')))
                  else
                    for (final n in filteredNotes)
                      Card(
                        child: ListTile(
                          title: Text(n.title),
                          subtitle: Text(
                            '${n.subject.isEmpty ? 'No subject' : n.subject} · ${n.body.length > 60 ? '${n.body.substring(0, 60)}…' : n.body}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  n.favorite
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: n.favorite ? Colors.amber : null,
                                ),
                                onPressed: () async {
                                  setState(() {
                                    final idx = _notes.indexWhere(
                                        (x) => x.id == n.id);
                                    if (idx >= 0) {
                                      _notes[idx] = Note(
                                        id: n.id,
                                        title: n.title,
                                        subject: n.subject,
                                        body: n.body,
                                        favorite: !n.favorite,
                                        updated: n.updated,
                                      );
                                    }
                                  });
                                  await _saveNotes();
                                },
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _openNoteForm(existing: n),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () => _deleteNote(n),
                              ),
                            ],
                          ),
                        ),
                      ),
                ] else if (_tab == 'cards') ...[
                  if (_cards.isEmpty)
                    const Card(
                        child: ListTile(
                            title: Text('No flashcards yet.'),
                            subtitle: Text(
                                'Add a card with a question on the front and the answer on the back.')))
                  else ...[
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => _StudyMode(
                        cards: _cards,
                        onDeckChanged: (deck) async {
                          setState(() => _cards = deck);
                          await _saveCards();
                        },
                      )),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Study all cards'),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    for (final c in _cards)
                      Card(
                        child: ListTile(
                          title: Text(c.front),
                          subtitle: Text(
                              '${c.subject.isEmpty ? 'No subject' : c.subject} · Answer: ${c.back}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              setState(() =>
                                  _cards.removeWhere((x) => x.id == c.id));
                              await _saveCards();
                            },
                          ),
                        ),
                      ),
                  ],
                ] else ...[
                  FilledButton.icon(
                    onPressed: () async {
                      final saved = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiQuizGenerateScreen(),
                        ),
                      );
                      if (saved == true) _load();
                    },
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Generate quiz from text (AI)'),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (_quizzes.isEmpty)
                    const Card(
                        child: ListTile(
                            title: Text('No quizzes yet.'),
                            subtitle: Text(
                                'Create a quiz with multiple-choice, true/false, identification, enumeration, matching, or fill-in-the-blanks questions.')))
                  else
                    for (final q in _quizzes)
                      Card(
                        child: ListTile(
                          title: Text(q.title),
                          subtitle: Text(
                              '${q.subject.isEmpty ? 'No subject' : q.subject} · ${q.questions.length} questions · ${quizDifficultyLabel(q.difficulty)}${q.randomize ? ' · randomized' : ''}${q.timeLimitSec > 0 ? ' · ${q.timeLimitSec ~/ 60} min limit' : ' · no time limit'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _takeQuiz(q),
                                child: const Text('Take'),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _openQuizEditor(existing: q),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async {
                                  setState(() => _quizzes.removeWhere(
                                      (x) => x.id == q.id));
                                  await _saveQuizzes();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: AppLayout.headerGap),
                  _analyticsCardWidget(_attempts, _quizzes),
                  if (_attempts.isNotEmpty) ...[
                    const SizedBox(height: AppLayout.headerGap),
                    const Text('Quiz history',
                        style: AppText.sectionTitle),
                    const SizedBox(height: AppSpacing.s8),
                    for (final a in _attempts)
                      Card(
                        child: ListTile(
                          title: Text(a.quizTitle),
                          subtitle: Text(
                              '${formatDate(a.date)} · ${a.percentage}%${a.durationSec > 0 ? ' · ${a.durationSec ~/ 60}m ${a.durationSec % 60}s' : ''}'),
                          trailing: Text(
                            '${a.score}/${a.total}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            final quiz = _quizForAttempt(a);
                            if (quiz == null) {
                              _snack(
                                  'That quiz is no longer saved, so its questions cannot be reviewed.');
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _AttemptReviewScreen(
                                    attempt: a, quiz: quiz),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ],
                const SizedBox(height: 72),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({this.existing});

  final Note? existing;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _subject.text = e.subject;
      _body.text = e.body;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _body.dispose();
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
          Text(
            widget.existing == null ? 'Add note' : 'Edit note',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppLayout.cardGap),
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: AppSpacing.s8),
          TextField(
              controller: _subject,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)')),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _body,
            decoration: const InputDecoration(
              labelText: 'Notes (plain text)',
              hintText: 'Write your review notes here…',
            ),
            maxLines: 8,
          ),
          const SizedBox(height: AppLayout.cardGap),
          FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a title.')));
                return;
              }
              Navigator.pop(
                context,
                Note(
                  id: widget.existing?.id ?? newId(),
                  title: _title.text.trim(),
                  subject: _subject.text.trim(),
                  body: _body.text,
                  favorite: widget.existing?.favorite ?? false,
                  updated: DateTime.now(),
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

class _CardForm extends StatefulWidget {
  const _CardForm();

  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  final _front = TextEditingController();
  final _back = TextEditingController();
  final _subject = TextEditingController();

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _subject.dispose();
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
          const Text('Add flashcard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppLayout.cardGap),
          TextField(
              controller: _front,
              decoration: const InputDecoration(labelText: 'Front (question)')),
          const SizedBox(height: AppSpacing.s8),
          TextField(
              controller: _back,
              decoration: const InputDecoration(labelText: 'Back (answer)')),
          const SizedBox(height: AppSpacing.s8),
          TextField(
              controller: _subject,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)')),
          const SizedBox(height: AppLayout.cardGap),
          FilledButton(
            onPressed: () {
              if (_front.text.trim().isEmpty ||
                  _back.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Fill in both front and back.')));
                return;
              }
              Navigator.pop(
                context,
                Flashcard(
                  id: newId(),
                  front: _front.text.trim(),
                  back: _back.text.trim(),
                  subject: _subject.text.trim(),
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

class _StudyMode extends StatefulWidget {
  const _StudyMode({required this.cards, this.onDeckChanged});

  final List<Flashcard> cards;

  /// Called with the updated deck whenever a card is marked, so
  /// the parent can persist the mark. Null = session-only marks.
  final Future<void> Function(List<Flashcard> deck)? onDeckChanged;

  @override
  State<_StudyMode> createState() => _StudyModeState();
}

class _StudyModeState extends State<_StudyMode> {
  late List<Flashcard> _deck;
  int _index = 0;
  bool _flipped = false;
  final Map<String, String> _marks = {};

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards);
    for (final card in _deck) {
      if (card.studyStatus.isNotEmpty) _marks[card.id] = card.studyStatus;
    }
  }

  int get _remembered =>
      _marks.values.where((s) => s == 'remembered').length;
  int get _needsReview =>
      _marks.values.where((s) => s == 'needsReview').length;
  int get _remaining => _deck.length - _remembered - _needsReview;

  void _mark(String status) {
    final card = _deck[_index];
    final updated = Flashcard(
      id: card.id,
      front: card.front,
      back: card.back,
      subject: card.subject,
      studyStatus: status,
    );
    setState(() {
      _deck[_index] = updated;
      _marks[card.id] = status;
    });
    widget.onDeckChanged?.call(List.of(_deck));
  }

  @override
  Widget build(BuildContext context) {
    final card = _deck[_index];
    return Scaffold(
      appBar: AppBar(title: Text('Study · ${_index + 1}/${_deck.length}')),
      body: Padding(
        padding: AppLayout.pagePaddingTab,
        child: Column(
          children: [
            Text(
              'Remembered $_remembered · Needs review $_needsReview · '
              'Remaining $_remaining',
              style: AppText.caption,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: _deck.isEmpty
                  ? 0
                  : (_remembered + _needsReview) / _deck.length,
            ),
            const SizedBox(height: AppLayout.cardGap),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _flipped = !_flipped),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.95, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: Card(
                    key: ValueKey(_flipped),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _flipped ? 'Answer' : 'Question',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: AppLayout.cardGap),
                            Text(
                              _flipped ? card.back : card.front,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(height: AppLayout.headerGap),
                            const Text('Tap the card to flip',
                                style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _mark('needsReview'),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Needs review'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _mark('remembered'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Remembered'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() {
                              _index--;
                              _flipped = false;
                            }),
                    child: const Text('Previous'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _deck.shuffle();
                      _index = 0;
                      _flipped = false;
                    }),
                    child: const Text('Shuffle'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FilledButton(
                    onPressed: _index == _deck.length - 1
                        ? null
                        : () => setState(() {
                              _index++;
                              _flipped = false;
                            }),
                    child: const Text('Next'),
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


  /// Study Analytics card, computed ONLY from real attempts (see
  /// [computeQuizAnalytics]). No fabricated data: with no attempts
  /// it says so plainly instead of showing zeros as progress.
  Widget _analyticsCardWidget(
    List<QuizAttempt> attempts, List<Quiz> quizzes) {
    final analytics = computeQuizAnalytics(attempts);
    if (attempts.isEmpty) {
      return const Card(
        child: ListTile(
          title: Text('Study Analytics'),
          subtitle: Text(
              'No attempts yet. Take a quiz and your results will appear here.'),
        ),
      );
    }
    final progressLabel = quizzes.isEmpty
        ? '${analytics.distinctQuizzesAttempted} quiz(zes) attempted'
        : '${analytics.distinctQuizzesAttempted} of ${quizzes.length} saved quiz(zes) attempted';
    return Card(
      child: Padding(
        padding: AppLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Study Analytics', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: _statCellWidget('Completed',
                      '${analytics.totalAttempts}'),
                ),
                Expanded(
                  child: _statCellWidget(
                      'Average', '${analytics.averagePct}%'),
                ),
                Expanded(
                  child: _statCellWidget(
                      'Highest', '${analytics.highestPct}%'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text('Weekly performance (last 7 days)',
                style: AppText.caption),
            const SizedBox(height: 4),
            _WeeklyBarChart(days: analytics.weekly),
            const SizedBox(height: 4),
            for (final day in analytics.weekly)
              Text(
                '${day.dateKey}: ${day.attempts} attempt(s)'
                '${day.attempts == 0 ? '' : ' · ${day.averagePct}%'}',
                style: AppText.caption,
              ),
            const SizedBox(height: AppSpacing.s8),
            Text('Study progress: $progressLabel',
                style: AppText.caption),
          ],
        ),
      ),
    );
  }

  Widget _statCellWidget(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: AppText.caption),
        ],
      );



/// Weekly attempts bar chart, custom-painted with no new
/// dependency. Bars show attempts per day over the last 7 days,
/// computed only from real attempts: a day with no attempts draws
/// no bar (zero), never a fabricated value. The numeric caption
/// rows under the chart carry the per-day average.
class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.days});

  final List<QuizAnalyticsDay> days;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: CustomPaint(
        painter: _WeeklyBarPainter(days: days),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WeeklyBarPainter extends CustomPainter {
  _WeeklyBarPainter({required this.days});

  final List<QuizAnalyticsDay> days;

  @override
  void paint(Canvas canvas, Size size) {
    final maxAttempts =
        days.fold<int>(0, (m, d) => d.attempts > m ? d.attempts : m);
    const labelHeight = 18.0;
    final chartHeight = size.height - labelHeight;
    final slot = days.isEmpty ? size.width : size.width / days.length;
    const barWidth = 22.0;
    final barPaint = Paint()..color = const Color(0xFF16A34A);
    final axisPaint = Paint()
      ..color = const Color(0xFFB0B0B0)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(size.width, chartHeight),
      axisPaint,
    );
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final center = slot * i + slot / 2;
      if (day.attempts > 0 && maxAttempts > 0) {
        final barHeight = (day.attempts / maxAttempts) * (chartHeight - 16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              center - barWidth / 2,
              chartHeight - barHeight,
              barWidth,
              barHeight,
            ),
            const Radius.circular(4),
          ),
          barPaint,
        );
        final countPainter = TextPainter(
          text: TextSpan(
            text: '${day.attempts}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF16A34A)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        countPainter.paint(
          canvas,
          Offset(
            center - countPainter.width / 2,
            chartHeight - barHeight - 14,
          ),
        );
      }
      final label = day.dateKey.length >= 10
          ? day.dateKey.substring(5)
          : day.dateKey;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(center - labelPainter.width / 2, chartHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(_WeeklyBarPainter old) => old.days != days;
}

/// Read-only review of one saved attempt. Shows the real answer
/// given only when it was stored ([QuizAttempt.givenAnswers]);
/// otherwise it shows correctness + the correct answer +
/// explanation without inventing a given answer.
class _AttemptReviewScreen extends StatelessWidget {
  const _AttemptReviewScreen({required this.attempt, required this.quiz});

  final QuizAttempt attempt;
  final Quiz quiz;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Review · ${attempt.quizTitle}')),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          Card(
            child: Padding(
              padding: AppLayout.cardPadding,
              child: Column(
                children: [
                  Text('${attempt.score}/${attempt.total}',
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w800)),
                  Text(
                      '${attempt.percentage}% · ${attempt.correctCount} correct · ${attempt.incorrectCount} incorrect${attempt.durationSec > 0 ? ' · ${attempt.durationSec ~/ 60}m ${attempt.durationSec % 60}s' : ''}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          for (var i = 0; i < quiz.questions.length; i++)
            Builder(builder: (_) {
              final q = quiz.questions[i];
              final correct = i < attempt.correctFlags.length
                  ? attempt.correctFlags[i]
                  : null;
              final given = i < attempt.givenAnswers.length
                  ? attempt.givenAnswers[i]
                  : '';
              return Card(
                child: Padding(
                  padding: AppLayout.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            correct == null
                                ? Icons.help_outline
                                : correct
                                    ? Icons.check_circle
                                    : Icons.cancel,
                            color: correct == null
                                ? null
                                : correct
                                    ? Colors.green
                                    : Colors.red,
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
                      if (correct != null)
                        Text(correct ? 'Correct' : 'Incorrect',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: correct
                                    ? Colors.green
                                    : Colors.red)),
                      if (given.isNotEmpty) Text('Your answer: $given'),
                      Text('Correct answer: ${questionCorrectAnswer(q)}'),
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
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}


/// Short label for a question type, used in the editor list and the
/// AI preview. Unknown types fall back to their raw value.
String _questionTypeLabel(String type) {
  switch (type) {
    case 'mcq':
      return 'Multiple choice';
    case 'tf':
      return 'True or False';
    case 'id':
      return 'Identification';
    case 'enum':
      return 'Enumeration';
    case 'match':
      return 'Matching';
    case 'fill':
      return 'Fill in the Blanks';
    default:
      return type;
  }
}

class _QuizEditor extends StatefulWidget {
  const _QuizEditor({this.existing});

  final Quiz? existing;

  @override
  State<_QuizEditor> createState() => _QuizEditorState();
}

class _QuizEditorState extends State<_QuizEditor> {
  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _minutes = TextEditingController();
  late List<QuizQuestion> _questions;
  String _difficulty = 'medium';
  bool _randomize = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _subject.text = e.subject;
      _minutes.text =
          e.timeLimitSec > 0 ? (e.timeLimitSec ~/ 60).toString() : '';
      _questions = List.of(e.questions);
      _difficulty = e.difficulty;
      _randomize = e.randomize;
    } else {
      _questions = [];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _editQuestion({QuizQuestion? existing, int? index}) async {
    final result = await showModalBottomSheet<QuizQuestion>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuestionForm(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (index != null) {
        _questions[index] = result;
      } else {
        _questions.add(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'New quiz' : 'Edit quiz')),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Quiz title')),
          const SizedBox(height: AppSpacing.s8),
          TextField(
              controller: _subject,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)')),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _minutes,
            decoration: const InputDecoration(
                labelText: 'Time limit in minutes (0 = no limit)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.s8),
          const Text('Difficulty', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'easy', label: Text('Easy')),
              ButtonSegment(value: 'medium', label: Text('Medium')),
              ButtonSegment(value: 'hard', label: Text('Hard')),
            ],
            selected: {_difficulty},
            onSelectionChanged: (sel) =>
                setState(() => _difficulty = sel.first),
          ),
          SwitchListTile(
            title: const Text('Randomize questions'),
            subtitle: const Text(
                'Shuffle question order (and MCQ options) for each attempt.'),
            value: _randomize,
            onChanged: (v) => setState(() => _randomize = v),
          ),
          const SizedBox(height: AppLayout.headerGap),
          Row(
            children: [
              Expanded(
                child: Text('Questions (${_questions.length})',
                    style: AppText.sectionTitle),
              ),
              TextButton.icon(
                onPressed: () => _editQuestion(),
                icon: const Icon(Icons.add),
                label: const Text('Add question'),
              ),
            ],
          ),
          for (var i = 0; i < _questions.length; i++)
            Card(
              child: ListTile(
                title: Text(_questions[i].question),
                subtitle: Text(_questionTypeLabel(_questions[i].type)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () =>
                          _editQuestion(existing: _questions[i], index: i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () =>
                          setState(() => _questions.removeAt(i)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppLayout.headerGap),
          FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a quiz title.')));
                return;
              }
              if (_questions.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Add at least one question.')));
                return;
              }
              final minutes = int.tryParse(_minutes.text) ?? 0;
              Navigator.pop(
                context,
                Quiz(
                  id: widget.existing?.id ?? newId(),
                  title: _title.text.trim(),
                  subject: _subject.text.trim(),
                  timeLimitSec: minutes * 60,
                  questions: _questions,
                  difficulty: _difficulty,
                  randomize: _randomize,
                ),
              );
            },
            child: const Text('Save quiz'),
          ),
        ],
      ),
    );
  }
}

class _QuestionForm extends StatefulWidget {
  const _QuestionForm({this.existing});

  final QuizQuestion? existing;

  @override
  State<_QuestionForm> createState() => _QuestionFormState();
}

class _QuestionFormState extends State<_QuestionForm> {
  final _question = TextEditingController();
  final _explanation = TextEditingController();
  final _learningTip = TextEditingController();
  final _answer = TextEditingController();
  final _options =
      List.generate(4, (_) => TextEditingController());
  final _rights =
      List.generate(4, (_) => TextEditingController());
  String _type = 'mcq';
  int _correct = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _question.text = e.question;
      _explanation.text = e.explanation;
      _learningTip.text = e.learningTip;
      _type = e.type;
      _correct = e.correctIndex;
      if (e.type == 'enum' || e.type == 'fill') {
        _answer.text = e.answer;
      } else if (e.type == 'match') {
        final rights = answerLines(e.answer);
        for (var i = 0; i < 4; i++) {
          if (i < e.options.length) _options[i].text = e.options[i];
          if (i < rights.length) _rights[i].text = rights[i];
        }
      } else {
        _answer.text = e.answer;
        for (var i = 0; i < 4; i++) {
          if (i < e.options.length) _options[i].text = e.options[i];
        }
      }
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _explanation.dispose();
    _learningTip.dispose();
    _answer.dispose();
    for (final c in _options) {
      c.dispose();
    }
    for (final c in _rights) {
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
            const Text('Question',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppLayout.cardGap),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in [
                  'mcq',
                  'tf',
                  'id',
                  'enum',
                  'match',
                  'fill',
                ])
                  ChoiceChip(
                    label: Text(_questionTypeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            TextField(
                controller: _question,
                decoration: const InputDecoration(labelText: 'Question')),
            const SizedBox(height: AppSpacing.s8),
            if (_type == 'mcq') ...[
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Radio<int>(
                        value: i,
                        groupValue: _correct,
                        onChanged: (v) =>
                            setState(() => _correct = v ?? 0),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _options[i],
                          decoration: InputDecoration(
                              labelText: 'Option ${i + 1}'),
                        ),
                      ),
                    ],
                  ),
                ),
              const Text('Pick the radio of the correct option.'),
            ] else if (_type == 'tf') ...[
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('True')),
                  ButtonSegment(value: 1, label: Text('False')),
                ],
                selected: {_correct},
                onSelectionChanged: (s) => setState(() => _correct = s.first),
              ),
            ] else if (_type == 'enum') ...[
              TextField(
                  controller: _answer,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                      labelText: 'Correct answers, one per line',
                      hintText: 'Answer 1\nAnswer 2\nAnswer 3')),
              const Text(
                  'Order does not matter; every listed answer must be given.'),
            ] else if (_type == 'match') ...[
              const Text('Left items are matched to right items, in order.'),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _options[i],
                          decoration: InputDecoration(
                              labelText: 'Left ${i + 1}'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_right_alt, size: 18),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _rights[i],
                          decoration: InputDecoration(
                              labelText: 'Right ${i + 1}'),
                        ),
                      ),
                    ],
                  ),
                ),
              const Text(
                  'Fill at least 2 complete pairs; blank rows are ignored.'),
            ] else if (_type == 'fill') ...[
              const Text(
                  'Write ____ in the question for each blank, in order.'),
              TextField(
                  controller: _answer,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Blank answers, one per line, in order')),
            ] else ...[
              TextField(
                  controller: _answer,
                  decoration: const InputDecoration(
                      labelText: 'Correct answer (exact text)')),
            ],
            const SizedBox(height: AppSpacing.s8),
            TextField(
                controller: _explanation,
                decoration: const InputDecoration(
                    labelText: 'Explanation (shown after answering)')),
            const SizedBox(height: AppSpacing.s8),
            TextField(
                controller: _learningTip,
                decoration: const InputDecoration(
                    labelText: 'Learning tip (optional, shown with Why)')),
            const SizedBox(height: AppLayout.cardGap),
            FilledButton(
              onPressed: () {
                if (_question.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a question.')));
                  return;
                }
                if (_type == 'mcq' &&
                    _options.any((c) => c.text.trim().isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Fill in all 4 options.')));
                  return;
                }
                if (_type == 'id' && _answer.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter the correct answer.')));
                  return;
                }
                if (_type == 'enum' &&
                    answerLines(_answer.text).length < 2) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter at least 2 answers, one per line.')));
                  return;
                }
                if (_type == 'match') {
                  var pairs = 0;
                  for (var i = 0; i < 4; i++) {
                    final left = _options[i].text.trim();
                    final right = _rights[i].text.trim();
                    if (left.isEmpty && right.isEmpty) continue;
                    if (left.isEmpty || right.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Each matching row needs both a left and a right item.')));
                      return;
                    }
                    pairs++;
                  }
                  if (pairs < 2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Enter at least 2 matching pairs.')));
                    return;
                  }
                }
                if (_type == 'fill') {
                  final blanks =
                      '____'.allMatches(_question.text).length;
                  final answers = answerLines(_answer.text);
                  if (blanks == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Use ____ in the question for each blank.')));
                    return;
                  }
                  if (answers.length != blanks) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Enter $blanks blank answer(s), one per line.')));
                    return;
                  }
                }
                final matchLefts = <String>[];
                final matchRights = <String>[];
                if (_type == 'match') {
                  for (var i = 0; i < 4; i++) {
                    final left = _options[i].text.trim();
                    final right = _rights[i].text.trim();
                    if (left.isEmpty && right.isEmpty) continue;
                    matchLefts.add(left);
                    matchRights.add(right);
                  }
                }
                Navigator.pop(
                  context,
                  QuizQuestion(
                    type: _type,
                    question: _question.text.trim(),
                    options: _type == 'mcq'
                        ? _options.map((c) => c.text.trim()).toList()
                        : _type == 'tf'
                            ? const ['True', 'False']
                            : _type == 'match'
                                ? matchLefts
                                : const [],
                    correctIndex: _correct,
                    answer: _type == 'match'
                        ? matchRights.join('\n')
                        : _type == 'enum' || _type == 'fill'
                            ? answerLines(_answer.text).join('\n')
                            : _answer.text.trim(),
                    explanation: _explanation.text.trim(),
                    learningTip: _learningTip.text.trim(),
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

class _QuizRunner extends StatefulWidget {
  const _QuizRunner({required this.quiz, this.onAttemptSaved, this.aiGenerator});

  final Quiz quiz;

  /// Called exactly once, when an attempt is submitted (including on
  /// timer expiry), so the parent can save it before Done/Retake.
  final Future<void> Function(QuizAttempt attempt)? onAttemptSaved;

  /// AI used for "Ask AI to Explain More". Production default is the
  /// Firebase generator; widget tests can inject a fake.
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

  AiQuizGenerator get _ai => widget.aiGenerator ?? FirebaseAiQuizGenerator();

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

  /// Number of questions with no answer yet, for the confirmation
  /// dialog. A match/fill/enum/id answer counts only when its typed
  /// text is non-blank.
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
    // Keep trailing blanks as empty lines so line positions stay
    // aligned with the blanks while typing.
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
