// Generate Quiz with AI — paste study text, get quiz questions.
//
// Smallest possible proof that AI calls work: paste context, tap
// Generate, see questions. Saving reuses the existing LOCAL quiz
// store (same store the Notes screen reads) — no Firestore, no
// credits, no points. The [generator] parameter exists so widget
// tests can inject a fake; production uses Firebase AI Logic.
import 'package:flutter/material.dart';

import 'ai_quiz_input.dart';
import 'ai_quiz_service.dart';
import 'student/student_data.dart';

class AiQuizGenerateScreen extends StatefulWidget {
  const AiQuizGenerateScreen({super.key, this.generator, this.pickInput});

  final AiQuizGenerator? generator;

  /// Override for the system pickers; widget tests inject a fake.
  /// Production default is [pickQuizInput].
  final Future<AiQuizPickedInput?> Function(AiQuizInputSource)? pickInput;

  @override
  State<AiQuizGenerateScreen> createState() => _AiQuizGenerateScreenState();
}

class _AiQuizGenerateScreenState extends State<AiQuizGenerateScreen> {
  late final AiQuizGenerator _generator =
      widget.generator ?? FirebaseAiQuizGenerator();
  final _contextController = TextEditingController();
  int _count = 5;
  String _difficulty = 'medium';
  Set<String> _types = {'mcq'};
  AiQuizGeneration? _result;
  bool _loading = false;
  bool _saved = false;

  /// Attached study material (camera / picture / document). When set,
  /// Generate uses it instead of the pasted text; clearing it returns
  /// to the paste-text flow.
  AiQuizPickedInput? _picked;
  String? _pickError;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _pick(AiQuizInputSource source) async {
    final pick = widget.pickInput ?? pickQuizInput;
    setState(() => _pickError = null);
    AiQuizPickedInput? picked;
    try {
      picked = await pick(source);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pickError = _pickErrorMessage(e));
      return;
    }
    if (!mounted || picked == null) return; // User cancelled.
    setState(() {
      _picked = picked;
      _result = null;
      _saved = false;
    });
  }

  String _pickErrorMessage(Object e) {
    if (e is FormatException) return e.message;
    final text = e.toString().toLowerCase();
    if (text.contains('permission') || text.contains('denied')) {
      return 'Permission denied — allow camera and photo access to '
          'use this, then try again.';
    }
    return 'Could not pick that file. Try again.';
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _result = null;
      _saved = false;
    });
    final picked = _picked;
    final AiQuizGeneration result;
    if (picked != null && picked.hasMedia) {
      result = await _generator.generateFromMedia(
        picked.attachments,
        questionCount: _count,
        difficulty: _difficulty,
        questionTypes: _types.toList(),
      );
    } else if (picked != null && picked.hasText) {
      result = await _generator.generateFromText(
        picked.text!,
        questionCount: _count,
        difficulty: _difficulty,
        questionTypes: _types.toList(),
      );
    } else {
      result = await _generator.generateFromText(
        _contextController.text,
        questionCount: _count,
        difficulty: _difficulty,
        questionTypes: _types.toList(),
      );
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || !result.succeeded) return;
    final pasted = _contextController.text.trim();
    final firstLine = pasted.isEmpty
        ? (_picked?.label ?? '')
        : pasted.split('\n').first.trim();
    final title = firstLine.isEmpty
        ? 'AI Generated Quiz'
        : (firstLine.length > 40
            ? '${firstLine.substring(0, 40)}…'
            : firstLine);
    final quiz = Quiz(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      subject: 'AI Generated',
      timeLimitSec: 0,
      questions: result.questions.map((q) => q.toQuizQuestion()).toList(),
      difficulty: _difficulty,
    );
    final existing =
        await StudentStorage.loadList(StudentStorage.quizzesKey);
    final quizzes = existing.map(Quiz.fromJson).toList()..add(quiz);
    await StudentStorage.saveList(
      StudentStorage.quizzesKey,
      quizzes.map((q) => q.toJson()).toList(),
    );
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Quiz with AI')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _contextController,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Paste study text',
                hintText: 'Paste notes or a lesson summary here…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Or generate from:'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _pick(AiQuizInputSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _pick(AiQuizInputSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Picture'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _pick(AiQuizInputSource.documents),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Documents'),
                  ),
                ),
              ],
            ),
            if (_picked != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text(_picked!.label),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => setState(() => _picked = null),
                ),
              ),
            ],
            if (_pickError != null) ...[
              const SizedBox(height: 8),
              Text(
                _pickError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Difficulty'),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'easy', label: Text('Easy')),
                ButtonSegment(value: 'medium', label: Text('Medium')),
                ButtonSegment(value: 'hard', label: Text('Hard')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (selected) =>
                  setState(() => _difficulty = selected.first),
            ),
            const SizedBox(height: 12),
            const Text('Question types'),
            const SizedBox(height: 4),
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
                  FilterChip(
                    label: Text(t.toUpperCase()),
                    selected: _types.contains(t),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _types.add(t);
                        } else if (_types.length > 1) {
                          _types.remove(t);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 5, label: Text('5')),
                ButtonSegment(value: 10, label: Text('10')),
              ],
              selected: {_count},
              onSelectionChanged: (selected) =>
                  setState(() => _count = selected.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Generate quiz'),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Generating…'),
                ],
              ),
            ],
            if (result != null && result.error != null) ...[
              const SizedBox(height: 16),
              Text(
                result.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (result != null && result.succeeded) ...[
              const SizedBox(height: 16),
              for (var i = 0; i < result.questions.length; i++) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q${i + 1}. [${result.questions[i].type.toUpperCase()}] ${result.questions[i].question}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (result.questions[i].type == 'mcq')
                          for (var o = 0;
                              o < result.questions[i].options.length;
                              o++)
                            Row(
                              children: [
                                Icon(
                                  o == result.questions[i].correctIndex
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 18,
                                  color: o == result.questions[i].correctIndex
                                      ? Colors.green
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child:
                                      Text(result.questions[i].options[o]),
                                ),
                              ],
                            )
                        else if (result.questions[i].type == 'match')
                          for (var pi = 0;
                              pi < result.questions[i].lefts.length;
                              pi++)
                            Text(
                                '${result.questions[i].lefts[pi]} → ${result.questions[i].rights[pi]}')
                        else
                          Text(
                              'Answer: ${_aiPreviewAnswer(result.questions[i])}'),
                        if (result.questions[i].explanation.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Why: ${result.questions[i].explanation}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (!_saved)
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save as quiz'),
                )
              else ...[
                const Text(
                  'Saved! Find it in your Quizzes list.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Preview text for a generated question that is not MCQ/match:
/// the single answer, or the per-line answers joined with commas.
String _aiPreviewAnswer(AiQuizQuestion q) {
  switch (q.type) {
    case 'tf':
      return q.correctIndex == 0 ? 'True' : 'False';
    case 'id':
      return q.answer;
    case 'enum':
    case 'fill':
      return q.answers.join(', ');
    default:
      return q.answer;
  }
}
