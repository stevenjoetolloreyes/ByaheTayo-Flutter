// Support Inbox — admin side (Nov 11, 2026).
//
// Account → Admin Access → "Support Inbox" (preview v15). Steven's
// list of student conversations: first name, last message, time,
// unread badge. Tapping a conversation opens that chat — student
// messages on the left, Steven's replies on the right, working
// reply box. Opening an unread conversation clears its badge; the
// back arrow returns to the list.
//
// The admin sees the FULL transcript, including the assistant's
// greeting and auto-replies, so Steven always knows what the
// student was already told before he replies. When Steven replies,
// the student gets a top popup "EstudyanteGO replied" (see
// `support_reply_popup.dart`) — the same style as the App Reviews
// admin replies. A closed conversation shows "This chat has ended."
// and its reply box is disabled: the student starts a new
// conversation instead.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'chat_support.dart';
import 'minecraft_theme.dart';
import 'top_popup.dart';

/// The Support Inbox list (body only — the Account tab wraps it in
/// a Scaffold with an AppBar titled "Support Inbox", like
/// [AppReviewsScreen]).
class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({
    super.key,
    required this.repository,
    required this.adminEmail,
  });

  /// Null when Firebase is not configured — the screen shows an
  /// honest "unavailable" state instead of crashing.
  final SupportRepository? repository;

  /// The signed-in admin's email (recorded on each reply).
  final String? adminEmail;

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  /// The conversations stream, created once — never in build, or
  /// every rebuild would resubscribe and re-emit.
  Stream<List<SupportConversation>>? _conversationsStream;

  @override
  void initState() {
    super.initState();
    _conversationsStream = widget.repository?.watchAllForAdmin();
  }

  void _openConversation(SupportConversation conversation) {
    final repository = widget.repository;
    if (repository == null) return;
    // Opening an unread conversation clears its badge.
    if (conversation.unreadForAdmin > 0) {
      unawaited(
        repository.markAdminRead(conversation.id).catchError((_) {}),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(conversation.studentName),
          ),
          body: SupportAdminChatScreen(
            repository: repository,
            conversation: conversation,
            adminEmail: widget.adminEmail,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Padding(
          padding: AppLayout.pagePaddingLarge,
          child: Text(
            'Support Inbox is unavailable — the app is not connected '
            'to Firebase.',
          ),
        ),
      );
    }
    return StreamBuilder<List<SupportConversation>>(
      stream: _conversationsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: AppLayout.pagePaddingLarge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Support Inbox', style: AppText.headingStrong),
                SizedBox(height: AppSpacing.s8),
                Text("Couldn't load conversations. Try again."),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: AppLayout.pagePaddingLarge,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final conversations =
            snapshot.data ?? const <SupportConversation>[];
        if (conversations.isEmpty) {
          return Padding(
            padding: AppLayout.pagePaddingLarge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Support Inbox', style: AppText.headingStrong),
                SizedBox(height: AppSpacing.s8),
                Text('No support conversations yet.'),
                SizedBox(height: AppSpacing.s4),
                Text(
                  'When a student messages Chat Support, their '
                  'conversation will appear here.',
                  style: AppText.caption,
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: AppLayout.pagePaddingLarge,
          children: [
            Text('Support Inbox', style: AppText.headingStrong),
            const SizedBox(height: AppSpacing.s12),
            for (final conversation in conversations)
              _InboxRow(
                conversation: conversation,
                onTap: () => _openConversation(conversation),
              ),
          ],
        );
      },
    );
  }
}

/// Total unread student messages across all threads, as a small
/// red count pill for the Account tab's "Support Inbox" row —
/// Steven sees at a glance that a student is waiting. Renders
/// nothing when there is nothing unread (or when Firebase is not
/// configured). Owns its stream (created once in initState).
class SupportInboxUnreadBadge extends StatefulWidget {
  const SupportInboxUnreadBadge({super.key, required this.repository});

  /// Null when Firebase is not configured.
  final SupportRepository? repository;

  @override
  State<SupportInboxUnreadBadge> createState() =>
      _SupportInboxUnreadBadgeState();
}

class _SupportInboxUnreadBadgeState extends State<SupportInboxUnreadBadge> {
  Stream<List<SupportConversation>>? _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.repository?.watchAllForAdmin();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<SupportConversation>>(
      stream: stream,
      builder: (context, snapshot) {
        final conversations =
            snapshot.data ?? const <SupportConversation>[];
        final total = conversations.fold<int>(
          0,
          (sum, c) => sum + c.unreadForAdmin,
        );
        if (total <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: MinecraftColors.heartRed,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$total',
            style: MinecraftText.button(color: Colors.white, fontSize: 12),
          ),
        );
      },
    );
  }
}

/// One inbox row: first initial avatar, first name, last message,
/// time, unread badge.
class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.conversation, required this.onTap});

  final SupportConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lastAt = conversation.lastMessageAt;
    final initial = conversation.studentName.isNotEmpty
        ? conversation.studentName[0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: MinecraftDecorations.blockCardFor(
            Theme.of(context).brightness,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: MinecraftColors.grassGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? MinecraftColors.darkBorder
                        : MinecraftColors.border,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: MinecraftText.heading(
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.studentName,
                            style: MinecraftText.title(
                              color: isDark
                                  ? Colors.white
                                  : MinecraftColors.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (lastAt != null)
                          Text(
                            supportInboxTime(lastAt),
                            style: MinecraftText.caption(
                              color: isDark
                                  ? MinecraftColors.darkSubtext
                                  : const Color(0xFF5B6B52),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conversation.lastMessage.isEmpty
                          ? 'New conversation'
                          : conversation.lastMessage,
                      style: MinecraftText.body(
                        color: isDark
                            ? MinecraftColors.darkSubtext
                            : const Color(0xFF5B6B52),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (conversation.unreadForAdmin > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: MinecraftColors.heartRed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${conversation.unreadForAdmin}',
                    style: MinecraftText.button(
                      color: Colors.white,
                      fontSize: 12,
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
}

/// One conversation from the admin side: full transcript (student
/// left, Steven right), working reply box. The admin is Steven Joe
/// T. Reyes — the header subtitle says so (preview v15).
class SupportAdminChatScreen extends StatefulWidget {
  const SupportAdminChatScreen({
    super.key,
    required this.repository,
    required this.conversation,
    required this.adminEmail,
  });

  /// Null is not expected here (the list screen guards it), but
  /// the screen still degrades honestly if it ever is.
  final SupportRepository? repository;

  /// The thread to open.
  final SupportConversation conversation;

  /// The signed-in admin's email.
  final String? adminEmail;

  @override
  State<SupportAdminChatScreen> createState() =>
      _SupportAdminChatScreenState();
}

class _SupportAdminChatScreenState extends State<SupportAdminChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<List<SupportMessage>>? _messagesSub;
  StreamSubscription<SupportConversation?>? _conversationSub;

  List<SupportMessage> _messages = [];
  SupportConversation? _conversation;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    final repository = widget.repository;
    if (repository == null) return;
    _messagesSub =
        repository.watchMessages(widget.conversation.id).listen(
      (messages) {
        if (!mounted) return;
        setState(() => _messages = messages);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        });
      },
      onError: (_) {},
    );
    _conversationSub = repository
        .watchConversation(widget.conversation.id)
        .listen(
      (conversation) {
        if (!mounted || conversation == null) return;
        setState(() => _conversation = conversation);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    unawaited(_messagesSub?.cancel());
    unawaited(_conversationSub?.cancel());
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _closed => _conversation?.closed ?? false;

  Future<void> _sendReply() async {
    final text = _inputController.text.trim();
    final conversation = _conversation;
    final repository = widget.repository;
    if (text.isEmpty || conversation == null || repository == null) return;
    if (_closed) return;
    _inputController.clear();
    try {
      await repository.sendAdminMessage(
        conversation: conversation,
        text: text,
      );
    } catch (_) {
      if (!mounted) return;
      _inputController.text = text;
      TopPopup.show(context, message: "Couldn't send your reply. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Padding(
          padding: AppLayout.pagePaddingLarge,
          child: Text(
            'This conversation is unavailable — the app is not '
            'connected to Firebase.',
          ),
        ),
      );
    }
    final conversation = _conversation ?? widget.conversation;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MinecraftColors.grassGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? MinecraftColors.darkBorder
                        : MinecraftColors.border,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  conversation.studentName.isNotEmpty
                      ? conversation.studentName[0].toUpperCase()
                      : '?',
                  style: MinecraftText.heading(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.studentName,
                      style: MinecraftText.heading(
                        color: isDark ? Colors.white : MinecraftColors.ink,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'Student · via Chat Support',
                      style: MinecraftText.caption(
                        color: isDark
                            ? MinecraftColors.darkSubtext
                            : const Color(0xFF5B6B52),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('support-admin-messages'),
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _buildBubble(context, _messages[index]);
            },
          ),
        ),
        if (_closed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
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
          )
        else
          Container(
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
                    key: const Key('support-admin-input'),
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Reply as Steven…',
                    ),
                    onSubmitted: (_) => _sendReply(),
                  ),
                ),
                const SizedBox(width: 8),
                MinecraftBlockButton(
                  key: const Key('support-admin-send'),
                  label: 'Send',
                  icon: Icons.send,
                  onPressed: _sendReply,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBubble(BuildContext context, SupportMessage message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : MinecraftColors.ink;
    // The admin's own messages sit on the right; the student's (and
    // the assistant's transcript lines) on the left.
    final isAdmin = message.sender == SupportSender.admin;
    final String label;
    final Color fill;
    final Color textColor;
    switch (message.sender) {
      case SupportSender.student:
        label = _studentLabel;
        fill = isDark ? MinecraftColors.darkElevated : Colors.white;
        textColor = onSurface;
      case SupportSender.admin:
        label = supportAdminLabel;
        fill = MinecraftColors.grassGreen;
        textColor = Colors.white;
      case SupportSender.assistant:
        label = message.text == supportGreeting
            ? supportGreetingLabel
            : supportAssistantLabel;
        fill = MinecraftColors.gold;
        textColor = MinecraftColors.ink;
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
        crossAxisAlignment:
            isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                isAdmin ? Alignment.centerRight : Alignment.centerLeft,
            child: bubble,
          ),
        ],
      ),
    );
  }

  /// Label for a student bubble in the admin view: the student's
  /// first name, uppercased.
  String get _studentLabel {
    final name = _conversation?.studentName ?? widget.conversation.studentName;
    return name.toUpperCase();
  }
}
