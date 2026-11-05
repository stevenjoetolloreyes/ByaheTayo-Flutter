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
  final _customCountController = TextEditingController();
  final _previewKey = GlobalKey();
  int _count = 5;
  bool _customCount = false;
  String _stage = '';
  String _difficulty = 'medium';
  Set<String> _types = {'mcq'};
  AiQuizGeneration? _result;
  bool _loading = false;
  bool _saved = false;

  /// Tipid: the last SUCCESSFUL generation and the request key that
  /// produced it. A later Generate with the exact same key reuses
  /// this result instead of spending another AI call, unless the
  /// user explicitly chooses to generate again.
  String? _lastSuccessfulKey;
  AiQuizGeneration? _lastSuccessfulResult;

  /// Whether that last successful result was already saved as a
  /// quiz, so reusing it restores the saved state instead of
  /// offering a second save of the same quiz.
  bool _lastSuccessfulSaved = false;

  /// Attached study material (camera / picture / document). When set,
  /// Generate uses it instead of the pasted text; clearing it returns
  /// to the paste-text flow.
  AiQuizPickedInput? _picked;
  String? _pickError;

  @override
  void dispose() {
    _contextController.dispose();
    _customCountController.dispose();
    super.dispose();
  }

  void _setCustomCount(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    setState(() {
      _count = parsed.clamp(1, 50);
      _customCount = true;
    });
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

  /// Key identifying one generation request exactly: the study
  /// material (trimmed text, or media label + total bytes +
  /// attachment count) plus count, difficulty and sorted types.
  /// Same key + a successful result = a reuse candidate, never a
  /// reason to spend another AI call on the same material.
  String _generationKey() {
    final picked = _picked;
    final sortedTypes = _types.toList()..sort();
    final settings = '$_count|$_difficulty|${sortedTypes.join(',')}';
    if (picked != null && picked.hasMedia) {
      final totalBytes = picked.attachments.fold<int>(
        0,
        (sum, a) => sum + a.bytes.length,
      );
      return 'media|${picked.label}|$totalBytes|'
          '${picked.attachments.length}|$settings';
    }
    final text = picked != null && picked.hasText
        ? picked.text!.trim()
        : _contextController.text.trim();
    return 'text|$text|$settings';
  }

  /// Effective input size for the large-request confirm: the text
  /// that will actually be sent (picked file text or pasted text),
  /// and the media bytes that will actually be sent. Pasted text
  /// is ignored when media is attached, because the media branch
  /// is the one the generator uses then.
  int get _effectiveTextLength {
    final picked = _picked;
    if (picked != null && picked.hasMedia) return 0;
    if (picked != null && picked.hasText) return picked.text!.length;
    return _contextController.text.length;
  }

  int get _effectiveMediaBytes {
    final picked = _picked;
    if (picked == null || !picked.hasMedia) return 0;
    return picked.attachments.fold<int>(
      0,
      (sum, a) => sum + a.bytes.length,
    );
  }

  bool get _isLargeRequest =>
      _count >= 20 ||
      _effectiveTextLength > 8000 ||
      _effectiveMediaBytes > 5 * 1024 * 1024;

  /// Reuse dialog. Returns 'reuse', 'regenerate', or null when
  /// dismissed. No model call happens for any outcome except an
  /// explicit 'regenerate' tap (which still goes through the
  /// large-request confirm below before any call).
  Future<String?> _showReuseDialog() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Walang bagong AI call — ginamit ulit yung huling quiz',
        ),
        content: const Text(
          'Same material, same bilang, same difficulty at question '
          'types na ito — ito na yung huling quiz na nagawa mo. '
          'Gusto mo bang gamitin ulit yun nang walang bagong AI call?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'reuse'),
            child: const Text('Gamitin yung dati'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'regenerate'),
            child: const Text('Generate ulit (gagamit ng quota)'),
          ),
        ],
      ),
    );
  }

  /// Large-request confirm. Plain Taglish, honest about the free
  /// tier: this is 1 AI call, and the free tier is only about 20
  /// requests a day. Cancel (or dismiss) means zero model calls.
  /// The app cannot know Google's server-side remaining quota, so
  /// no remaining-calls number is shown here — that would be fake.
  Future<bool> _showLargeConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Malaking request ito'),
        content: const Text(
          'Isa itong AI call, at malaki ang kakainin nitong tokens '
          '— mas maraming questions o mas mahabang material, mas '
          'mahaba ang output. Ang free tier ay mga 20 requests lang '
          'kada araw, kaya sayang kung mauubos ito sa paulit-ulit '
          'na pag-generate ng same material. Sigurado ka bang '
          'ituloy mo ito?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate pa rin'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _generate() async {
    // Double-call guard: rapid taps cannot burn two quota calls
    // for one request. The Generate button is also disabled while
    // loading, and the Retry button below is too.
    if (_loading) return;
    final key = _generationKey();
    // Reuse guard: same successful request as last time — offer
    // the existing result before spending another AI call.
    if (_lastSuccessfulKey == key && _lastSuccessfulResult != null) {
      final choice = await _showReuseDialog();
      if (!mounted) return;
      if (choice == 'reuse') {
        setState(() {
          _result = _lastSuccessfulResult;
          _saved = _lastSuccessfulSaved;
        });
        return;
      }
      if (choice != 'regenerate') return; // Dismissed: no call.
      if (_loading) return;
    }
    // Large-request confirm: normal 5/10 short requests get no
    // dialog, so there is no extra friction on the common path.
    if (_isLargeRequest) {
      final confirmed = await _showLargeConfirmDialog();
      if (!mounted) return;
      if (!confirmed) return; // Cancel: zero model calls.
      if (_loading) return;
    }
    await _performGenerate(key);
  }

  Future<void> _performGenerate(String key) async {
    // Stage text follows REAL phases only. File reading and, for
    // txt/docx, text extraction already happened when the file was
    // picked, and model-output parsing happens inside the generator
    // call — so no separate 'Reading Document...', 'Extracting
    // Text...', or 'Finalizing Quiz...' stage is shown here;
    // showing one would be fake progress. During the call the
    // stage is 'Sending to AI...' for media (the model reads
    // PDF/image bytes itself; there is no separate OCR step) and
    // 'Generating Questions...' for text.
    final pickedStage = _picked;
    setState(() {
      _loading = true;
      _result = null;
      _saved = false;
      _stage = pickedStage != null && pickedStage.hasMedia
          ? 'Sending to AI...'
          : 'Generating Questions...';
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
      _stage = '';
      if (result.succeeded) {
        _lastSuccessfulKey = key;
        _lastSuccessfulResult = result;
        _lastSuccessfulSaved = false;
      }
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
    setState(() {
      _saved = true;
      _lastSuccessfulSaved = true;
    });
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
            const SizedBox(height: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _contextController,
              builder: (context, value, _) => Text(
                '${value.text.length} characters',
                style: Theme.of(context).textTheme.bodySmall,
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
            const Text('Number of questions'),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 5, label: Text('5')),
                ButtonSegment(value: 10, label: Text('10')),
                ButtonSegment(value: 20, label: Text('20')),
                ButtonSegment(value: 30, label: Text('30')),
                ButtonSegment(value: 50, label: Text('50')),
              ],
              selected: _customCount ? <int>{} : {_count},
              onSelectionChanged: (selected) => setState(() {
                _count = selected.first;
                _customCount = false;
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Custom number (1–50)',
                border: OutlineInputBorder(),
              ),
              onChanged: _setCustomCount,
            ),
            if (_count > 10) ...[
              const SizedBox(height: 4),
              Text(
                'Long generations may be truncated by model output '
                'limits — a request for $_count questions is not a '
                'guarantee; only valid returned questions are shown. '
                'Mas malaki rin ang tokens kada call pag mas marami '
                'ang questions, kaya mas tipid ang isang maayos na '
                'generate na ni-save at ginamit ulit kaysa '
                'paulit-ulit na pag-generate ng same material.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Generate quiz'),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              _NeonLoadingBar(stage: _stage),
            ],
            if (result != null && result.error != null) ...[
              const SizedBox(height: 16),
              Text(
                result.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : _generate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
            if (result != null && result.succeeded) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Quiz Generated Successfully!',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            '${result.questions.length} questions generated'),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                'Tip: i-save mo para magamit ulit nang walang '
                'bagong AI call.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  final context = _previewKey.currentContext;
                  if (context != null) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 300),
                    );
                  }
                },
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Preview Quiz'),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < result.questions.length; i++) ...[
                Card(
                  key: i == 0 ? _previewKey : null,
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

/// Inline floating neon loading bar for AI generation. Inline
/// only: it renders inside the Generate Quiz page, never as a
/// full-screen page, modal, or large centered spinner. A small
/// emerald bar with a glow and trail travels continuously from
/// left to right while [stage] describes the real in-flight phase.
class _NeonLoadingBar extends StatefulWidget {
  const _NeonLoadingBar({required this.stage});

  final String stage;

  @override
  State<_NeonLoadingBar> createState() => _NeonLoadingBarState();
}

class _NeonLoadingBarState extends State<_NeonLoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Generating...',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Please wait while AI processes your file.'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const barWidth = 80.0;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final left =
                    _controller.value * (width - barWidth).clamp(0, width);
                return SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Positioned(
                        left: (left - 60).clamp(0, width),
                        child: Container(
                          width: 60,
                          height: 6,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF16A34A)
                                    .withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Positioned(
                        left: left,
                        child: Container(
                          width: barWidth,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFF16A34A),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0xFF4ADE80),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Color(0xFF16A34A),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        if (widget.stage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(widget.stage, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
