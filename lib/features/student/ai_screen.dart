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
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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
    setState(() {
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
      _input.clear();
    });
    _scrollToBottom();
    final reply = answerChat(
      trimmed,
      notes: widget.notes,
      quizzes: widget.quizzes,
      cards: widget.cards,
      subjects: widget.subjects,
      points: widget.points,
    );
    setState(() {
      _messages.add(_ChatMessage(text: reply.text, isUser: false));
    });
    _scrollToBottom();
  }

  /// Reads a picked file on-device and turns it into questions.
  Future<void> _generateFromFile(File file, String fileName) async {
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
        // Messages (scrollable).
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final msg = _messages[i];
              final align = msg.isUser
                  ? Alignment.centerRight
                  : Alignment.centerLeft;
              return Align(
                alignment: align,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width * 0.78,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
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
