// App Reviews — review detail (Nov 9, 2026).
//
// The detail view an admin opens by tapping a review in App
// Reviews: the full review, the Admin comments thread, and a
// composer. Sending a reply saves it on the review in Firestore
// (and creates the student's notification — see app_reviews.dart).
// The thread updates live via the rating stream, so the reply
// appears as soon as it is saved.

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'app_reviews.dart';
import 'student/student_data.dart';

/// The review detail screen (body only — the caller wraps it in a
/// Scaffold with an AppBar titled "Review").
class AppReviewDetailScreen extends StatefulWidget {
  const AppReviewDetailScreen({
    super.key,
    required this.repository,
    required this.ratingId,
    required this.adminEmail,
  });

  /// Null when Firebase is not configured — replies are then
  /// disabled and an honest note is shown.
  final AppReviewsRepository? repository;

  /// The `app_ratings` doc id.
  final String ratingId;

  /// The signed-in admin's email (recorded on each reply).
  final String? adminEmail;

  @override
  State<AppReviewDetailScreen> createState() =>
      _AppReviewDetailScreenState();
}

class _AppReviewDetailScreenState extends State<AppReviewDetailScreen> {
  final _replyController = TextEditingController();
  bool _sending = false;
  String? _error;

  /// The rating stream, created once — never in build, or every
  /// rebuild would resubscribe and re-emit.
  Stream<AppRating?>? _ratingStream;

  @override
  void initState() {
    super.initState();
    _ratingStream = widget.repository?.watchOne(widget.ratingId);
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply(AppRating rating) async {
    final repository = widget.repository;
    final adminEmail = widget.adminEmail;
    final text = _replyController.text.trim();
    if (text.isEmpty || repository == null || adminEmail == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await repository.addReply(
        rating: rating,
        text: text,
        adminEmail: adminEmail,
      );
      if (!mounted) return;
      _replyController.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't send your reply. Try again.";
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
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
            'This review is unavailable — the app is not connected to Firebase.',
          ),
        ),
      );
    }
    return StreamBuilder<AppRating?>(
      stream: _ratingStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: AppLayout.pagePaddingLarge,
              child: Text("Couldn't load this review. Try again."),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rating = snapshot.data;
        if (rating == null) {
          return const Center(
            child: Padding(
              padding: AppLayout.pagePaddingLarge,
              child: Text('This review was removed.'),
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _ReviewSummary(rating: rating),
                  const SizedBox(height: 20),
                  const Text(
                    'Admin replies',
                    style: AppText.headingStrong,
                  ),
                  const SizedBox(height: 12),
                  if (rating.adminReplies.isEmpty)
                    const Text(
                      'No replies yet. Your reply will appear in the student\'s Notifications.',
                      style: AppText.caption,
                    )
                  else
                    for (final reply in rating.adminReplies)
                      _ReplyBubble(reply: reply),
                ],
              ),
            ),
            _Composer(
              controller: _replyController,
              sending: _sending,
              error: _error,
              canSend: widget.adminEmail != null,
              onSend: () => _sendReply(rating),
            ),
          ],
        );
      },
    );
  }
}

/// The full review, shown at the top of the detail view.
class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.rating});

  final AppRating rating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final submittedAt = rating.submittedAt;
    final satisfied = rating.satisfied;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (rating.stars != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(
                        i <= rating.stars!
                            ? Icons.star
                            : Icons.star_border,
                        color: const Color(0xFFFFB300),
                        size: 20,
                      ),
                  ],
                )
              else
                const Text('No stars', style: AppText.caption),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: satisfied
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  satisfied ? 'Satisfied' : 'Not yet',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (submittedAt != null)
                Text(formatDate(submittedAt), style: AppText.caption),
            ],
          ),
          if (rating.topics.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final topic in rating.topics)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(topic, style: AppText.small),
                  ),
              ],
            ),
          ],
          if (rating.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(rating.comment, style: AppText.body),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16),
              const SizedBox(width: 4),
              const Text('Student', style: AppText.caption),
              if (rating.appVersion.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text('v${rating.appVersion}', style: AppText.caption),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One reply in the Admin comments thread.
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply});

  final AdminReply reply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final createdAt = reply.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reply.text, style: AppText.body),
          const SizedBox(height: 6),
          Text(
            [
              if (reply.adminEmail.isNotEmpty) reply.adminEmail,
              if (createdAt != null) formatDate(createdAt),
            ].join(' · '),
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// The reply composer, pinned at the bottom of the detail view.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.error,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final String? error;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            Text(error!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: canSend && !sending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write a reply…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: canSend && !sending ? onSend : null,
                icon: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                tooltip: 'Send reply',
              ),
            ],
          ),
          if (!canSend) ...[
            const SizedBox(height: 8),
            const Text(
              'Replies need a signed-in admin account.',
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}
