// Support-reply top popup (Nov 11, 2026).
//
// When Steven replies to a student's Chat Support thread while the
// student has the app open, a dark card pops up at the top of the
// screen — the SAME shared [TopPopup] as the App Reviews admin
// replies (dark card, green checkmark circle, title, message, green
// drain bar, auto-dismiss after 5 seconds). It reads
// "EstudyanteGO replied" plus a snippet of Steven's reply. Tapping
// it opens Chat Support.
//
// Same baseline rule as [AppReplyPopupOverlay]: the popup fires only
// for replies that arrive while the app is running — a reply that
// was already waiting when the app opened (or when the student
// signed in) shows nowhere as a popup, so the student is never
// greeted by a popup for an old reply on every launch. The
// auto-handoff message ("Hi, I'm Steven, the admin…") never pops:
// it is written by the student's own client while the student is
// watching the chat, and it doesn't bump the unread count (see
// `chat_support.dart`).
//
// This is the visible alert only. The thread itself carries the
// reply persistently; there is no bell badge for support replies
// and no push (in-app only, no FCM).

import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_support.dart';
import 'top_popup.dart';

/// How long the reply popup stays up before auto-dismissing.
const Duration supportReplyPopupDuration = Duration(seconds: 5);

/// Wraps the shell's tab content and shows the reply popup at the
/// top when a new admin reply arrives for the signed-in student.
/// When [repository] or [userId] is null (Firebase not configured
/// / signed out), it just passes [child] through.
class SupportReplyPopupOverlay extends StatefulWidget {
  const SupportReplyPopupOverlay({
    super.key,
    required this.repository,
    required this.userId,
    required this.onOpenChat,
    required this.child,
  });

  final SupportRepository? repository;
  final String? userId;

  /// Opens Chat Support (the shell pushes the screen).
  final VoidCallback onOpenChat;

  final Widget child;

  @override
  State<SupportReplyPopupOverlay> createState() =>
      _SupportReplyPopupOverlayState();
}

class _SupportReplyPopupOverlayState extends State<SupportReplyPopupOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drainController;

  /// The reply currently shown in the popup, or null.
  SupportConversation? _current;

  /// Unread counts already accounted for (baseline + shown),
  /// keyed by conversation id.
  final Map<String, int> _seenUnread = <String, int>{};

  /// True until the first snapshot arrives — that snapshot is the
  /// baseline (replies already waiting), never a popup.
  bool _isFirstSnapshot = true;

  StreamSubscription<List<SupportConversation>>? _subscription;

  @override
  void initState() {
    super.initState();
    _drainController = AnimationController(
      vsync: this,
      duration: supportReplyPopupDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _current = null);
        }
      });
    _subscribe();
  }

  @override
  void didUpdateWidget(SupportReplyPopupOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.userId != widget.userId) {
      _unsubscribe();
      _seenUnread.clear();
      _isFirstSnapshot = true;
      _current = null;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    _drainController.dispose();
    super.dispose();
  }

  void _subscribe() {
    final repository = widget.repository;
    final userId = widget.userId;
    if (repository == null || userId == null) return;
    _subscription = repository.watchForStudent(userId).listen(
      _onConversations,
      onError: (_) {
        // A stream error must never break the shell — the thread
        // itself carries the reply instead.
      },
    );
  }

  void _unsubscribe() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _onConversations(List<SupportConversation> conversations) {
    if (!mounted) return;
    if (_isFirstSnapshot) {
      // Baseline: replies already waiting when the app opened show
      // nowhere as a popup.
      _isFirstSnapshot = false;
      for (final c in conversations) {
        _seenUnread[c.id] = c.unreadForStudent;
      }
      return;
    }
    // New arrivals: a thread whose student-unread count grew and
    // whose last message is from the admin.
    SupportConversation? fresh;
    for (final c in conversations) {
      final seen = _seenUnread[c.id] ?? 0;
      _seenUnread[c.id] = c.unreadForStudent;
      if (c.unreadForStudent > seen && c.lastSender == 'admin') {
        fresh ??= c;
      }
    }
    if (fresh == null) return;
    setState(() => _current = fresh);
    _drainController.forward(from: 0);
  }

  /// Tapping the popup opens Chat Support with the full reply.
  /// The popup dismisses; opening the chat marks the reply read,
  /// so no stale badge survives.
  void _openChat() {
    if (_current == null) return;
    _drainController.stop();
    setState(() => _current = null);
    widget.onOpenChat();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: TopPopup(
              progress: _drainController,
              title: supportReplyPopupTitle,
              message: _current!.lastMessage,
              messageMaxLines: 2,
              onTap: _openChat,
            ),
          ),
      ],
    );
  }
}
