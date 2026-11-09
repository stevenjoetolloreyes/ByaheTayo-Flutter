// Tests for Friends cloud sync: code backfill, exact-code lookup,
// send/accept/decline flow, friends derived from accepted requests
// only, local friends never fabricated into cloud friendships, the
// Firestore rules text, and alignment preserved in the cloud path.
//
// The production Firestore implementation is not exercised against
// a live database here; its contract is covered by the fake below
// (same interface, same guard semantics) plus the rules-text test.
import 'dart:io';
import 'dart:math';

import 'package:estudyantego/features/friend_cloud_repository.dart';
import 'package:estudyantego/features/friend_store.dart';
import 'package:estudyantego/features/friend_sharing.dart';
import 'package:estudyantego/features/friends_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFriendSharing implements FriendSharing {
  final List<String> copied = [];
  final List<String> shared = [];

  @override
  Future<void> copyCode(String code) async {
    copied.add(code);
  }

  @override
  Future<void> shareCode(String code) async {
    shared.add(code);
  }
}

/// In-memory [FriendCloudRepository] with the same guard semantics
/// as the Firestore implementation (backfill once, exact lookup,
/// duplicate guard, recipient-only answers, derived friends).
class FakeFriendCloudRepository implements FriendCloudRepository {
  /// code -> owner UID.
  final Map<String, String> codes = {};

  /// UID -> established cloud code.
  final Map<String, String> mappings = {};

  /// request ID -> request.
  final Map<String, FriendRequest> requests = {};

  var _counter = 0;
  var throwOnFetch = false;
  var throwOnEnsure = false;

  String _nextId() => 'req-${++_counter}';

  DateTime _nextTime() =>
      DateTime(2026, 1, 1).add(Duration(seconds: ++_counter));

  /// Seeds a request directly (bypassing send guards).
  void seed(FriendRequest request) {
    requests[request.id] = request;
  }

  @override
  Future<String> ensureCloudCode({
    required String uid,
    required String localCode,
  }) async {
    if (throwOnEnsure) throw Exception('boom');
    final mapped = mappings[uid];
    if (mapped != null) return mapped;
    if (!codes.containsKey(localCode) || codes[localCode] == uid) {
      codes[localCode] = uid;
      mappings[uid] = localCode;
      return localCode;
    }
    final fresh = 'fresh-code-${++_counter}';
    codes[fresh] = uid;
    mappings[uid] = fresh;
    return fresh;
  }

  @override
  Future<String> ensureInviteCode({
    required String uid,
    String? localCode,
  }) async {
    if (throwOnEnsure) throw Exception('boom');
    final mapped = mappings[uid];
    if (mapped != null && isInviteCodeFormat(mapped)) return mapped;
    if (mapped != null) {
      // Legacy UUID mapping: migrate to an invite code, keeping
      // the old code document as an alias (never deleted).
      final migrated = generateInviteCode();
      codes[migrated] = uid;
      mappings[uid] = migrated;
      return migrated;
    }
    if (localCode != null &&
        isInviteCodeFormat(localCode) &&
        (!codes.containsKey(localCode) || codes[localCode] == uid)) {
      codes[localCode] = uid;
      mappings[uid] = localCode;
      return localCode;
    }
    var claimed = generateInviteCode();
    while (codes.containsKey(claimed) && codes[claimed] != uid) {
      claimed = generateInviteCode();
    }
    codes[claimed] = uid;
    mappings[uid] = claimed;
    return claimed;
  }

  @override
  Future<CloudCodeLookup?> lookupCode(String code) async {
    final uid = codes[code];
    if (uid == null) return null;
    return CloudCodeLookup(uid: uid, code: code);
  }

  @override
  Future<FriendRequest> sendRequest({
    required String fromUid,
    required String? fromName,
    required String fromCode,
    required String toUid,
    required String toCode,
  }) async {
    if (fromUid == toUid) {
      throw ArgumentError('Cannot send a friend request to yourself.');
    }
    if (codes[toCode] != toUid) {
      throw StateError('That code is no longer valid.');
    }
    final duplicate = requests.values.any((r) =>
        r.fromUid == fromUid &&
        r.toUid == toUid &&
        r.isPending);
    if (duplicate) {
      throw StateError('A request to this friend is already pending.');
    }
    final request = FriendRequest(
      id: _nextId(),
      fromUid: fromUid,
      toUid: toUid,
      fromCode: fromCode,
      toCode: toCode,
      status: requestStatusPending,
      fromName: fromName,
      createdAt: _nextTime(),
    );
    requests[request.id] = request;
    return request;
  }

  @override
  Future<List<FriendRequest>> fetchIncoming(String uid) async {
    if (throwOnFetch) throw Exception('boom');
    final list =
        requests.values.where((r) => r.toUid == uid).toList();
    list.sort((a, b) =>
        (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return list;
  }

  @override
  Future<List<FriendRequest>> fetchOutgoing(String uid) async {
    if (throwOnFetch) throw Exception('boom');
    final list =
        requests.values.where((r) => r.fromUid == uid).toList();
    list.sort((a, b) =>
        (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return list;
  }

  @override
  Future<void> respondToRequest({
    required String requestId,
    required String uid,
    required bool accept,
  }) async {
    final request = requests[requestId];
    if (request == null) throw StateError('Request not found.');
    if (request.toUid != uid) {
      throw StateError('Only the recipient can answer this request.');
    }
    if (!request.isPending) {
      throw StateError('This request was already answered.');
    }
    requests[requestId] = FriendRequest(
      id: request.id,
      fromUid: request.fromUid,
      toUid: request.toUid,
      fromCode: request.fromCode,
      toCode: request.toCode,
      status: accept ? requestStatusAccepted : requestStatusDeclined,
      fromName: request.fromName,
      toName: request.toName,
      createdAt: request.createdAt,
    );
  }

  @override
  Future<List<CloudFriend>> fetchFriends(String uid) async {
    if (throwOnFetch) throw Exception('boom');
    final byUid = <String, CloudFriend>{};
    for (final r in requests.values) {
      if (r.toUid == uid && r.isAccepted) {
        byUid.putIfAbsent(
          r.fromUid,
          () => CloudFriend(
            uid: r.fromUid,
            code: r.fromCode,
            name: r.fromName,
          ),
        );
      }
      if (r.fromUid == uid && r.isAccepted) {
        byUid.putIfAbsent(
          r.toUid,
          () => CloudFriend(
            uid: r.toUid,
            code: r.toCode,
            name: r.toName,
          ),
        );
      }
    }
    final friends = byUid.values.toList();
    friends.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return friends;
  }
}

const _meUid = 'me-uid';
const _meCode = '123e4567-e89b-12d3-a456-426614174000';

Finder _codeText(String code) => find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == code,
    );

Finder _codeField() => find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Enter a friend code',
    );

Future<void> _pumpCloudFriends(
  WidgetTester tester, {
  required FakeFriendCloudRepository repo,
  Map<String, Object>? prefs,
  String code = _meCode,
  Size size = const Size(390, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(prefs ?? {});
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FriendsTab(
        sharing: FakeFriendSharing(),
        codeGenerator: () => code,
        cloudRepository: repo,
        cloudUserId: _meUid,
        cloudUserName: 'Me Myself',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

FriendRequest _seedRequest({
  required String id,
  required String fromUid,
  required String toUid,
  required String fromCode,
  required String toCode,
  String? fromName,
  String? toName,
  String status = requestStatusPending,
}) =>
    FriendRequest(
      id: id,
      fromUid: fromUid,
      toUid: toUid,
      fromCode: fromCode,
      toCode: toCode,
      status: status,
      fromName: fromName,
      toName: toName,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FriendCloudRepository contract (fake semantics)', () {
    test('backfill claims the local code once, never overwrites', () async {
      final repo = FakeFriendCloudRepository();
      expect(
        await repo.ensureCloudCode(uid: _meUid, localCode: 'code-a'),
        'code-a',
      );
      // A later call with a different local code keeps the first one.
      expect(
        await repo.ensureCloudCode(uid: _meUid, localCode: 'code-b'),
        'code-a',
      );
      expect(repo.mappings[_meUid], 'code-a');
      expect(repo.codes['code-a'], _meUid);
      expect(repo.codes.containsKey('code-b'), isFalse);
    });

    test('backfill collision mints a fresh code', () async {
      final repo = FakeFriendCloudRepository();
      repo.codes['taken-code'] = 'other-uid';
      final claimed = await repo.ensureCloudCode(
        uid: _meUid,
        localCode: 'taken-code',
      );
      expect(claimed, isNot('taken-code'));
      expect(repo.mappings[_meUid], claimed);
      expect(repo.codes[claimed], _meUid);
    });

    test('exact-code lookup: found and not-found', () async {
      final repo = FakeFriendCloudRepository();
      repo.codes['friend-code'] = 'friend-uid';
      final found = await repo.lookupCode('friend-code');
      expect(found?.uid, 'friend-uid');
      expect(await repo.lookupCode('missing-code'), isNull);
    });

    test('send guards: self, stale code, duplicate pending', () async {
      final repo = FakeFriendCloudRepository();
      repo.codes['friend-code'] = 'friend-uid';
      await expectLater(
        repo.sendRequest(
          fromUid: _meUid,
          fromName: 'Me',
          fromCode: _meCode,
          toUid: _meUid,
          toCode: _meCode,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.sendRequest(
          fromUid: _meUid,
          fromName: 'Me',
          fromCode: _meCode,
          toUid: 'ghost-uid',
          toCode: 'ghost-code',
        ),
        throwsStateError,
      );
      await repo.sendRequest(
        fromUid: _meUid,
        fromName: 'Me',
        fromCode: _meCode,
        toUid: 'friend-uid',
        toCode: 'friend-code',
      );
      await expectLater(
        repo.sendRequest(
          fromUid: _meUid,
          fromName: 'Me',
          fromCode: _meCode,
          toUid: 'friend-uid',
          toCode: 'friend-code',
        ),
        throwsStateError,
      );
    });

    test('respond guards: wrong recipient, already answered', () async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: 'ana-uid',
        toUid: _meUid,
        fromCode: 'ana-code',
        toCode: _meCode,
        fromName: 'Ana',
      ));
      await expectLater(
        repo.respondToRequest(requestId: 'r1', uid: 'someone-else', accept: true),
        throwsStateError,
      );
      await repo.respondToRequest(requestId: 'r1', uid: _meUid, accept: true);
      expect(repo.requests['r1']?.status, requestStatusAccepted);
      await expectLater(
        repo.respondToRequest(requestId: 'r1', uid: _meUid, accept: false),
        throwsStateError,
      );
      await expectLater(
        repo.respondToRequest(requestId: 'nope', uid: _meUid, accept: true),
        throwsStateError,
      );
    });

    test('friends derived from accepted requests only', () async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: 'ana-uid',
        toUid: _meUid,
        fromCode: 'ana-code',
        toCode: _meCode,
        fromName: 'Ana',
        status: requestStatusAccepted,
      ));
      repo.seed(_seedRequest(
        id: 'r2',
        fromUid: 'gus-uid',
        toUid: _meUid,
        fromCode: 'gus-code',
        toCode: _meCode,
        fromName: 'Gus',
      ));
      repo.seed(_seedRequest(
        id: 'r3',
        fromUid: _meUid,
        toUid: 'dan-uid',
        fromCode: _meCode,
        toCode: 'dan-code',
        toName: 'Dan',
        status: requestStatusAccepted,
      ));
      repo.seed(_seedRequest(
        id: 'r4',
        fromUid: _meUid,
        toUid: 'eli-uid',
        fromCode: _meCode,
        toCode: 'eli-code',
        toName: 'Eli',
        status: requestStatusDeclined,
      ));
      final friends = await repo.fetchFriends(_meUid);
      expect(friends.map((f) => f.uid), ['ana-uid', 'dan-uid']);
    });
  });

  group('Invite codes (ensureInviteCode)', () {
    test('generator produces ESK- plus six uppercase alphanumerics',
        () async {
      final code = generateInviteCode(random: Random(42));
      expect(isInviteCodeFormat(code), isTrue);
      expect(code, startsWith('ESK-'));
      expect(code.length, 10);
      expect(isInviteCodeFormat('ESK-123'), isFalse);
      expect(isInviteCodeFormat('123e4567-e89b-12d3-a456-426614174000'),
          isFalse);
    });

    test('normalization uppercases ESK codes and preserves UUIDs', () {
      expect(normalizeInviteCode('esk-7k9p2x'), 'ESK-7K9P2X');
      expect(normalizeInviteCode(' 7k9p2x '), 'ESK-7K9P2X');
      expect(
        normalizeInviteCode('123e4567-e89b-12d3-a456-426614174000'),
        '123e4567-e89b-12d3-a456-426614174000',
      );
    });

    test('rate guard blocks after 5 failures, unblocks after 60s', () {
      var now = DateTime(2026, 1, 1);
      final guard = FailedLookupRateGuard(now: () => now);
      for (var i = 0; i < 4; i++) {
        guard.recordFailure();
        expect(guard.isBlocked, isFalse);
      }
      guard.recordFailure();
      expect(guard.isBlocked, isTrue);
      now = now.add(const Duration(seconds: 61));
      expect(guard.isBlocked, isFalse);
    });

    test('new user with no mapping gets an invite code', () async {
      final repo = FakeFriendCloudRepository();
      final claimed = await repo.ensureInviteCode(uid: _meUid);
      expect(isInviteCodeFormat(claimed), isTrue);
      expect(repo.mappings[_meUid], claimed);
      expect(repo.codes[claimed], _meUid);
    });

    test('new user with a free local invite code claims it', () async {
      final repo = FakeFriendCloudRepository();
      final claimed = await repo.ensureInviteCode(
        uid: _meUid,
        localCode: 'ESK-ABC123',
      );
      expect(claimed, 'ESK-ABC123');
      expect(repo.codes['ESK-ABC123'], _meUid);
    });

    test('existing invite mapping is returned unchanged', () async {
      final repo = FakeFriendCloudRepository();
      repo.codes['ESK-ABC123'] = _meUid;
      repo.mappings[_meUid] = 'ESK-ABC123';
      expect(
        await repo.ensureInviteCode(uid: _meUid),
        'ESK-ABC123',
      );
    });

    test('UUID mapping migrates to invite code, old code kept as alias',
        () async {
      final repo = FakeFriendCloudRepository();
      repo.codes[_meCode] = _meUid;
      repo.mappings[_meUid] = _meCode;
      final migrated = await repo.ensureInviteCode(uid: _meUid);
      expect(isInviteCodeFormat(migrated), isTrue);
      expect(migrated, isNot(_meCode));
      expect(repo.mappings[_meUid], migrated);
      expect(repo.codes[migrated], _meUid);
      // Old code document is never deleted.
      expect(repo.codes[_meCode], _meUid);
    });

    test('taken local invite code mints a different invite code',
        () async {
      final repo = FakeFriendCloudRepository();
      repo.codes['ESK-ABC123'] = 'other-uid';
      final claimed = await repo.ensureInviteCode(
        uid: _meUid,
        localCode: 'ESK-ABC123',
      );
      expect(isInviteCodeFormat(claimed), isTrue);
      expect(claimed, isNot('ESK-ABC123'));
      expect(repo.codes[claimed], _meUid);
    });
  });

  group('Friends tab cloud sync (widget)', () {
    testWidgets('invite backfill claims an ESK code on first cloud open',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      await _pumpCloudFriends(tester, repo: repo);
      final claimed = repo.mappings[_meUid]!;
      expect(isInviteCodeFormat(claimed), isTrue);
      expect(repo.codes[claimed], _meUid);
      expect(_codeText(claimed), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('byahetayo_friend_code'), claimed);
    });

    testWidgets('backfill never overwrites an established invite code',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.codes['ESK-ABC123'] = _meUid;
      repo.mappings[_meUid] = 'ESK-ABC123';
      await _pumpCloudFriends(tester, repo: repo);
      expect(repo.mappings[_meUid], 'ESK-ABC123');
      // The displayed code adopts the established cloud identity so
      // the shown code is the one other devices can look up.
      expect(_codeText('ESK-ABC123'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('byahetayo_friend_code'),
        'ESK-ABC123',
      );
    });

    testWidgets('UUID cloud code migrates to invite, old code kept',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.codes[_meCode] = _meUid;
      repo.mappings[_meUid] = _meCode;
      await _pumpCloudFriends(tester, repo: repo);
      final migrated = repo.mappings[_meUid]!;
      expect(isInviteCodeFormat(migrated), isTrue);
      expect(migrated, isNot(_meCode));
      expect(repo.codes[migrated], _meUid);
      // Old code document is kept as an alias.
      expect(repo.codes[_meCode], _meUid);
      expect(_codeText(migrated), findsOneWidget);
    });

    testWidgets('backfill collision mints a fresh invite code',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.codes['taken-code'] = 'other-uid';
      await _pumpCloudFriends(tester, repo: repo, code: 'taken-code');
      final claimed = repo.mappings[_meUid]!;
      expect(isInviteCodeFormat(claimed), isTrue);
      expect(claimed, isNot('taken-code'));
      expect(repo.codes[claimed], _meUid);
      expect(_codeText(claimed), findsOneWidget);
    });

    testWidgets('send flow: code entry, lookup, outgoing pending',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.codes['friend-code'] = 'friend-uid';
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      expect(_codeField(), findsOneWidget);

      await tester.enterText(_codeField(), 'friend-code');
      await tester.tap(find.text('Send request'));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Friend request sent.'), findsOneWidget);
      // Outgoing row shows the recipient (name falls back to code)
      // with its real Pending status.
      expect(find.text('friend-code'), findsWidgets);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('No outgoing requests'), findsNothing);
    });

    testWidgets('send flow: unknown code shows an inline error, no request',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      await tester.enterText(_codeField(), 'missing-code');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('No friend found with that code.'), findsOneWidget);
      expect(repo.requests, isEmpty);
      expect(find.text('No outgoing requests'), findsOneWidget);
    });

    testWidgets('send flow: own code is rejected inline',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      await _pumpCloudFriends(tester, repo: repo);
      // The user's current code after invite backfill is the ESK
      // mapping, not the legacy local UUID.
      final ownCode = repo.mappings[_meUid]!;

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      await tester.enterText(_codeField(), ownCode);
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('That is your own code.'), findsOneWidget);
      expect(repo.requests, isEmpty);
    });

    testWidgets('send flow: lowercase ESK code is normalized and sent',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.codes['ESK-7K9P2X'] = 'friend-uid';
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      await tester.enterText(_codeField(), 'esk-7k9p2x');
      await tester.tap(find.text('Send request'));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Friend request sent.'), findsOneWidget);
      expect(repo.requests, isNotEmpty);
    });

    testWidgets('send flow: bare six-character body gains ESK- prefix',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.codes['ESK-7K9P2X'] = 'friend-uid';
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      await tester.enterText(_codeField(), '7k9p2x');
      await tester.tap(find.text('Send request'));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Friend request sent.'), findsOneWidget);
      expect(repo.requests, isNotEmpty);
    });

    testWidgets('send flow: legacy UUID code still works',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      const legacy = '123e4567-e89b-12d3-a456-426614174001';
      repo.codes[legacy] = 'friend-uid';
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      await tester.enterText(_codeField(), legacy);
      await tester.tap(find.text('Send request'));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Friend request sent.'), findsOneWidget);
      expect(repo.requests, isNotEmpty);
    });

    testWidgets('send flow: 5 failed lookups block the 6th attempt',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.enterText(_codeField(), 'missing-code');
        await tester.tap(find.text('Send request'));
        await tester.pumpAndSettle();
        expect(find.text('No friend found with that code.'), findsOneWidget);
      }
      await tester.enterText(_codeField(), 'missing-code');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect(
        find.text('Too many failed attempts. Please try again in a minute.'),
        findsOneWidget,
      );
      expect(repo.requests, isEmpty);
    });

    testWidgets('incoming accept moves the sender into My Friends',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: 'ana-uid',
        toUid: _meUid,
        fromCode: 'ana-code',
        toCode: _meCode,
        fromName: 'Ana Santos',
      ));
      await _pumpCloudFriends(tester, repo: repo);

      expect(find.text('Ana Santos'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Friend request accepted.'), findsOneWidget);
      expect(find.text('No incoming requests'), findsOneWidget);
      // Ana is now a friend (accepted request derived friend).
      expect(find.text('Ana Santos'), findsOneWidget);
      expect((await repo.fetchFriends(_meUid)).map((f) => f.uid), ['ana-uid']);
    });

    testWidgets('incoming decline hides the request, adds no friend',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: 'ben-uid',
        toUid: _meUid,
        fromCode: 'ben-code',
        toCode: _meCode,
        fromName: 'Ben Cruz',
      ));
      await _pumpCloudFriends(tester, repo: repo);

      await tester.tap(find.text('Decline'));
      // Top popup (was a SnackBar): assert while it is still up —
      // pumpAndSettle would fast-forward past its 5 seconds.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Friend request declined.'), findsOneWidget);
      expect(find.text('No incoming requests'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsNothing);
      expect(await repo.fetchFriends(_meUid), isEmpty);
    });

    testWidgets('outgoing rows show real statuses',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: _meUid,
        toUid: 'cid-uid',
        fromCode: _meCode,
        toCode: 'cid-code',
        toName: 'Cid',
      ));
      repo.seed(_seedRequest(
        id: 'r2',
        fromUid: _meUid,
        toUid: 'dan-uid',
        fromCode: _meCode,
        toCode: 'dan-code',
        toName: 'Dan',
        status: requestStatusAccepted,
      ));
      repo.seed(_seedRequest(
        id: 'r3',
        fromUid: _meUid,
        toUid: 'eli-uid',
        fromCode: _meCode,
        toCode: 'eli-code',
        toName: 'Eli',
        status: requestStatusDeclined,
      ));
      await _pumpCloudFriends(tester, repo: repo);

      expect(find.text('Cid'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
      // Dan is also a derived friend in My Friends; Eli is not.
      expect(find.text('Dan'), findsWidgets);
      expect(find.text('Eli'), findsOneWidget);
    });

    testWidgets('My Friends holds accepted only, never pending/declined',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: 'fay-uid',
        toUid: _meUid,
        fromCode: 'fay-code',
        toCode: _meCode,
        fromName: 'Fay',
        status: requestStatusAccepted,
      ));
      repo.seed(_seedRequest(
        id: 'r2',
        fromUid: 'gus-uid',
        toUid: _meUid,
        fromCode: 'gus-code',
        toCode: _meCode,
        fromName: 'Gus',
      ));
      repo.seed(_seedRequest(
        id: 'r3',
        fromUid: 'hal-uid',
        toUid: _meUid,
        fromCode: 'hal-code',
        toCode: _meCode,
        fromName: 'Hal',
        status: requestStatusDeclined,
      ));
      await _pumpCloudFriends(tester, repo: repo);

      // Fay: My Friends only. Gus: incoming row only. Hal: nowhere
      // (declined incoming requests are resolved and hidden).
      expect(find.text('Fay'), findsOneWidget);
      expect(find.text('Gus'), findsOneWidget);
      expect(find.text('Hal'), findsNothing);
    });

    testWidgets('local friends are never fabricated into cloud friendships',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      repo.seed(_seedRequest(
        id: 'r1',
        fromUid: 'ana-uid',
        toUid: _meUid,
        fromCode: 'ana-code',
        toCode: _meCode,
        fromName: 'Ana Santos',
        status: requestStatusAccepted,
      ));
      const localJson =
          '[{"name":"Ben Cruz","code":"code-ben"}]';
      await _pumpCloudFriends(
        tester,
        repo: repo,
        prefs: {'byahetayo_friends': localJson},
      );

      // Both render: Ana from the cloud, Ben from local storage.
      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);
      // But the cloud knows only Ana: Ben was never promoted.
      expect(
        (await repo.fetchFriends(_meUid)).map((f) => f.uid),
        ['ana-uid'],
      );
      // And the local list on disk is untouched by the cloud data.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('byahetayo_friends'), localJson);
    });

    testWidgets('remote failure keeps local UI with an honest error',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository()..throwOnFetch = true;
      await _pumpCloudFriends(tester, repo: repo);

      expect(
        find.text('Could not sync friend requests. Showing on-device data.'),
        findsOneWidget,
      );
      expect(find.text('No friends yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('alignment preserved in the cloud path',
        (WidgetTester tester) async {
      final repo = FakeFriendCloudRepository();
      await _pumpCloudFriends(tester, repo: repo);

      double cardCenterX(Finder f) {
        final card = tester.widget<Card>(
          find.ancestor(of: f, matching: find.byType(Card)).first,
        );
        return tester.getRect(find.byWidget(card)).center.dx;
      }

      double cardLeft(Finder f) {
        final card = tester.widget<Card>(
          find.ancestor(of: f, matching: find.byType(Card)).first,
        );
        return tester.getRect(find.byWidget(card)).left;
      }

      // QR + Chats empty state stay centered.
      final qr = find.byType(QrImageView).first;
      expect(
        (tester.getCenter(qr).dx - cardCenterX(qr)).abs(),
        lessThan(1.0),
      );
      final chatsEmpty = find.text('No conversations yet');
      expect(
        (tester.getCenter(chatsEmpty).dx - cardCenterX(chatsEmpty)).abs(),
        lessThan(1.0),
      );
      // Headings stay left: page header at the 20dp padding edge,
      // Incoming label at card-content left, left of card center.
      expect(tester.getTopLeft(find.text('Friends')).dx, closeTo(20, 1.0));
      final incoming = find.text('Incoming');
      expect(
        tester.getTopLeft(incoming).dx,
        closeTo(cardLeft(incoming) + 20, 1.0),
      );
      expect(
        tester.getCenter(incoming).dx,
        lessThan(cardCenterX(incoming)),
      );
      // Copy + Share still share one row at phone width.
      expect(
        (tester.getTopLeft(find.text('Copy')).dy -
                tester.getTopLeft(find.text('Share')).dy)
            .abs(),
        lessThan(1.0),
      );
    });
  });

  group('firestore.rules (friends blocks)', () {
    String block(String rules, String marker) {
      final start = rules.indexOf(marker);
      expect(start, isNot(-1), reason: '$marker missing from rules');
      var end = rules.indexOf('match /', start + marker.length);
      if (end == -1) end = rules.length;
      return rules.substring(start, end);
    }

    test('friend codes are get-only, requests participant-only', () {
      final rules = File('firestore.rules').readAsStringSync();

      // Earlier blocks untouched.
      expect(rules, contains('match /community_posts/{postId}'));
      expect(rules, contains('match /student_profiles/{userId}'));
      expect(rules, contains('match /points_transactions/{txnId}'));

      final codes = block(rules, 'match /friend_codes/{code}');
      expect(codes, contains('allow get: if isSignedIn();'));
      expect(codes, isNot(contains('allow read:')));
      expect(codes, isNot(contains('allow list:')));
      expect(
        codes,
        contains('request.resource.data.uid == request.auth.uid'),
      );
      expect(codes, contains('request.resource.data.code == code'));

      expect(rules, contains('match /user_friend_codes/{userId}'));
      expect(
        block(rules, 'match /user_friend_codes/{userId}'),
        contains('request.auth.uid == userId'),
      );

      final requests = block(rules, 'match /friend_requests/{requestId}');
      expect(
        requests,
        contains('resource.data.from == request.auth.uid'),
      );
      expect(
        requests,
        contains('resource.data.to == request.auth.uid'),
      );
      expect(
        requests,
        contains("request.resource.data.status == 'pending'"),
      );
      expect(
        requests,
        contains("request.resource.data.status in ['accepted', 'declined']"),
      );
      expect(
        requests,
        contains(".hasOnly(['status', 'updatedAt'])"),
      );
      expect(requests, contains('allow delete: if false;'));
    });
  });
}
