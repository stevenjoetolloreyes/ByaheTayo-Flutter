// Friends tab — premium social travel design.
//
// Sections, in order: My Friends (real friends + message
// actions), My Friend Code (real code + real QR + real
// copy/share), Friend Requests (incoming + outgoing), Chats.
//
// HONESTY RULES:
// - The friend code is genuinely generated on-device (invite
//   code ESK-XXXXXX, persisted in SharedPreferences) and encoded
//   in a real QR code. Copy uses the real clipboard; Share uses
//   the real share sheet. When a cloud repository is provided,
//   the invite code is claimed once as the user's cloud code
//   (never overwritten); a legacy UUID cloud code is migrated
//   to an invite code with the old code kept as an alias.
//   Without a repository the tab stays local-only.
// - Search filters ONLY actually-stored friends (local entries plus
//   cloud friends from accepted requests, when synced). With none
//   stored, the section shows its honest empty state.
// - Add Friend shows the real code/QR share path. With cloud sync
//   it also offers an exact-code entry field: a typed code is
//   looked up by exact document ID (never listed) and only a real
//   match can receive a request. Without cloud sync there is NO
//   code-entry field: without a backend a typed code cannot be
//   validated, so it must never be presented as a friend.
// - Friend Requests: with cloud sync, pending incoming requests
//   render with real Accept/Decline actions and outgoing requests
//   render with their real status. Without cloud sync both
//   subsections show premium empty states, and NO Accept/Decline
//   buttons are rendered for requests that do not exist.
// - Chats / real-time messaging / notifications cannot be real
//   without a messaging backend: the conversation list shows its
//   honest empty state only. No fake conversations, last messages,
//   timestamps, or unread badges are ever rendered.
// - Online status is NEVER rendered: presence requires a backend and
//   any green dot would be invented.
// - Local friends are never promoted into cloud friendships: the
//   cloud friends list is derived from accepted requests only, and
//   local entries stay local cache.
//
// Design: premium Material 3, Deep Emerald Green #14532D accents,
// white cards, soft gray background, single-column mobile content
// with safe-area handling. The app shell and 6-tab navigation are
// untouched — this tab is only the Friends destination's content.
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_layout.dart';
import 'friend_cloud_repository.dart';
import 'friend_sharing.dart';
import 'friend_store.dart';

/// Shown when an action needs cloud sync (not enabled yet).
const _syncNeededMessage =
    'Chats need cloud sync, which is not enabled yet.';

/// Client-side guard against repeated failed code lookups.
/// NOT server-side rate limiting: Firestore rules have no
/// rate-limit primitive, so this only throttles this device's own
/// Add Friend sheet. After 5 failed lookups within 5 minutes, the
/// next attempts are blocked for 60 seconds. [now] is injectable
/// so tests can control time.
class FailedLookupRateGuard {
  FailedLookupRateGuard({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final List<DateTime> _failures = [];
  DateTime? _blockedUntil;

  bool get isBlocked {
    final until = _blockedUntil;
    return until != null && _now().isBefore(until);
  }

  void recordFailure() {
    final t = _now();
    _failures.removeWhere((f) => t.difference(f) > const Duration(minutes: 5));
    _failures.add(t);
    if (_failures.length >= 5) {
      _blockedUntil = t.add(const Duration(minutes: 1));
      _failures.clear();
    }
  }
}

class FriendsTab extends StatefulWidget {
  const FriendsTab({
    super.key,
    this.sharing,
    this.codeGenerator,
    this.cloudRepository,
    this.cloudUserId,
    this.cloudUserName,
  });

  /// Copy/share backend. Null means the real clipboard + share sheet.
  final FriendSharing? sharing;

  /// Overrides UUID generation (tests use a deterministic code).
  final String Function()? codeGenerator;

  /// Cloud friend-code + request backend. Null means the tab stays
  /// local-only (the legacy behavior): no code entry, no request
  /// rows, honest empty states. Null when Firebase is unconfigured.
  final FriendCloudRepository? cloudRepository;

  /// The signed-in user's UID + display name for cloud requests.
  /// Both a repository and a UID must be set for cloud features to
  /// appear; a repository without a UID stays local-only.
  final String? cloudUserId;
  final String? cloudUserName;

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  late final FriendSharing _sharing =
      widget.sharing ?? SystemFriendSharing();
  String? _code;
  List<FriendEntry> _friends = [];
  String _query = '';

  /// Cloud state. Empty when cloud is unavailable. [_cloudFailed]
  /// records a sync failure: local data stays visible and the
  /// Friend Requests card shows an inline note (never an overlay
  /// SnackBar — an overlay could cover other tabs' content, since
  /// this tab is built eagerly inside the shell's IndexedStack).
  String? _cloudCode;
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];
  List<CloudFriend> _cloudFriends = [];
  bool _cloudFailed = false;

  /// Code-entry state for the Add Friend sheet.
  final TextEditingController _codeController = TextEditingController();
  String? _codeError;
  bool _sending = false;

  /// Client-side failed-lookup guard (see FailedLookupRateGuard).
  final FailedLookupRateGuard _lookupGuard = FailedLookupRateGuard();

  bool get _cloudEnabled =>
      widget.cloudRepository != null && widget.cloudUserId != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
    if (_cloudEnabled) await _syncCloud();
  }

  /// Claims the cloud code (backfill once, never overwrites) and
  /// loads requests + cloud friends. Remote failure never blocks
  /// the tab: local data stays visible with an honest error.
  Future<void> _syncCloud() async {
    final repo = widget.cloudRepository;
    final uid = widget.cloudUserId;
    final localCode = _code;
    if (repo == null || uid == null || localCode == null) return;
    try {
      final cloudCode = await repo.ensureInviteCode(
        uid: uid,
        localCode: localCode,
      );
      if (cloudCode != localCode) {
        // Collision minted a fresh code: adopt it locally so the
        // displayed code is the code other devices can look up.
        final prefs = await SharedPreferences.getInstance();
        await FriendStore(prefs).saveFriendCode(cloudCode);
        if (!mounted) return;
        setState(() => _code = cloudCode);
      }
      await _refreshCloudLists();
      if (!mounted) return;
      setState(() {
        _cloudCode = cloudCode;
        _cloudFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cloudFailed = true);
    }
  }

  /// Re-reads incoming/outgoing requests + cloud friends.
  Future<void> _refreshCloudLists() async {
    final repo = widget.cloudRepository;
    final uid = widget.cloudUserId;
    if (repo == null || uid == null) return;
    final incoming = await repo.fetchIncoming(uid);
    final outgoing = await repo.fetchOutgoing(uid);
    final friends = await repo.fetchFriends(uid);
    if (!mounted) return;
    setState(() {
      _incoming = incoming;
      _outgoing = outgoing;
      _cloudFriends = friends;
    });
  }

  /// Cloud friends first (derived from accepted requests only),
  /// then local friends. Local entries are never merged into cloud
  /// friendships — they are displayed as the local data they are,
  /// and are never written back to the cloud.
  List<FriendEntry> get _visibleFriends {
    final all = [
      ..._cloudFriends.map(
        (f) => FriendEntry(name: f.displayName, code: f.code),
      ),
      ..._friends,
    ];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return all;
    return all
        .where((f) => f.name.toLowerCase().contains(query))
        .toList();
  }

  /// Pending incoming requests (accepted counterparts appear in My
  /// Friends; declined ones are resolved and hidden).
  List<FriendRequest> get _pendingIncoming =>
      _incoming.where((r) => r.isPending).toList();

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

  Future<void> _respond(FriendRequest request, bool accept) async {
    final repo = widget.cloudRepository;
    final uid = widget.cloudUserId;
    if (repo == null || uid == null) return;
    try {
      await repo.respondToRequest(
        requestId: request.id,
        uid: uid,
        accept: accept,
      );
      await _refreshCloudLists();
      if (mounted) {
        _showSnack(
          accept ? 'Friend request accepted.' : 'Friend request declined.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Could not update that request. Please try again.');
      }
    }
  }

  /// Looks a typed code up exactly and sends a request. Returns an
  /// error message to show inline, or null on success.
  Future<String?> _sendCodeRequest(String rawCode) async {
    final repo = widget.cloudRepository;
    final uid = widget.cloudUserId;
    if (repo == null || uid == null) return 'Cloud sync is not available.';
    // Client-side rate guard only (see FailedLookupRateGuard):
    // Firestore rules cannot rate-limit lookups.
    if (_lookupGuard.isBlocked) {
      return 'Too many failed attempts. Please try again in a minute.';
    }
    final code = normalizeInviteCode(rawCode);
    if (code.isEmpty) return 'Enter a friend code first.';
    try {
      final found = await repo.lookupCode(code);
      if (found == null) {
        _lookupGuard.recordFailure();
        return 'No friend found with that code.';
      }
      if (found.uid == uid) return 'That is your own code.';
      await repo.sendRequest(
        fromUid: uid,
        fromName: widget.cloudUserName,
        fromCode: _cloudCode ?? _code ?? '',
        toUid: found.uid,
        toCode: found.code,
      );
      await _refreshCloudLists();
      return null;
    } on StateError catch (e) {
      // Duplicate-guard + stale-code messages are user-safe.
      return e.message;
    } catch (_) {
      return 'Could not send that request. Please try again.';
    }
  }

  void _showAddFriendSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Friend',
                  style: AppText.titleStrong,
                ),
                const SizedBox(height: AppSpacing.s8),
                const Text(
                  'Share your friend code with someone you travel with.',
                ),
                const SizedBox(height: AppSpacing.s20),
                _friendCodeDisplay(),
                const SizedBox(height: AppSpacing.s20),
                if (_cloudEnabled) ...[
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      hintText: 'Enter a friend code',
                      prefixIcon: Icon(Icons.person_add_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(AppLayout.inputRadiusTab)),
                      ),
                    ),
                    onChanged: (_) {
                      if (_codeError != null) {
                        setSheetState(() => _codeError = null);
                      }
                    },
                  ),
                  if (_codeError != null) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      _codeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppLayout.cardGap),
                  FilledButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            setSheetState(() {
                              _sending = true;
                              _codeError = null;
                            });
                            final error = await _sendCodeRequest(
                              _codeController.text,
                            );
                            if (!mounted) return;
                            // The sheet may have been dismissed
                            // mid-send; guard its own context too.
                            if (!context.mounted) return;
                            setSheetState(() {
                              _sending = false;
                              _codeError = error;
                            });
                            if (error == null) {
                              _codeController.clear();
                              Navigator.of(context).pop();
                              _showSnack('Friend request sent.');
                            }
                          },
                    child: const Text('Send request'),
                  ),
                ] else
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
        padding: AppLayout.pagePaddingTab,
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
                      style: AppText.pageTitle,
                    ),
                    const SizedBox(height: AppSpacing.s2),
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
          const SizedBox(height: AppLayout.headerGap),
          // ---- Search: real local friends only ----
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search friends',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLayout.inputRadiusTab),
              ),
              filled: true,
              fillColor: scheme.surface,
            ),
          ),
          const SizedBox(height: AppLayout.headerGap),
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
                        ? (_cloudEnabled
                            ? 'When you add friends, they will appear '
                                'here. Tap Add Friend above to share '
                                'your code or enter a friend\'s code.'
                            : 'When you add friends, they will appear here. '
                                'Tap Add Friend above to share your code.')
                        : (_cloudEnabled
                            ? 'Try a different name.'
                            : 'Try a different name. Search only covers '
                                'friends stored on this device.'),
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
          const SizedBox(height: AppLayout.cardGap),
          // ---- 2. My Friend Code ----
          _sectionCard(
            icon: Icons.badge_outlined,
            title: 'My Friend Code',
            child: _friendCodeDisplay(),
          ),
          const SizedBox(height: AppLayout.cardGap),
          // ---- 3. Friend Requests ----
          _sectionCard(
            icon: Icons.person_add_outlined,
            title: 'Friend Requests',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_cloudEnabled && _cloudFailed) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      const Expanded(
                        child: Text(
                          'Could not sync friend requests. Showing '
                          'on-device data.',
                          style: AppText.caption,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.cardGap),
                ],
                const Text(
                  'Incoming',
                  style: AppText.labelStrong,
                ),
                const SizedBox(height: AppSpacing.s8),
                if (!_cloudEnabled)
                  _emptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No incoming requests',
                    note: 'Incoming requests will appear here once cloud '
                        'sync is enabled.',
                  )
                else if (_pendingIncoming.isEmpty)
                  _emptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No incoming requests',
                    note: 'New friend requests will appear here.',
                  )
                else
                  Column(
                    children: [
                      for (final request in _pendingIncoming)
                        _incomingRequestRow(request),
                    ],
                  ),
                const SizedBox(height: AppLayout.headerGap),
                const Text(
                  'Outgoing',
                  style: AppText.labelStrong,
                ),
                const SizedBox(height: AppSpacing.s8),
                if (!_cloudEnabled)
                  _emptyState(
                    icon: Icons.outbox_outlined,
                    title: 'No outgoing requests',
                    note: 'Outgoing requests will appear here once cloud '
                        'sync is enabled.',
                  )
                else if (_outgoing.isEmpty)
                  _emptyState(
                    icon: Icons.outbox_outlined,
                    title: 'No outgoing requests',
                    note: 'Requests you send will appear here with their '
                        'status.',
                  )
                else
                  Column(
                    children: [
                      for (var i = 0; i < _outgoing.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _outgoingRequestRow(_outgoing[i]),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
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
          const SizedBox(height: AppLayout.headerGap),
          Text(
            _cloudEnabled
                ? 'Friend codes and requests sync across your devices. '
                    'Chats are not available yet.'
                : 'Friend data is stored only on this device. Cross-device '
                    'sync needs cloud sync, which is not enabled yet.',
            style: AppText.caption.copyWith(color: muted),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
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
          const SizedBox(width: AppLayout.cardGap),
          Expanded(
            child: Text(
              friend.name,
              style: AppText.name,
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

  /// One pending incoming request: initials avatar + name + code,
  /// then real Accept/Decline actions. Only rendered for requests
  /// that actually exist.
  Widget _incomingRequestRow(FriendRequest request) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                child: Text(
                  FriendEntry(name: request.nameFor(true)).initials,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppLayout.cardGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.nameFor(true),
                      style: AppText.name,
                    ),
                    Text(
                      request.fromCode,
                      style: AppText.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          _requestActions(request),
        ],
      ),
    );
  }

  /// Accept + Decline stay in one row when the card is wide enough
  /// and stack full-width on narrow cards — same convention as the
  /// Copy/Share buttons, never cramped, never overflowing.
  Widget _requestActions(FriendRequest request) {
    final acceptButton = FilledButton.icon(
      onPressed: () => _respond(request, true),
      icon: const Icon(Icons.check, size: 18),
      label: const Text('Accept'),
    );
    final declineButton = OutlinedButton.icon(
      onPressed: () => _respond(request, false),
      icon: const Icon(Icons.close, size: 18),
      label: const Text('Decline'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 280) {
          return Row(
            children: [
              Expanded(child: acceptButton),
              const SizedBox(width: AppLayout.cardGap),
              Expanded(child: declineButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            acceptButton,
            const SizedBox(height: AppLayout.cardGap),
            declineButton,
          ],
        );
      },
    );
  }

  /// One outgoing request: name + code + its real status.
  Widget _outgoingRequestRow(FriendRequest request) {
    final status = request.isAccepted
        ? 'Accepted'
        : request.isDeclined
            ? 'Declined'
            : 'Pending';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.12),
            child: Text(
              FriendEntry(name: request.nameFor(false)).initials,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppLayout.cardGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.nameFor(false),
                  style: AppText.name,
                ),
                Text(
                  request.toCode,
                  style: AppText.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            status,
            style: AppText.captionStrong.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: AppLayout.cardPadding,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppLayout.cardRadius),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            child: QrImageView(
              data: code,
              size: AppLayout.qrSize,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          const Text(
            'This is your code on this device. Share it with someone '
            'you travel with.',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
          const SizedBox(height: AppLayout.cardGap),
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
              const SizedBox(width: AppLayout.cardGap),
              Expanded(child: shareButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copyButton,
            const SizedBox(height: AppLayout.cardGap),
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
        padding: AppLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: AppLayout.cardGap),
                Expanded(
                  child: Text(
                    title,
                    style: AppText.sectionTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: AppLayout.emptyIllustrationSize,
              height: AppLayout.emptyIllustrationSize,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppLayout.emptyIllustrationRadius),
              ),
              child: Icon(icon, size: 36, color: scheme.primary),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.emptyTitle,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              note,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Honest note used by the Add Friend sheet only when no cloud
/// repository is available: cross-device adding needs cloud sync,
/// so no code entry is offered (a typed code cannot be validated
/// or confirmed without a backend).
class _SyncNoteCard extends StatelessWidget {
  const _SyncNoteCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppLayout.cardPadding,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayout.noteRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: AppLayout.cardGap),
          const Expanded(
            child: Text(
              'Adding a friend across devices needs cloud sync, which '
              'is not enabled yet. A typed code cannot confirm a '
              'friend yet, so no code entry is offered here — share '
              'your code above instead.',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
