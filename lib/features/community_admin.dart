// Post approvals — the admin screen for community submissions.
//
// PLAIN LANGUAGE: community posts live on THIS DEVICE ONLY, and
// review here is done only by allowlisted admin accounts (see
// admin_access.dart) — the previous device-owner rule was replaced by
// the email allowlist. There is no server-side review, no moderator
// team, and nothing is uploaded. New submissions arrive Pending
// ("Pending verification"). Approving marks a post Published (it stays
// in the main list); rejecting hides it from the main list (it stays
// here until approved again or deleted). The sample CTransco
// submission arrives Pending like any other post and needs approval
// here before it counts as published.
import 'package:flutter/material.dart';

import 'community_posts.dart';
import 'vehicle_categories.dart';

class CommunityAdminScreen extends StatelessWidget {
  const CommunityAdminScreen({
    super.key,
    required this.posts,
    required this.onChanged,
  });

  /// All posts on the device (pending, published, and rejected).
  final List<CommunityPost> posts;

  /// Called with the updated list after any approve/reject/delete,
  /// so the caller can persist it and refresh its own list.
  final ValueChanged<List<CommunityPost>> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending =
        posts.where((p) => p.status == PostStatus.pending).toList();
    final published =
        posts.where((p) => p.status == PostStatus.approved).toList();
    final rejected =
        posts.where((p) => p.status == PostStatus.rejected).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Post approvals')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Review is restricted to admin accounts, and posts stay on '
            'this device only. There is no server-side review — posts '
            'are never uploaded.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _section(
            context,
            'Pending verification',
            pending,
            'No submissions waiting for review.',
            actions: (post) => [
              FilledButton(
                onPressed: () => _setStatus(post, PostStatus.approved),
                child: const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: () => _setStatus(post, PostStatus.rejected),
                child: const Text('Reject'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            context,
            'Published',
            published,
            'No published posts yet.',
            actions: (post) => [
              OutlinedButton(
                onPressed: () => _setStatus(post, PostStatus.rejected),
                child: const Text('Reject'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            context,
            'Rejected',
            rejected,
            'No rejected posts.',
            actions: (post) => [
              FilledButton(
                onPressed: () => _setStatus(post, PostStatus.approved),
                child: const Text('Approve'),
              ),
              OutlinedButton(
                onPressed: () => _delete(context, post),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setStatus(CommunityPost post, PostStatus status) {
    onChanged(
      posts
          .map((p) => identical(p, post) ? p.copyWith(status: status) : p)
          .toList(),
    );
  }

  Future<void> _delete(BuildContext context, CommunityPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: Text(
          'This removes "${post.displayTitle}" from this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onChanged(posts.where((p) => !identical(p, post)).toList());
    }
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
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (sectionPosts.isEmpty)
          Text(emptyText, style: TextStyle(color: scheme.onSurfaceVariant))
        else
          for (final post in sectionPosts) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.displayTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (post.vehicles.isNotEmpty) ...[
                    const SizedBox(height: 4),
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
                    const SizedBox(height: 4),
                    for (final line in post.fareLines) Text(line),
                  ],
                  if (post.operatorName.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Operator: ${post.operatorName}'),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: actions(post),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}
