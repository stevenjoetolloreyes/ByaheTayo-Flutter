// Friends tab — premium social travel design.
//
// Sections, in order: My Friends (real local friends + message
// actions), My Friend Code (real on-device code + real QR + real
// copy/share), Friend Requests (incoming + outgoing), Chats.
//
// HONESTY RULES — this app has NO social backend, so:
// - The friend code is genuinely generated on-device (UUID v4,
//   persisted in SharedPreferences) and encoded in a real QR code.
//   Copy uses the real clipboard; Share uses the real share sheet.
// - Search filters ONLY actually-stored local friends. With none
//   stored, the section shows its honest empty state.
// - Add Friend shows the real code/QR share path plus an honest note
//   that cross-device adding needs cloud sync (not yet enabled).
//   There is NO code-entry field: without a backend a typed code
//   cannot be validated, so it must never be presented as a friend.
// - Friend Requests cannot arrive or be delivered without a backend:
//   both subsections show premium empty states, and NO Accept/Decline
//   buttons are rendered for requests that do not exist.
// - Chats / real-time messaging / notifications cannot be real
//   without a backend: the conversation list shows its honest empty
//   state only. No fake conversations, last messages, timestamps, or
//   unread badges are ever rendered.
// - Online status is NEVER rendered: presence requires a backend and
//   any green dot would be invented.
// - Storage stays on-device (friend_store.dart); true cross-device
//   SYNC is out of scope until a backend is explicitly approved.
//
// Design: premium Material 3, Deep Emerald Green #14532D accents,
// white cards, soft gray background, single-column mobile content
// with safe-area handling. The app shell and 6-tab navigation are
// untouched — this tab is only the Friends destination's content.
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friend_sharing.dart';
import 'friend_store.dart';

/// Shown when an action needs cloud sync (not enabled yet).
const _syncNeededMessage =
    'Chats need cloud sync, which is not enabled yet.';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key, this.sharing, this.codeGenerator});

  /// Copy/share backend. Null means the real clipboard + share sheet.
  final FriendSharing? sharing;

  /// Overrides UUID generation (tests use a deterministic code).
  final String Function()? codeGenerator;

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  late final FriendSharing _sharing =
      widget.sharing ?? SystemFriendSharing();
  String? _code;
  List<FriendEntry> _friends = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final store = FriendStore(prefs);
    final code = await store.loadOrCreateFriendCode(
      generate: widget.codeGenerator,
    );
    if (!mounted) return;
    setState(() {
      _code = code;
      _friends = store.loadFriends();
    });
  }

  List<FriendEntry> get _visibleFriends {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _friends;
    return _friends
        .where((f) => f.name.toLowerCase().contains(query))
        .toList();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null) return;
    try {
      await _sharing.copyCode(code);
      if (mounted) _showSnack('Friend code copied.');
    } catch (_) {
      if (mounted) _showSnack('Could not copy the code.');
    }
  }

  Future<void> _shareCode() async {
    final code = _code;
    if (code == null) return;
    try {
      await _sharing.shareCode(code);
    } catch (_) {
      if (mounted) _showSnack('Sharing is not available on this device.');
    }
  }

  void _showAddFriendSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Friend',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share your friend code with someone you travel with.',
              ),
              const SizedBox(height: 20),
              _friendCodeDisplay(),
              const SizedBox(height: 20),
              const _SyncNoteCard(),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final visible = _visibleFriends;
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Header: title + Add Friend action ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Friends',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'People you travel with',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _showAddFriendSheet,
                icon: const Icon(Icons.person_add_outlined, size: 20),
                label: const Text('Add Friend'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ---- Search: real local friends only ----
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search friends',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: scheme.surface,
            ),
          ),
          const SizedBox(height: 16),
          // ---- 1. My Friends ----
          _sectionCard(
            icon: Icons.people_outlined,
            title: 'My Friends',
            child: visible.isEmpty
                ? _emptyState(
                    icon: Icons.people_outlined,
                    title: _query.trim().isEmpty
                        ? 'No friends yet'
                        : 'No friends match "$_query"',
                    note: _query.trim().isEmpty
                        ? 'When you add friends, they will appear here. '
                            'Tap Add Friend above to share your code.'
                        : 'Try a different name. Search only covers '
                            'friends stored on this device.',
                  )
                : Column(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _friendRow(visible[i]),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          // ---- 2. My Friend Code ----
          _sectionCard(
            icon: Icons.badge_outlined,
            title: 'My Friend Code',
            child: _friendCodeDisplay(),
          ),
          const SizedBox(height: 12),
          // ---- 3. Friend Requests ----
          _sectionCard(
            icon: Icons.person_add_outlined,
            title: 'Friend Requests',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incoming',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _emptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No incoming requests',
                  note: 'Incoming requests will appear here once cloud '
                      'sync is enabled.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Outgoing',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _emptyState(
                  icon: Icons.outbox_outlined,
                  title: 'No outgoing requests',
                  note: 'Outgoing requests will appear here once cloud '
                      'sync is enabled.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- 4. Chats ----
          _sectionCard(
            icon: Icons.chat_bubble_outline,
            title: 'Chats',
            child: _emptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              note: 'Chats need cloud sync, which is not enabled yet — '
                  'no conversations are shown here.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Friend data is stored only on this device. Cross-device '
            'sync needs cloud sync, which is not enabled yet.',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
  }

  /// One stored friend: initials avatar (never a fake photo, never an
  /// online dot) + name + a message action that honestly explains
  /// messaging is not available yet.
  Widget _friendRow(FriendEntry friend) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              friend.initials,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              friend.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.message_outlined),
            tooltip: 'Message ${friend.name}',
            onPressed: () => _showSnack(_syncNeededMessage),
          ),
        ],
      ),
    );
  }

  /// The real code block, shared by the My Friend Code section and the
  /// Add Friend sheet: real QR + code text + real Copy/Share.
  ///
  /// ALIGNMENT: the block is always full card width with centered
  /// content, so the QR and code stay centered at every width (the
  /// buttons row alone used to force the width; centering is now
  /// explicit, not incidental).
  Widget _friendCodeDisplay() {
    final code = _code;
    if (code == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            child: QrImageView(
              data: code,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'This is your code on this device. Share it with someone '
            'you travel with.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          _codeActionButtons(),
        ],
      ),
    );
  }

  /// Copy + Share stay in one row when the card is wide enough and
  /// stack full-width on narrow cards — never cramped, never
  /// overflowing. Same buttons, labels, icons, and actions either way.
  Widget _codeActionButtons() {
    final copyButton = OutlinedButton.icon(
      onPressed: _copyCode,
      icon: const Icon(Icons.copy, size: 18),
      label: const Text('Copy'),
    );
    final shareButton = FilledButton.icon(
      onPressed: _shareCode,
      icon: const Icon(Icons.share, size: 18),
      label: const Text('Share'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 280) {
          return Row(
            children: [
              Expanded(child: copyButton),
              const SizedBox(width: 12),
              Expanded(child: shareButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copyButton,
            const SizedBox(height: 12),
            shareButton,
          ],
        );
      },
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
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
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  /// Attractive built-UI empty state: Material icon in a styled
  /// container (never emoji) + title + helpful message.
  ///
  /// ALIGNMENT: the block is always full card width with centered
  /// content. A bare Column would shrink to its widest child and, on
  /// wide screens where the note fits on one line, the whole block
  /// would sit left (the section card's column is start-aligned).
  /// The full-width box keeps illustration, title, and note centered
  /// at every width, in both themes.
  Widget _emptyState({
    required IconData icon,
    required String title,
    required String note,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 36, color: scheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              note,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Honest note used by the Add Friend sheet: cross-device adding needs
/// cloud sync, so no code entry is offered (a typed code cannot be
/// validated or confirmed without a backend).
class _SyncNoteCard extends StatelessWidget {
  const _SyncNoteCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Adding a friend across devices needs cloud sync, which '
              'is not enabled yet. A typed code cannot confirm a '
              'friend yet, so no code entry is offered here — share '
              'your code above instead.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
