// Review Notes & Quizzes — learning center (local only).
//
// Notes are plain text (this app has no rich-text editor plugin, so
// no fake formatting toolbar). Attachments are not included: there is
// no image/file picker dependency in this app. What IS real: notes
// CRUD + favorites + search, flashcards with a study mode, and
// quizzes (MCQ / True-False / Identification) with a timer,
// automatic scoring, explanations, and saved history.
import 'dart:async';

import 'package:flutter/material.dart';

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
    final attempt = await Navigator.push<QuizAttempt>(
      context,
      MaterialPageRoute(builder: (_) => _QuizRunner(quiz: quiz)),
    );
    if (attempt == null) return;
    setState(() => _attempts.insert(0, attempt));
    await _saveAttempts();
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        selected: _favsOnly,
                        onSelected: (v) => setState(() => _favsOnly = v),
                      ),
                      const SizedBox(width: 8),
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
              padding: const EdgeInsets.all(16),
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
                            builder: (_) => _StudyMode(cards: _cards)),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Study all cards'),
                    ),
                    const SizedBox(height: 8),
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
                  if (_quizzes.isEmpty)
                    const Card(
                        child: ListTile(
                            title: Text('No quizzes yet.'),
                            subtitle: Text(
                                'Create a quiz with multiple-choice, true/false, or identification questions.')))
                  else
                    for (final q in _quizzes)
                      Card(
                        child: ListTile(
                          title: Text(q.title),
                          subtitle: Text(
                              '${q.subject.isEmpty ? 'No subject' : q.subject} · ${q.questions.length} questions${q.timeLimitSec > 0 ? ' · ${q.timeLimitSec ~/ 60} min limit' : ' · no time limit'}'),
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
                  if (_attempts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Quiz history',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final a in _attempts)
                      Card(
                        child: ListTile(
                          title: Text(a.quizTitle),
                          subtitle: Text(formatDate(a.date)),
                          trailing: Text(
                            '${a.score}/${a.total}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
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
          const SizedBox(height: 12),
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 8),
          TextField(
              controller: _subject,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)')),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            decoration: const InputDecoration(
              labelText: 'Notes (plain text)',
              hintText: 'Write your review notes here…',
            ),
            maxLines: 8,
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          TextField(
              controller: _front,
              decoration: const InputDecoration(labelText: 'Front (question)')),
          const SizedBox(height: 8),
          TextField(
              controller: _back,
              decoration: const InputDecoration(labelText: 'Back (answer)')),
          const SizedBox(height: 8),
          TextField(
              controller: _subject,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)')),
          const SizedBox(height: 12),
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
  const _StudyMode({required this.cards});

  final List<Flashcard> cards;

  @override
  State<_StudyMode> createState() => _StudyModeState();
}

class _StudyModeState extends State<_StudyMode> {
  late List<Flashcard> _deck;
  int _index = 0;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards);
  }

  @override
  Widget build(BuildContext context) {
    final card = _deck[_index];
    return Scaffold(
      appBar: AppBar(title: Text('Study · ${_index + 1}/${_deck.length}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _flipped = !_flipped),
                child: Card(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _flipped ? 'Answer' : 'Question',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _flipped ? card.back : card.front,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(height: 16),
                          const Text('Tap the card to flip',
                              style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
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
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Quiz title')),
          const SizedBox(height: 8),
          TextField(
              controller: _subject,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)')),
          const SizedBox(height: 8),
          TextField(
            controller: _minutes,
            decoration: const InputDecoration(
                labelText: 'Time limit in minutes (0 = no limit)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Questions (${_questions.length})',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
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
                subtitle: Text(
                    _questions[i].type == 'mcq'
                        ? 'Multiple choice'
                        : _questions[i].type == 'tf'
                            ? 'True or False'
                            : 'Identification'),
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
          const SizedBox(height: 16),
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
  final _answer = TextEditingController();
  final _options =
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
      _answer.text = e.answer;
      _type = e.type;
      _correct = e.correctIndex;
      for (var i = 0; i < 4; i++) {
        if (i < e.options.length) _options[i].text = e.options[i];
      }
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _explanation.dispose();
    _answer.dispose();
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
            const Text('Question',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mcq', label: Text('Multiple')),
                ButtonSegment(value: 'tf', label: Text('True/False')),
                ButtonSegment(value: 'id', label: Text('Identify')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _question,
                decoration: const InputDecoration(labelText: 'Question')),
            const SizedBox(height: 8),
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
            ] else ...[
              TextField(
                  controller: _answer,
                  decoration: const InputDecoration(
                      labelText: 'Correct answer (exact text)')),
            ],
            const SizedBox(height: 8),
            TextField(
                controller: _explanation,
                decoration: const InputDecoration(
                    labelText: 'Explanation (shown after answering)')),
            const SizedBox(height: 12),
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
                Navigator.pop(
                  context,
                  QuizQuestion(
                    type: _type,
                    question: _question.text.trim(),
                    options: _type == 'mcq'
                        ? _options.map((c) => c.text.trim()).toList()
                        : _type == 'tf'
                            ? const ['True', 'False']
                            : const [],
                    correctIndex: _type == 'tf' ? _correct : _correct,
                    answer: _answer.text.trim(),
                    explanation: _explanation.text.trim(),
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
  const _QuizRunner({required this.quiz});

  final Quiz quiz;

  @override
  State<_QuizRunner> createState() => _QuizRunnerState();
}

class _QuizRunnerState extends State<_QuizRunner> {
  late List<int> _selected;
  late List<String> _typed;
  int _index = 0;
  int _timeLeft = 0;
  Timer? _timer;
  bool _submitted = false;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.quiz.questions.length, -1);
    _typed = List.filled(widget.quiz.questions.length, '');
    _timeLeft = widget.quiz.timeLimitSec;
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

  void _submit() {
    if (_submitted) return;
    _timer?.cancel();
    final score = scoreQuiz(widget.quiz, _selected, _typed);
    setState(() {
      _submitted = true;
      _score = score;
    });
  }

  String _timeText() {
    final m = _timeLeft ~/ 60;
    final s = _timeLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: Text('Result · ${quiz.title}')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('$_score/${quiz.questions.length}',
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w800)),
                    const Text('Your score'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < quiz.questions.length; i++)
              Builder(builder: (_) {
                final q = quiz.questions[i];
                final correct = q.type == 'id'
                    ? _typed[i].trim().toLowerCase() ==
                        q.answer.trim().toLowerCase() &&
                        _typed[i].trim().isNotEmpty
                    : _selected[i] == q.correctIndex;
                final given = q.type == 'id'
                    ? (_typed[i].isEmpty ? '(no answer)' : _typed[i])
                    : _selected[i] < 0
                        ? '(no answer)'
                        : q.options[_selected[i]];
                final right = q.type == 'id'
                    ? q.answer
                    : q.options[q.correctIndex];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              correct
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: correct ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
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
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                QuizAttempt(
                  id: newId(),
                  quizTitle: quiz.title,
                  score: _score,
                  total: quiz.questions.length,
                  date: DateTime.now(),
                ),
              ),
              child: const Text('Done'),
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
          if (widget.quiz.timeLimitSec > 0)
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(q.question, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            if (q.type == 'id')
              TextFormField(
                key: ValueKey('typed-$_index'),
                initialValue: _typed[_index],
                decoration:
                    const InputDecoration(labelText: 'Your answer'),
                onChanged: (v) => _typed[_index] = v,
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
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _index == quiz.questions.length - 1
                        ? _submit
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
