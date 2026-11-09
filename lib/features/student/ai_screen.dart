// EstudyanteGO AI screen — the app's own built-in assistant.
//
// Chat ONLY. There is no Notes Lab tab (removed — the notes live
// in the Notes panel, and the AI's file work happens right here in
// chat). The screen title stays "EstudyanteGO AI".
//
// * A + icon sits on the LEFT of the input field. Tapping it
//   opens a floating menu with only two buttons: "Take Photo"
//   and "Files". (No "More"/"Others".)
// * The quick-reply chips are a single swipeable horizontal row
//   PINNED at the bottom, just above the input field — never
//   inside the scrolling messages. Tapping one sends it.
// * The AI is on-device and rule-based (see estudyantego_ai.dart):
//   no Gemini, no external API, offline, no quota, no API key.
//   It reads files on-device (ML Kit OCR for photos, pdfrx text
//   layer for PDFs, direct read for text) and generates questions
//   that land in the SAME deck the Flashcards and Quiz pages
//   share. It states that it is built into the app, not an
//   online AI.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ai_quiz_service.dart';
import '../estudyantego_ai.dart';
import 'note_extract_service.dart';
import 'student_data.dart';

/// One chat message.
class _ChatMessage {
  _ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// The AI reply animation phase. Only chat replies (via _send)
/// animate: the AI first "thinks" for 5 seconds, then types the
/// answer out character by character. File-flow status messages
/// appear immediately as before.
enum _AiReplyPhase { idle, thinking, typing }

/// The AI chat panel, embedded in the Study tab when the AI pill
/// tab is active. [onQuestionsGenerated] hands generated questions
/// to the Study tab, which saves them as a quiz in the shared deck.
class AiChatPanel extends StatefulWidget {
  const AiChatPanel({
    super.key,
    required this.notes,
    required this.quizzes,
    required this.cards,
    required this.subjects,
    required this.points,
    required this.onQuestionsGenerated,
    this.aiGenerator,
    this.extractor,
  });

  final List<Note> notes;
  final List<Quiz> quizzes;
  final List<Flashcard> cards;
  final List<String> subjects;
  final int points;

  /// Called with generated questions + the source file name, so
  /// the parent can save them as a quiz in the shared deck.
  final Future<void> Function(List<QuizQuestion> questions, String sourceName)
      onQuestionsGenerated;

  /// On-device AI (injectable so tests can use a fake).
  final AiQuizGenerator? aiGenerator;

  /// File text extractor (injectable so tests run without native
  /// plugins).
  final NoteExtractService? extractor;

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final List<_ChatMessage> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// True while the + attach menu is open — the + rotates 45°.
  bool _attachOpen = false;

  /// True while the AI is reading a file.
  bool _readingFile = false;

  /// The in-progress AI reply animation (thinking, then typing).
  /// The on-device AI answers instantly — the 5-second thinking
  /// window is a display delay that reveals the answer, it does
  /// not slow the AI itself.
  _AiReplyPhase _replyPhase = _AiReplyPhase.idle;

  /// Which rotating status word the Thinking bubble shows.
  int _thinkingStatus = 0;

  /// Which of the three Thinking dots is lit (cycles 0 → 1 → 2).
  int _dotPhase = 0;

  /// The full reply being typed, split into characters (runes, so
  /// a multi-code-unit glyph is never split in half).
  String _typingFull = '';
  List<String> _typingChars = const [];
  int _typingShown = 0;

  /// Blinks the typing cursor while the answer is being typed.
  bool _cursorVisible = true;

  Timer? _dotTimer;
  Timer? _statusTimer;
  Timer? _phaseTimer;
  Timer? _typeTimer;
  Timer? _cursorTimer;

  /// How long the Thinking bubble shows before typing starts.
  static const _thinkingDuration = Duration(seconds: 5);

  /// How often the Thinking status word rotates / a dot lights up.
  static const _statusStep = Duration(milliseconds: 1300);
  static const _dotStep = Duration(milliseconds: 320);

  /// Typing pace: quick between ordinary characters, with natural
  /// pauses after a sentence ends or a clause breaks.
  static const _typeStep = Duration(milliseconds: 30);
  static const _typePauseSentence = Duration(milliseconds: 280);
  static const _typePauseClause = Duration(milliseconds: 140);

  /// Cursor blink rate, and how long it takes to fade out once the
  /// answer is complete.
  static const _cursorBlink = Duration(milliseconds: 530);
  static const _cursorFade = Duration(milliseconds: 320);

  /// Status words the Thinking bubble rotates through. No progress
  /// bar and no elapsed-seconds counter — both were asked away.
  static const _thinkingStatuses = <String>[
    'Thinking…',
    'Understanding your question…',
    'Checking your notes…',
    'Writing your answer…',
  ];

  /// The file the AI just read, shown as a removable chip.
  String? _attachedFile;

  AiQuizGenerator get _ai =>
      widget.aiGenerator ?? OnDeviceAiQuizGenerator();

  NoteExtractService get _extractor =>
      widget.extractor ?? NoteExtractService();

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      text: 'Hello! I am EstudyanteGO AI — I run right here on your '
          'phone, so I work even without internet. Ask me about your '
          'quizzes, flashcards, schedule, or fares, or tap + to turn '
          'a file into questions.',
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _cancelReplyTimers();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Cancels every timer driving the reply animation.
  void _cancelReplyTimers() {
    _dotTimer?.cancel();
    _statusTimer?.cancel();
    _phaseTimer?.cancel();
    _typeTimer?.cancel();
    _cursorTimer?.cancel();
    _dotTimer = null;
    _statusTimer = null;
    _phaseTimer = null;
    _typeTimer = null;
    _cursorTimer = null;
  }

  /// Finishes any in-flight reply animation at once: a half-typed
  /// answer joins the chat in full, a still-thinking reply simply
  /// never appears. Callers must rebuild (setState) afterwards.
  void _finishReplyNow() {
    _cancelReplyTimers();
    if (_replyPhase == _AiReplyPhase.typing && _typingFull.isNotEmpty) {
      _messages.add(_ChatMessage(text: _typingFull, isUser: false));
    }
    _replyPhase = _AiReplyPhase.idle;
    _typingFull = '';
    _typingChars = const [];
    _typingShown = 0;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // A new send finishes any in-flight reply animation first, so
    // the chat never shows two half-written AI replies.
    _finishReplyNow();
    setState(() {
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
      _input.clear();
    });
    _scrollToBottom();
    // The on-device AI answers instantly; the animation below only
    // controls how that answer appears.
    final reply = answerChat(
      trimmed,
      notes: widget.notes,
      quizzes: widget.quizzes,
      cards: widget.cards,
      subjects: widget.subjects,
      points: widget.points,
    );
    _startReplyAnimation(reply.text);
  }

  /// Shows the Thinking bubble for 5 seconds (bouncing dots +
  /// rotating status words, no progress bar, no counter), then
  /// types the answer out character by character.
  void _startReplyAnimation(String fullText) {
    _cancelReplyTimers();
    setState(() {
      _replyPhase = _AiReplyPhase.thinking;
      _thinkingStatus = 0;
      _dotPhase = 0;
      _typingFull = fullText;
      _typingChars =
          fullText.runes.map((r) => String.fromCharCode(r)).toList();
      _typingShown = 0;
      _cursorVisible = true;
    });
    _scrollToBottom();
    // The three dots light up in turn while thinking.
    _dotTimer = Timer.periodic(_dotStep, (_) {
      if (!mounted) return;
      setState(() => _dotPhase = (_dotPhase + 1) % 3);
    });
    // The status word rotates while thinking.
    _statusTimer = Timer.periodic(_statusStep, (_) {
      if (!mounted) return;
      setState(() {
        _thinkingStatus =
            (_thinkingStatus + 1) % _thinkingStatuses.length;
      });
    });
    // After the thinking window, start typing the answer out.
    _phaseTimer = Timer(_thinkingDuration, () {
      if (!mounted) return;
      _dotTimer?.cancel();
      _statusTimer?.cancel();
      _dotTimer = null;
      _statusTimer = null;
      setState(() {
        _replyPhase = _AiReplyPhase.typing;
        _typingShown = 0;
        _cursorVisible = true;
      });
      _scrollToBottom();
      _cursorTimer = Timer.periodic(_cursorBlink, (_) {
        if (!mounted) return;
        setState(() => _cursorVisible = !_cursorVisible);
      });
      _typeNext();
    });
  }

  /// Reveals one more character, then schedules the next with a
  /// natural pause (longer after a sentence ends, shorter after a
  /// clause, quick between ordinary characters).
  void _typeNext() {
    if (!mounted) return;
    if (_typingShown >= _typingChars.length) {
      _completeTyping();
      return;
    }
    setState(() => _typingShown++);
    _scrollToBottom();
    final justShown = _typingChars[_typingShown - 1];
    final delay = _isSentenceEnd(justShown)
        ? _typePauseSentence
        : _isClausePause(justShown)
            ? _typePauseClause
            : _typeStep;
    _typeTimer = Timer(delay, _typeNext);
  }

  bool _isSentenceEnd(String ch) =>
      ch == '.' || ch == '!' || ch == '?';
  bool _isClausePause(String ch) =>
      ch == ',' || ch == ';' || ch == ':';

  /// Fades the cursor out, then joins the finished reply to the
  /// chat as a normal message bubble.
  void _completeTyping() {
    _cancelReplyTimers();
    if (!mounted) return;
    setState(() => _cursorVisible = false);
    _typeTimer = Timer(_cursorFade, () {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: _typingFull, isUser: false));
        _replyPhase = _AiReplyPhase.idle;
        _typingFull = '';
        _typingChars = const [];
        _typingShown = 0;
      });
      _scrollToBottom();
    });
  }

  /// Reads a picked file on-device and turns it into questions.
  Future<void> _generateFromFile(File file, String fileName) async {
    // A file message must not land ahead of a half-typed reply.
    _finishReplyNow();
    setState(() {
      _readingFile = true;
      _attachOpen = false;
      _attachedFile = fileName;
    });
    _messages.add(_ChatMessage(
      text: 'Reading $fileName…',
      isUser: false,
    ));
    _scrollToBottom();
    String? error;
    List<AiQuizQuestion> generated = [];
    try {
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
    setState(() => _readingFile = false);
    if (generated.isEmpty) {
      setState(() {
        _messages.add(_ChatMessage(text: error!, isUser: false));
        _attachedFile = null;
      });
      _scrollToBottom();
      return;
    }
    await widget.onQuestionsGenerated(
      generated.map((q) => q.toQuizQuestion()).toList(),
      fileName,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(
        text: 'Added ${generated.length} question(s) from $fileName '
            'to your deck — review them as flashcards, then take '
            'them as a quiz.',
        isUser: false,
      ));
    });
    _scrollToBottom();
  }

  Future<void> _takePhoto() async {
    setState(() => _attachOpen = false);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
    );
    if (picked == null || !mounted) return;
    await _generateFromFile(File(picked.path), picked.name);
  }

  Future<void> _pickFile() async {
    setState(() => _attachOpen = false);
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
    if (picked == null || picked.path == null || !mounted) return;
    await _generateFromFile(File(picked.path!), picked.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleAi = isDark
        ? const Color(0xFF1A2C22)
        : const Color(0xFFEEF4F0);
    final bubbleUser = const Color(0xFF16A34A);
    final textColor = isDark
        ? const Color(0xFFEEF5F1)
        : const Color(0xFF10231A);
    return Column(
      children: [
        // On-device line (the panel header above already shows the
        // "EstudyanteGO AI" title + the heart/star chips).
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'On-device · Offline · No Gemini',
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF34D399),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Messages (scrollable). The in-progress AI reply — the
        // Thinking bubble, then the typed answer — renders as one
        // extra item after the finished messages.
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _messages.length +
                (_replyPhase == _AiReplyPhase.idle ? 0 : 1),
            itemBuilder: (context, i) {
              if (i < _messages.length) {
                return _messageBubble(
                    _messages[i], bubbleAi, bubbleUser, textColor);
              }
              if (_replyPhase == _AiReplyPhase.thinking) {
                return _thinkingBubble(bubbleAi, textColor);
              }
              return _typingBubble(bubbleAi, textColor);
            },
          ),
        ),
        // Attached-file chip (removable).
        if (_attachedFile != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bubbleAi,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_file, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _attachedFile!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: textColor),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _attachedFile = null),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          ),
        // Attach floating menu (Take Photo / Files), anchored
        // above the input.
        if (_attachOpen)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bubbleAi,
                borderRadius: BorderRadius.circular(16),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding:
                        EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Text(
                      'ADD TO THIS CHAT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFF9DB4A8),
                      ),
                    ),
                  ),
                  _attachItem(
                    icon: Icons.photo_camera_outlined,
                    title: 'Take Photo',
                    subtitle:
                        'Snap your notes — the AI reads the handwriting',
                    onTap: _takePhoto,
                    textColor: textColor,
                  ),
                  _attachItem(
                    icon: Icons.folder_outlined,
                    title: 'Files',
                    subtitle: 'PDF, photo, or .txt / .md / .csv '
                        'from your phone',
                    onTap: _pickFile,
                    textColor: textColor,
                  ),
                ],
              ),
            ),
          ),
        // Quick-reply chips: ONE swipeable horizontal row, pinned
        // at the bottom just above the input (never inside the
        // scrolling messages).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final chip in const [
                'Make a quiz from my notes',
                'Fare: Cabugao → Vigan?',
                'Summarize my deck',
                'Are you an online AI?',
              ]) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(chip),
                    onPressed: () => _send(chip),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Input row: + (left) + text field + send.
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF16A34A),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () =>
                      setState(() => _attachOpen = !_attachOpen),
                  child: Center(
                    child: AnimatedRotation(
                      turns: _attachOpen ? 0.125 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.add,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                decoration: InputDecoration(
                  hintText: 'Ask EstudyanteGO AI…',
                  filled: true,
                  fillColor: bubbleAi,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: _send,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF16A34A),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _readingFile
                      ? null
                      : () => _send(_input.text),
                  child: const Center(
                    child: Icon(Icons.send,
                        size: 20, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A finished chat message bubble (unchanged from before).
  Widget _messageBubble(_ChatMessage msg, Color bubbleAi,
      Color bubbleUser, Color textColor) {
    final align =
        msg.isUser ? Alignment.centerRight : Alignment.centerLeft;
    return Align(
      alignment: align,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUser ? bubbleUser : bubbleAi,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isUser ? Colors.white : textColor,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }

  /// The Thinking bubble: three dots lighting up in turn plus the
  /// rotating status word. No progress bar and no elapsed-seconds
  /// counter — both were asked away.
  Widget _thinkingBubble(Color bubbleAi, Color textColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleAi,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              AnimatedOpacity(
                opacity: _dotPhase == i ? 1.0 : 0.35,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 4),
            ],
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _thinkingStatuses[_thinkingStatus],
                style: TextStyle(color: textColor, fontSize: 14.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The answer being typed out, with a blinking green cursor at
  /// the end. The cursor fades out once the answer is complete
  /// (see _completeTyping).
  Widget _typingBubble(Color bubbleAi, Color textColor) {
    final shown = _typingChars.take(_typingShown).join();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleAi,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text.rich(
          TextSpan(
            style: TextStyle(color: textColor, fontSize: 14.5),
            children: [
              TextSpan(text: shown),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AnimatedOpacity(
                  opacity: _cursorVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    width: 2,
                    height: 16,
                    color: const Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(22, 163, 74, 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF34D399)),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: textColor),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFF9DB4A8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
