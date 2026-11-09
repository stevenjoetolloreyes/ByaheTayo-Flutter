// Admin-reply top popup (Nov 9, 2026).
//
// When the admin replies to a student's review while the student
// has the app open, a dark card pops up at the top of the screen —
// the SAME style as the rating flow's "Thank you!" popup (dark
// card, green checkmark circle, title, message, green drain bar,
// auto-dismiss after 5 seconds). It reads "EstudyanteGO replied
// to your review." plus a snippet of the admin's reply. Tapping
// it opens the Notifications sheet with the full reply.
//
// This is the visible alert. The bell unread badge and the sheet
// entry are the persistent parts. The popup fires only for replies
// that arrive while the app is running — a reply that was already
// waiting when the app opened (or when the student signed in)
// shows on the bell only, not as a popup, so the student is never
// greeted by a popup for an old reply on every launch.
// No white bar, no top banner beyond this popup.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_review_notifications.dart';
import 'top_popup.dart';

/// How long the reply popup stays up before auto-dismissing.
const Duration appReplyPopupDuration = Duration(seconds: 5);

/// Wraps the shell's tab content and shows the reply popup at the
/// top when a new admin reply arrives for the signed-in student.
/// When [repository] or [userId] is null (Firebase not configured
/// / signed out), it just passes [child] through.
class AppReplyPopupOverlay extends StatefulWidget {
  const AppReplyPopupOverlay({
    super.key,
    required this.repository,
    required this.userId,
    required this.child,
  });

  final AppReviewNotificationRepository? repository;
  final String? userId;
  final Widget child;

  @override
  State<AppReplyPopupOverlay> createState() => _AppReplyPopupOverlayState();
}

class _AppReplyPopupOverlayState extends State<AppReplyPopupOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drainController;

  /// The reply currently shown in the popup, or null.
  AppReviewNotification? _current;

  /// Notifications already accounted for (baseline + shown).
  final Set<String> _seenIds = <String>{};

  /// True until the first snapshot arrives — that snapshot is the
  /// baseline (replies already waiting), never a popup.
  bool _isFirstSnapshot = true;

  StreamSubscription<List<AppReviewNotification>>? _subscription;

  @override
  void initState() {
    super.initState();
    _drainController = AnimationController(
      vsync: this,
      duration: appReplyPopupDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _current = null);
        }
      });
    _subscribe();
  }

  @override
  void didUpdateWidget(AppReplyPopupOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.userId != widget.userId) {
      _unsubscribe();
      _seenIds.clear();
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
    _subscription = repository.watchForUser(userId).listen(
      _onNotifications,
      onError: (_) {
        // A stream error must never break the shell — the bell
        // badge and the sheet carry the notification instead.
      },
    );
  }

  void _unsubscribe() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _onNotifications(List<AppReviewNotification> notifications) {
    if (!mounted) return;
    if (_isFirstSnapshot) {
      // Baseline: replies already waiting when the app opened show
      // on the bell only, not as a popup.
      _isFirstSnapshot = false;
      _seenIds.addAll(notifications.map((n) => n.id));
      return;
    }
    // New arrivals: unread notifications we have not seen yet.
    // The stream is newest first, so the first fresh one is the
    // newest reply.
    final fresh = notifications
        .where((n) => !n.read && !_seenIds.contains(n.id))
        .toList();
    _seenIds.addAll(notifications.map((n) => n.id));
    if (fresh.isEmpty) return;
    setState(() => _current = fresh.first);
    _drainController.forward(from: 0);
  }

  /// Tapping the popup opens the Notifications sheet with the full
  /// reply (same sheet the bell opens). The popup dismisses, and
  /// the notifications are marked read when the sheet closes, so
  /// the bell badge clears.
  void _openSheet() {
    if (_current == null) return;
    _drainController.stop();
    setState(() => _current = null);
    final repository = widget.repository;
    final userId = widget.userId;
    if (repository == null || userId == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => AppReviewNotificationsSheet(
        repository: repository,
        userId: userId,
      ),
    ).then((_) {
      unawaited(repository.markAllRead(userId));
    });
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
              title: 'EstudyanteGO replied to your review.',
              message: _current!.replyText,
              messageMaxLines: 2,
              onTap: _openSheet,
            ),
          ),
      ],
    );
  }
}

/// (The 5-second reply popup is the shared [TopPopup] — see
/// `top_popup.dart` — shown by the overlay above, with the reply
/// snippet as its message, max 2 lines.)
