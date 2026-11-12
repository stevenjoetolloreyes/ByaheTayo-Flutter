// Chat Support screens — student side (Nov 11, 2026).
//
// Built from approved preview v17 (`estudyantego-chat-support-preview`).
// Two screens over ONE conversation thread (the admin inbox sees the
// same thread):
//   * [ChatSupportScreen] — Meta-style assisted chat: the assistant
//     greets first, topic-aware auto-replies answer, "Did this help?"
//     decides whether Steven joins, closing asks for a 5-star rating.
//   * [ChatWithAdminScreen] — direct chat with Steven: no bot, no
//     auto-reply, no Quick Help, no rating panel. Reached only from
//     the "Chat with Admin" Quick Help chip.
//
// Flow rules (preview v17, exact):
//   - A new conversation opens bot-first: after a short typing pause
//     the greeting appears with inline topic chips.
//   - Tapping a topic chip (or typing) posts the student message;
//     "AI Assistant is typing…" shows ~1s, then the gold
//     AI ASSISTANT · AUTO-REPLY bubble answers by topic.
//   - "Did this help?" Yes → "Great! Message us anytime." (Steven
//     never joins). No → "Connecting you to an agent…" ~2s, then
//     Steven joins; further student messages go to the admin only.
//   - "Close this chat" asks first, then (Chat Support only) asks
//     "How was your experience?" with 5 stars → "Thanks for your
//     feedback!" → "This chat has ended." + "Start a new
//     conversation" (fresh empty chat, working input box).
//   - Closing Chat with Admin skips the rating step.
//   - Quick Help (Schedule / Fares / Account / Chat with Admin) sits
//     above the input in Chat Support only; the Chat with Admin chip
//     opens the direct screen with NO message posted. It hides when
//     the chat is closed and returns in a new conversation.
//
// The assistant runs on-device (see `chat_support.dart`): the
// student's client writes the auto-reply to Firestore — no backend,
// no Gemini call. The admin sees the full transcript in the inbox,
// including the bot messages, so Steven always knows what the
// student was already told.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'chat_support.dart';
import 'minecraft_theme.dart';
import 'onboarding/auth_service.dart';
import 'top_popup.dart';

/// Which flow this chat view runs: assisted (bot first) or direct
/// (Steven only).
enum SupportChatMode { assisted, directAdmin }

/// Chat Support — the assisted screen (Account → Chat Support).
class ChatSupportScreen extends StatelessWidget {
  const ChatSupportScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.studentName,
    this.conversation,
    this.typingDelay = const Duration(seconds: 1),
    this.connectingDelay = const Duration(seconds: 2),
    this.ratingThanksDelay = const Duration(milliseconds: 1200),
  });

  /// Null when Firebase is not configured — the screen shows an
  /// honest unavailable state instead of crashing.
  final SupportRepository? repository;

  /// The signed-in student (null when signed out).
  final AuthUser? user;

  /// First name shown to the admin (first names only).
  final String studentName;

  /// An existing thread to open (the Chat with Admin chip passes
  /// the current thread). Null = open the student's latest thread
  /// or create a new one.
  final SupportConversation? conversation;

  /// Pause behind "AI Assistant is typing…" (injectable for tests).
  final Duration typingDelay;

  /// Pause behind "Connecting you to an agent…" (injectable).
  final Duration connectingDelay;

  /// How long "Thanks for your feedback!" shows before the ended
  /// panel (injectable).
  final Duration ratingThanksDelay;

  @override
  Widget build(BuildContext context) {
    return _SupportChatView(
      mode: SupportChatMode.assisted,
      repository: repository,
      user: user,
      studentName: studentName,
      conversation: conversation,
      typingDelay: typingDelay,
      connectingDelay: connectingDelay,
      ratingThanksDelay: ratingThanksDelay,
    );
  }
}

/// Chat with Admin — the direct screen (Quick Help chip only).
class ChatWithAdminScreen extends StatelessWidget {
  const ChatWithAdminScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.studentName,
    this.conversation,
    this.typingDelay = const Duration(seconds: 1),
    this.connectingDelay = const Duration(seconds: 2),
    this.ratingThanksDelay = const Duration(milliseconds: 1200),
  });

  /// Null when Firebase is not configured — the screen shows an
  /// honest unavailable state instead of crashing.
  final SupportRepository? repository;

  /// The signed-in student (null when signed out).
  final AuthUser? user;

  /// First name shown to the admin (first names only).
  final String studentName;

  /// The current thread (passed by the Chat Support screen).
  final SupportConversation? conversation;

  /// Unused in direct mode (no typing indicator), kept so both
  /// screens share one constructor shape.
  final Duration typingDelay;

  /// Unused in direct mode (no connecting step).
  final Duration connectingDelay;

  /// Unused in direct mode (no rating step).
  final Duration ratingThanksDelay;

  @override
  Widget build(BuildContext context) {
    return _SupportChatView(
      mode: SupportChatMode.directAdmin,
      repository: repository,
      user: user,
      studentName: studentName,
      conversation: conversation,
      typingDelay: typingDelay,
      connectingDelay: connectingDelay,
      ratingThanksDelay: ratingThanksDelay,
    );
  }
}

class _SupportChatView extends StatefulWidget {
  const _SupportChatView({
    required this.mode,
    required this.repository,
    required this.user,
    required this.studentName,
    this.conversation,
    required this.typingDelay,
    required this.connectingDelay,
    required this.ratingThanksDelay,
  });

  final SupportChatMode mode;
  final SupportRepository? repository;
  final AuthUser? user;
  final String studentName;
  final SupportConversation? conversation;
  final Duration typingDelay;
  final Duration connectingDelay;
  final Duration ratingThanksDelay;

  @override
  State<_SupportChatView> createState() => _SupportChatViewState();
}

class _SupportChatViewState extends State<_SupportChatView> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<List<SupportMessage>>? _messagesSub;
  StreamSubscription<SupportConversation?>? _conversationSub;

  SupportConversation? _conversation;
  List<SupportMessage> _messages = [];

  bool _loading = true;
  String? _error;

  /// True while the fresh-conversation greeting is still behind
  /// its typing pause (the greeting is already written — it is
  /// revealed, not sent, after the pause).
  bool _greetingPause = false;

  /// True while "AI Assistant is typing…" shows.
  bool _typing = false;

  /// True while "Connecting you to an agent…" shows.
  bool _connecting = false;

  /// Id of the latest auto-reply awaiting a Yes/No answer, or null.
  String? _awaitingHelpCheckId;

  /// True while the close-rating card is shown (Chat Support only).
  bool _showRating = false;

  /// True while "Thanks for your feedback!" shows.
  bool _ratingThanks = false;

  bool get _isAssisted => widget.mode == SupportChatMode.assisted;

  bool get _closed => _conversation?.closed ?? false;

  /// Steven has joined (or replied): any admin message in the
  /// thread — the system handoff or a real typed reply. Derived
  /// from the thread, so it survives reopening the chat.
  bool get _humanJoined =>
      _messages.any((m) => m.sender == SupportSender.admin);

  bool get _canSend =>
      !_loading && _error == null && _conversation != null && !_closed;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _unsubscribe();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _unsubscribe() {
    unawaited(_messagesSub?.cancel());
    _messagesSub = null;
    unawaited(_conversationSub?.cancel());
    _conversationSub = null;
  }

  Future<void> _open() async {
    final repository = widget.repository;
    final user = widget.user;
    if (repository == null || user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final SupportConversation conversation;
      var isNew = false;
      final passed = widget.conversation;
      if (passed != null) {
        conversation = passed;
      } else {
        final opened = await repository.openOrCreateForStudent(
          studentUid: user.uid,
          studentName: widget.studentName,
        );
        conversation = opened.conversation;
        isNew = opened.isNew;
      }
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _loading = false;
      });
      _subscribe(conversation.id);
      if (isNew && _isAssisted) {
        // New conversation, bot-first: the greeting appears after
        // a short typing pause (preview v17).
        setState(() => _greetingPause = true);
        await Future.delayed(widget.typingDelay);
        if (mounted) setState(() => _greetingPause = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't open Chat Support. Check your connection "
            'and try again.';
      });
    }
  }

  void _subscribe(String conversationId) {
    final repository = widget.repository;
    if (repository == null) return;
    _unsubscribe();
    _messagesSub = repository.watchMessages(conversationId).listen(
      (messages) {
        if (!mounted) return;
        setState(() => _messages = messages);
        _scrollToBottom();
      },
      onError: (_) {},
    );
    _conversationSub =
        repository.watchConversation(conversationId).listen(
      (conversation) {
        if (!mounted || conversation == null) return;
        // The student is looking at the thread: a waiting admin
        // reply is read now, so the (invisible-to-them) student
        // badge clears.
        if (conversation.unreadForStudent > 0) {
          unawaited(
            repository.markStudentRead(conversationId).catchError((_) {}),
          );
        }
        if (mounted) setState(() => _conversation = conversation);
      },
      onError: (_) {},
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  void _showError(String message) {
    TopPopup.show(context, message: message);
  }

  Future<void> _sendStudentMessage(
    String rawText, {
    SupportTopic? forcedTopic,
  }) async {
    final text = rawText.trim();
    final conversation = _conversation;
    final repository = widget.repository;
    if (text.isEmpty || conversation == null || repository == null) return;
    if (_closed) return;
    final topic = forcedTopic ?? detectSupportTopic(text);
    _inputController.clear();
    setState(() => _awaitingHelpCheckId = null);
    try {
      await repository.sendStudentMessage(
        conversation: conversation,
        text: text,
        topic: topic,
      );
    } catch (_) {
      if (!mounted) return;
      _inputController.text = text;
      _showError("Couldn't send your message. Try again.");
      return;
    }
    if (!_isAssisted) return;
    // Steven already joined (or replied): no more bot replies —
    // further messages go to the admin side only.
    if (_humanJoined) return;
    setState(() => _typing = true);
    await Future.delayed(widget.typingDelay);
    if (!mounted) return;
    setState(() => _typing = false);
    if (_closed) return;
    // Steven may have replied while the assistant was "typing".
    if (_humanJoined) return;
    try {
      final replyId = await repository.sendAssistantMessage(
        conversation: conversation,
        text: supportAutoReply(topic),
      );
      if (!mounted) return;
      setState(() => _awaitingHelpCheckId = replyId);
    } catch (_) {
      if (!mounted) return;
      _showError("Couldn't load the assistant's reply. Try again.");
    }
  }

  Future<void> _onHelpYes() async {
    final conversation = _conversation;
    final repository = widget.repository;
    if (conversation == null || repository == null) return;
    setState(() => _awaitingHelpCheckId = null);
    try {
      await repository.sendAssistantMessage(
        conversation: conversation,
        text: supportGreatMessage,
      );
    } catch (_) {
      if (!mounted) return;
      _showError("Couldn't send that. Try again.");
    }
  }

  Future<void> _onHelpNo() async {
    final conversation = _conversation;
    final repository = widget.repository;
    if (conversation == null || repository == null) return;
    setState(() {
      _awaitingHelpCheckId = null;
      _connecting = true;
    });
    await Future.delayed(widget.connectingDelay);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (_closed) return;
    try {
      await repository.sendAdminMessage(
        conversation: conversation,
        text: supportStevenJoinsMessage,
        system: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showError("Couldn't connect you to Steven. Try again.");
    }
  }

  Future<void> _onClosePressed() async {
    if (_closed || _showRating) return;
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this chat?'),
        content: const Text(
          'This conversation will end. You can start a new one after.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep chatting'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close chat'),
          ),
        ],
      ),
    );
    if (close != true || !mounted) return;
    if (!_isAssisted) {
      await _closeNow();
      return;
    }
    // Chat Support closes with the rating step first (preview v14).
    setState(() => _showRating = true);
  }

  Future<void> _onRate(int stars) async {
    final conversation = _conversation;
    final repository = widget.repository;
    if (conversation == null || repository == null) return;
    try {
      await repository.rateConversation(conversation.id, stars);
    } catch (_) {
      if (!mounted) return;
      _showError("Couldn't save your rating. Try again.");
      return;
    }
    if (!mounted) return;
    setState(() => _ratingThanks = true);
    await Future.delayed(widget.ratingThanksDelay);
    if (!mounted) return;
    // Close while the thanks card is still up, so the input never
    // flashes back in between rating and the ended panel.
    await _closeNow();
    if (!mounted) return;
    setState(() {
      _showRating = false;
      _ratingThanks = false;
    });
  }

  Future<void> _closeNow() async {
    final conversation = _conversation;
    final repository = widget.repository;
    if (conversation == null || repository == null) return;
    try {
      await repository.closeConversation(conversation.id);
    } catch (_) {
      if (!mounted) return;
      _showError("Couldn't close the chat. Try again.");
    }
  }

  Future<void> _onStartNew() async {
    final repository = widget.repository;
    final user = widget.user;
    if (repository == null || user == null) return;
    setState(() {
      _awaitingHelpCheckId = null;
      _showRating = false;
      _ratingThanks = false;
      _typing = false;
      _connecting = false;
      _messages = <SupportMessage>[];
      _loading = true;
    });
    try {
      final fresh = await repository.createFreshForStudent(
        studentUid: user.uid,
        studentName: widget.studentName,
      );
      if (!mounted) return;
      setState(() {
        _conversation = fresh;
        _loading = false;
      });
      _subscribe(fresh.id);
      if (_isAssisted) {
        setState(() => _greetingPause = true);
        await Future.delayed(widget.typingDelay);
        if (mounted) setState(() => _greetingPause = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't start a new conversation. Try again.";
      });
    }
  }

  void _openChatWithAdmin() {
    final repository = widget.repository;
    final user = widget.user;
    final conversation = _conversation;
    if (repository == null || user == null || conversation == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatWithAdminScreen(
          repository: repository,
          user: user,
          studentName: widget.studentName,
          conversation: conversation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : MinecraftColors.ink;
    final title = _isAssisted ? 'Chat Support' : 'Chat with Admin';
    final subtitle = _isAssisted
        ? 'EstudyanteGO Support'
        : 'Admin · Steven Joe T. Reyes';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/estudyantego_logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.school),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: MinecraftText.heading(color: onSurface)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: MinecraftColors.grassGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '$subtitle · Online',
                          style: MinecraftText.caption(
                            color: isDark
                                ? MinecraftColors.darkSubtext
                                : const Color(0xFF5B6B52),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.repository == null || widget.user == null) {
      return const Center(
        child: Padding(
          padding: AppLayout.pagePaddingLarge,
          child: Text(
            'Chat Support is unavailable — sign in to message the '
            'EstudyanteGO team.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: AppLayout.pagePaddingLarge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              MinecraftBlockButton(
                label: 'Try again',
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _open();
                },
              ),
            ],
          ),
        ),
      );
    }
    final closed = _closed;
    return Column(
      children: [
        if (!closed && !_showRating)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: MinecraftBlockButton(
                key: const Key('chat-support-close'),
                label: 'Close this chat',
                icon: Icons.close,
                backgroundColor: MinecraftColors.heartRed,
                onPressed: _onClosePressed,
              ),
            ),
          ),
        Expanded(
          child: _buildMessageList(context),
        ),
        if (_showRating) _buildRatingCard(context),
        if (closed && !_showRating) _buildEndedPanel(context),
        if (_isAssisted && !closed && !_showRating)
          _buildQuickHelp(context),
        if (!closed && !_showRating) _buildInputRow(context),
      ],
    );
  }

  /// Messages visible right now.
  ///
  /// Direct mode (Chat with Admin) shows no bot: assistant messages
  /// (greeting, auto-replies) stay in the stored transcript for the
  /// admin inbox, but are hidden here. While a fresh conversation
  /// is still behind its greeting pause, the greeting stays hidden
  /// (the typing bubble shows instead).
  List<SupportMessage> get _visibleMessages {
    var list = _messages;
    if (!_isAssisted) {
      list = list
          .where((m) => m.sender != SupportSender.assistant)
          .toList();
    }
    if (!_greetingPause) return list;
    return list.where((m) => m.text != supportGreeting).toList();
  }

  Widget _buildMessageList(BuildContext context) {
    final messages = _visibleMessages;
    final hasStudentMessage = _messages.any(
      (m) => m.sender == SupportSender.student,
    );
    return ListView.builder(
      key: const Key('chat-support-messages'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount:
          messages.length +
          (_typing || _greetingPause ? 1 : 0) +
          (_connecting ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final message = messages[index];
          final isGreeting =
              message.sender == SupportSender.assistant &&
              message.text == supportGreeting;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBubble(context, message),
              // Inline topic chips under the greeting (preview v17)
              // — only at the start of the conversation, before the
              // student has said anything.
              if (isGreeting && _isAssisted && !hasStudentMessage)
                _buildTopicChips(context, keyPrefix: 'greeting'),
              // "Did this help?" under the latest auto-reply.
              if (message.id == _awaitingHelpCheckId)
                _buildHelpCheck(context),
            ],
          );
        }
        final extra = index - messages.length;
        if ((_typing || _greetingPause) && extra == 0) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: _TypingBubble(),
          );
        }
        return const Align(
          alignment: Alignment.center,
          child: _ConnectingBubble(),
        );
      },
    );
  }

  Widget _buildBubble(BuildContext context, SupportMessage message) {
    final isStudent = message.sender == SupportSender.student;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : MinecraftColors.ink;
    final String label;
    final Color fill;
    final Color textColor;
    switch (message.sender) {
      case SupportSender.student:
        label = supportStudentLabel;
        fill = MinecraftColors.grassGreen;
        textColor = Colors.white;
      case SupportSender.admin:
        label = supportAdminLabel;
        fill = isDark ? MinecraftColors.darkElevated : Colors.white;
        textColor = onSurface;
      case SupportSender.assistant:
        if (message.text == supportGreeting) {
          label = supportGreetingLabel;
          fill = isDark ? MinecraftColors.darkElevated : Colors.white;
          textColor = onSurface;
        } else {
          label = supportAssistantLabel;
          fill = MinecraftColors.gold;
          textColor = MinecraftColors.ink;
        }
    }
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
        border: Border.all(
          color: isDark
              ? MinecraftColors.darkBorder
              : MinecraftColors.border,
          width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
        ),
      ),
      child: Text(
        message.text,
        style: MinecraftText.body(color: textColor, fontSize: 14),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isStudent
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MinecraftText.pixel(
              color: isDark
                  ? MinecraftColors.darkSubtext
                  : const Color(0xFF5B6B52),
              fontSize: 8,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment:
                isStudent ? Alignment.centerRight : Alignment.centerLeft,
            child: bubble,
          ),
        ],
      ),
    );
  }

  /// "Did this help?" — Yes keeps the bot, No connects Steven.
  Widget _buildHelpCheck(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: MinecraftDecorations.blockCardFor(
          Theme.of(context).brightness,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Did this help?',
              style: MinecraftText.title(
                color: isDark ? Colors.white : MinecraftColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MinecraftBlockButton(
                    key: const Key('chat-support-help-yes'),
                    label: 'Yes, that helped',
                    onPressed: _onHelpYes,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MinecraftBlockButton(
                    key: const Key('chat-support-help-no'),
                    label: 'No, I need a human',
                    backgroundColor: MinecraftColors.gold,
                    onPressed: _onHelpNo,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Topic chips — the Quick Help row (and the inline greeting
  /// chips, same taps). Schedule / Fares / Account post the topic
  /// as the student's message; Chat with Admin opens the direct
  /// screen with NO message posted.
  Widget _buildTopicChips(BuildContext context, {required String keyPrefix}) {
    const topics = [
      (SupportTopic.schedule, 'Schedule'),
      (SupportTopic.fares, 'Fares'),
      (SupportTopic.account, 'Account'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (topic, label) in topics)
            ActionChip(
              key: Key('chat-support-topic-$keyPrefix-${topic.name}'),
              label: Text(label),
              onPressed: _canSend
                  ? () => _sendStudentMessage(label, forcedTopic: topic)
                  : null,
            ),
          ActionChip(
            key: Key('chat-support-topic-$keyPrefix-admin'),
            label: const Text('Chat with Admin'),
            onPressed: _canSend ? _openChatWithAdmin : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickHelp(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _quickHelpChip(
              key: const Key('quick-help-schedule'),
              label: 'Schedule',
              onPressed: () => _sendStudentMessage(
                'Schedule',
                forcedTopic: SupportTopic.schedule,
              ),
            ),
            const SizedBox(width: 8),
            _quickHelpChip(
              key: const Key('quick-help-fares'),
              label: 'Fares',
              onPressed: () => _sendStudentMessage(
                'Fares',
                forcedTopic: SupportTopic.fares,
              ),
            ),
            const SizedBox(width: 8),
            _quickHelpChip(
              key: const Key('quick-help-account'),
              label: 'Account',
              onPressed: () => _sendStudentMessage(
                'Account',
                forcedTopic: SupportTopic.account,
              ),
            ),
            const SizedBox(width: 8),
            _quickHelpChip(
              key: const Key('quick-help-admin'),
              label: 'Chat with Admin',
              onPressed: _openChatWithAdmin,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickHelpChip({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ActionChip(
      key: key,
      label: Text(label),
      onPressed: _canSend ? onPressed : null,
    );
  }

  /// Rating card shown when closing a Chat Support chat.
  Widget _buildRatingCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_ratingThanks)
            Text(
              supportThanksFeedback,
              style: MinecraftText.title(
                color: isDark ? Colors.white : MinecraftColors.ink,
              ),
            )
          else ...[
            Text(
              supportHowWasExperience,
              style: MinecraftText.title(
                color: isDark ? Colors.white : MinecraftColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    key: Key('chat-support-star-$star'),
                    onPressed: () => _onRate(star),
                    icon: const Icon(Icons.star, color: MinecraftColors.gold),
                    iconSize: 36,
                    tooltip: '$star star${star == 1 ? '' : 's'}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Ended panel: the chat is closed, input disabled.
  Widget _buildEndedPanel(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 6),
              Text(
                supportEndedMessage,
                style: MinecraftText.title(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: MinecraftBlockButton(
              key: const Key('chat-support-new-conversation'),
              label: 'Start a new conversation',
              icon: Icons.add,
              onPressed: _onStartNew,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat-support-input'),
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: 'Type a message…',
              ),
              onSubmitted: (_) => _sendStudentMessage(_inputController.text),
            ),
          ),
          const SizedBox(width: 8),
          MinecraftBlockButton(
            key: const Key('chat-support-send'),
            label: 'Send',
            icon: Icons.send,
            onPressed: () => _sendStudentMessage(_inputController.text),
          ),
        ],
      ),
    );
  }
}

/// "AI Assistant is typing…" bubble with animated dots.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? MinecraftColors.darkElevated : Colors.white,
          borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
          border: Border.all(
            color: isDark
                ? MinecraftColors.darkBorder
                : MinecraftColors.border,
            width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              supportTypingMessage,
              style: MinecraftText.body(
                color: isDark
                    ? MinecraftColors.darkSubtext
                    : const Color(0xFF5B6B52),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final step = (_controller.value * 3).floor() % 3;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= step
                                ? MinecraftColors.grassGreen
                                : MinecraftColors.stone,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// "Connecting you to an agent…" transient status bubble.
class _ConnectingBubble extends StatelessWidget {
  const _ConnectingBubble();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? MinecraftColors.darkElevated : MinecraftColors.cream,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDark
                ? MinecraftColors.darkBorder
                : MinecraftColors.border,
            width: isDark ? 1 : 2,
          ),
        ),
        child: Text(
          supportConnectingMessage,
          style: MinecraftText.bodySemiBold(
            color: isDark ? Colors.white : MinecraftColors.ink,
          ),
        ),
      ),
    );
  }
}
