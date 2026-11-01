// Friends tab — friend features only.
//
// The Community section used to live here; it moved to its own
// Communities nav destination (see communities_tab.dart) at the user's
// request. This tab keeps only: Your Friends, My Friend Code, and
// Chats, shown directly (the old Posts/Chat toggle went with the
// community content — Posts showed community posts, so it no longer
// belongs here).
//
// HONEST STATE: this Flutter app has NO social backend yet (no
// Firebase, no friend system, no chats). So this tab shows the social
// structure only — no invented friends, no invented friend code, no
// invented chats. Every action that needs a backend says so plainly in
// a SnackBar instead of faking success.
//
// Presentation follows the approved Premium Dark Minimalist design
// (the iPhone Map preview): dark charcoal cards with subtle outlines,
// emerald accent, outline icons — via the shared CardTheme in main.dart.
import 'package:flutter/material.dart';

/// Shown for every Friends action that needs a backend (not ported yet).
const _notConnectedMessage =
    'Hindi pa available — hindi pa naka-connect ang feature na ito.';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  void _showNotConnected() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(_notConnectedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'People you travel with',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        const Text(
          'Friends',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          icon: Icons.people_outlined,
          title: 'Your Friends',
          body: 'No friends added yet.',
          note: 'Friend codes and chats are not connected yet, so no people are shown here.',
          actionLabel: 'Add a friend',
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.badge_outlined,
          title: 'My Friend Code',
          body: "You don't have a friend code yet.",
          note: 'Friend codes are not issued yet — no code is shown because none exists.',
          actionLabel: 'Get my code',
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.chat_bubble_outline,
          title: 'Chats',
          body: 'No chats yet.',
          note: 'Chats are not connected yet, so no conversations are shown here.',
        ),
        const SizedBox(height: 16),
        Text(
          'Friend data is not stored or synced.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String body,
    required String note,
    String? actionLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            const SizedBox(height: 4),
            Text(
              note,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _showNotConnected,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
