// Generate Quiz with AI — paste study text, get quiz questions.
//
// Smallest possible proof that AI calls work: paste context, tap
// Generate, see questions. Saving reuses the existing LOCAL quiz
// store (same store the Notes screen reads) — no Firestore, no
// credits, no points. The [generator] parameter exists so widget
// tests can inject a fake; production uses Firebase AI Logic.
import 'package:flutter/material.dart';

import 'ai_quiz_service.dart';
import 'student/student_data.dart';

class AiQuizGenerateScreen extends StatefulWidget {
  const AiQuizGenerateScreen({super.key, this.generator});

  final AiQuizGenerator? generator;

  @override
  State<AiQuizGenerateScreen> createState() => _AiQuizGenerateScreenState();
}

class _AiQuizGenerateScreenState extends State<AiQuizGenerateScreen> {
  late final AiQuizGenerator _generator =
      widget.generator ?? FirebaseAiQuizGenerator();
  final _contextController = TextEditingController();
  int _count = 5;
  AiQuizGeneration? _result;
  bool _loading = false;
  bool _saved = false;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _result = null;
      _saved = false;
    });
    final result = await _generator.generateFromText(
      _contextController.text,
      questionCount: _count,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || !result.succeeded) return;
    final firstLine = _contextController.text.trim().split('\n').first.trim();
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
                          'Q${i + 1}. ${result.questions[i].question}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
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
                                child: Text(result.questions[i].options[o]),
                              ),
                            ],
                          ),
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
