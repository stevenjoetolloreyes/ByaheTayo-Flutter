// Post approvals — the admin screen for community submissions.
//
// TWO KINDS, kept visibly separate: SHARED posts (Firestore) are
// reviewed here by allowlisted admin accounts (see admin_access.dart)
// and become visible to all users once approved; LOCAL posts stay on
// this device and keep their old device-only approval behavior. The
// sample CTransco submission lives in Firestore only (created once
// by an admin opening the Communities tab, approved once, never
// re-created).
// Rejected posts stay visible here until approved again or deleted.
import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'community_post_repository.dart';
import 'community_posts.dart';
import 'ios_components.dart';
import 'vehicle_categories.dart';

class CommunityAdminScreen extends StatefulWidget {
  const CommunityAdminScreen({
    super.key,
    required this.localPosts,
    required this.onLocalChanged,
    this.sharedPosts = const [],
    this.postRepository,
    this.onSharedChanged,
  });

  /// Device-only posts (pending, published, and rejected).
  final List<CommunityPost> localPosts;

  /// Called with the updated local list after any approve/reject/
  /// delete, so the caller can persist it.
  final ValueChanged<List<CommunityPost>> onLocalChanged;

  /// Shared posts visible to the admin (approved + all pending).
  final List<CommunityPost> sharedPosts;

  /// Firestore storage for shared-post actions. Null when sharing
  /// isn't configured — shared review is then unavailable.
  final PostRepository? postRepository;

  /// Called after a shared-post action succeeds, so the caller can
  /// reload its shared list.
  final VoidCallback? onSharedChanged;

  @override
  State<CommunityAdminScreen> createState() => _CommunityAdminScreenState();
}

class _CommunityAdminScreenState extends State<CommunityAdminScreen> {
  late List<CommunityPost> _local = widget.localPosts;
  late List<CommunityPost> _shared = widget.sharedPosts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sharedPending =
        _shared.where((p) => p.status == PostStatus.pending).toList();
    final sharedPublished =
        _shared.where((p) => p.status == PostStatus.approved).toList();
    final sharedRejected =
        _shared.where((p) => p.status == PostStatus.rejected).toList();
    final localPending =
        _local.where((p) => p.status == PostStatus.pending).toList();
    final localPublished =
        _local.where((p) => p.status == PostStatus.approved).toList();
    final localRejected =
        _local.where((p) => p.status == PostStatus.rejected).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Post approvals')),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          Text(
            'Shared posts are reviewed by admin accounts and become '
            'visible to all users once approved. Local posts stay on '
            'this device only.',
            style: AppText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppLayout.cardGap),
          if (widget.postRepository == null) ...[
            Text(
              "Shared-post review isn't available — the shared "
              'database hasn\'t been set up.',
              style: AppText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppLayout.cardGap),
          ] else ...[
            _section(
              context,
              'Shared posts — Waiting Approval',
              sharedPending,
              'No shared submissions waiting for review.',
              actions: (post) => [
                FilledButton(
                  onPressed: () =>
                      _setSharedStatus(post, PostStatus.approved),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () => _rejectShared(context, post),
                  child: const Text('Reject'),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            _section(
              context,
              'Shared posts — Published',
              sharedPublished,
              'No published shared posts yet.',
              actions: (post) => [
                OutlinedButton(
                  onPressed: () => _rejectShared(context, post),
                  child: const Text('Reject'),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            _section(
              context,
              'Shared posts — Rejected',
              sharedRejected,
              'No rejected shared posts.',
              actions: (post) => [
                FilledButton(
                  onPressed: () =>
                      _setSharedStatus(post, PostStatus.approved),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () => _deleteShared(context, post),
                  child: const Text('Delete'),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
          ],
          _section(
            context,
            'Local posts — Waiting Approval',
            localPending,
            'No local submissions waiting for review.',
            actions: (post) => [
              FilledButton(
                onPressed: () => _setLocalStatus(post, PostStatus.approved),
                child: const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: () => _setLocalStatus(post, PostStatus.rejected),
                child: const Text('Reject'),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.cardGap),
          _section(
            context,
            'Local posts — Published',
            localPublished,
            'No published local posts yet.',
            actions: (post) => [
              OutlinedButton(
                onPressed: () => _setLocalStatus(post, PostStatus.rejected),
                child: const Text('Reject'),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.cardGap),
          _section(
            context,
            'Local posts — Rejected',
            localRejected,
            'No rejected local posts.',
            actions: (post) => [
              FilledButton(
                onPressed: () => _setLocalStatus(post, PostStatus.approved),
                child: const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: () => _deleteLocal(context, post),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setLocalStatus(CommunityPost post, PostStatus status) {
    final updated = _local
        .map((p) => identical(p, post) ? p.copyWith(status: status) : p)
        .toList();
    setState(() => _local = updated);
    widget.onLocalChanged(updated);
  }

  Future<void> _deleteLocal(
    BuildContext context,
    CommunityPost post,
  ) async {
    final confirmed = await _confirmDelete(context, post, local: true);
    if (confirmed != true) return;
    final updated = _local.where((p) => !identical(p, post)).toList();
    setState(() => _local = updated);
    widget.onLocalChanged(updated);
  }

  Future<void> _setSharedStatus(
    CommunityPost post,
    PostStatus status, {
    String? rejectionReason,
    bool clearRejectionReason = false,
  }) async {
    final repository = widget.postRepository;
    if (repository == null) return;
    try {
      await repository.updatePostStatus(
        post,
        status,
        rejectionReason: rejectionReason,
        clearRejectionReason: clearRejectionReason,
      );
      if (!mounted) return;
      setState(() {
        _shared = _shared
            .map((p) => identical(p, post)
                ? p.copyWith(
                    status: status,
                    rejectionReason: rejectionReason,
                    clearRejectionReason: clearRejectionReason,
                  )
                : p)
            .toList();
      });
      widget.onSharedChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sharedPostsErrorMessage(e))),
      );
    }
  }

  /// Shared reject flow: asks for an optional reason, shown only to
  /// the post's author on their rejected post. An empty reason clears
  /// any stale reason from an earlier rejection cycle. Local rejects
  /// keep their old direct behavior — no reason, no dialog.
  /// No TextEditingController here: the dialog's exit transition
  /// still builds the field after pop, so disposing a controller on
  /// pop would use it after disposal — the text is captured with
  /// onChanged instead.
  Future<void> _rejectShared(
    BuildContext context,
    CommunityPost post,
  ) async {
    var reasonText = '';
    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this post?'),
        content: TextField(
          onChanged: (value) => reasonText = value,
          maxLength: kMaxRejectionReasonLength,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            helperText: 'Shown only to the author of this post.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(reasonText.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _setSharedStatus(
      post,
      PostStatus.rejected,
      rejectionReason: reason.isEmpty ? null : reason,
      clearRejectionReason: reason.isEmpty,
    );
  }

  Future<void> _deleteShared(
    BuildContext context,
    CommunityPost post,
  ) async {
    final repository = widget.postRepository;
    if (repository == null) return;
    // Captured before any await: the parameter context must not be
    // used across async gaps.
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirmDelete(context, post, local: false);
    if (confirmed != true) return;
    try {
      await repository.deletePost(post);
      if (!mounted) return;
      setState(() {
        _shared = _shared.where((p) => !identical(p, post)).toList();
      });
      widget.onSharedChanged?.call();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(sharedPostsErrorMessage(e))),
      );
    }
  }

  Future<bool?> _confirmDelete(
    BuildContext context,
    CommunityPost post, {
    required bool local,
  }) {
    return showIosAlert<bool>(
      context: context,
      title: 'Delete this post?',
      message: local
          ? 'This removes "${post.displayTitle}" from this device. '
              'This cannot be undone.'
          : 'This removes "${post.displayTitle}" for all users. '
              'This cannot be undone.',
      actions: const [
        IosAlertAction<bool>('Cancel', value: false),
        IosAlertAction<bool>(
          'Delete',
          value: true,
          isDestructive: true,
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<CommunityPost> sectionPosts,
    String emptyText, {
    required List<Widget> Function(CommunityPost post) actions,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.sectionTitle,
        ),
        const SizedBox(height: AppSpacing.s8),
        if (sectionPosts.isEmpty)
          Text(emptyText, style: TextStyle(color: scheme.onSurfaceVariant))
        else
          for (final post in sectionPosts) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(AppLayout.cardRadius),
              ),
              padding: AppLayout.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.displayTitle,
                    style: AppText.cardTitle,
                  ),
                  if (post.vehicles.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final vehicle in post.vehicles)
                          Chip(
                            avatar: Icon(vehicleIcon(vehicle), size: 18),
                            label: Text(vehicleLabel(vehicle)),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  if (post.fareLines.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    for (final line in post.fareLines) Text(line),
                  ],
                  if (post.operatorName.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text('Operator: ${post.operatorName}'),
                  ],
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: actions(post),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
      ],
    );
  }
}
