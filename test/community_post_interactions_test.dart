// Tests for CommunityPostInteractionWidget and its storage contract.
//
// The widget is tested against an in-memory fake that mirrors the
// real semantics (one reaction per user per post, toggle-off,
// switching, counts computed from stored documents, own-delete only,
// comment validation). The Firestore implementation itself cannot run
// without a Firestore backend; its transaction shape is the same
// shape the fake mirrors, and the rules (firestore.rules) enforce
// the same constraints server-side.
import 'package:estudyantego/features/community_interactions.dart';
import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _userA = AuthUser(
  uid: 'user-a',
  email: 'ana@example.com',
  displayName: 'Ana',
);
const _userB = AuthUser(
  uid: 'user-b',
  email: 'ben@example.com',
  displayName: 'Ben',
);

CommunityPost _sharedPost({required String id, required PostStatus status}) =>
    CommunityPost(
      routeName: 'Cabugao → Vigan City',
      vehicles: const ['traditional-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      from: 'Cabugao',
      to: 'Vigan City',
      faresByVehicle: const {'traditional-jeepney': 60},
      status: status,
      id: id,
      authorUid: 'author-1',
      createdAt: DateTime(2026, 11, 2),
    );

CommunityPost _localPost() => const CommunityPost(
      routeName: 'Vigan City → Cabugao',
      vehicles: ['modern-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Vigan City',
      from: 'Vigan City',
      to: 'Cabugao',
      faresByVehicle: {'modern-jeepney': 60},
      operatorName: 'CTransco',
      status: PostStatus.pending,
    );

/// In-memory fake mirroring the real repository semantics.
class FakeInteractions implements PostInteractionRepository {
  final Map<String, Map<String, PostReaction>> reactions = {};
  final Map<String, List<PostComment>> comments = {};

  /// Comment reactions: postId -> commentId -> uid -> reaction.
  final Map<String, Map<String, Map<String, PostReaction>>>
      commentReactions = {};
  var throwOnReaction = false;
  var throwOnCommentReaction = false;
  var _commentSeq = 0;

  @override
  Future<PostInteractionState> loadState({
    required String postId,
    required String? uid,
  }) async {
    final postReactions = reactions[postId] ?? {};
    var likes = 0;
    var dislikes = 0;
    for (final value in postReactions.values) {
      if (value == PostReaction.like) likes += 1;
      if (value == PostReaction.dislike) dislikes += 1;
    }
    return PostInteractionState(
      likeCount: likes,
      dislikeCount: dislikes,
      commentCount: comments[postId]?.length ?? 0,
      myReaction: uid == null ? null : postReactions[uid],
    );
  }

  @override
  Future<List<PostComment>> loadComments(String postId) async {
    final list = List<PostComment>.of(comments[postId] ?? []);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> setReaction({
    required String postId,
    required AuthUser user,
    required PostReaction tapped,
  }) async {
    if (throwOnReaction) {
      throw const PostInteractionException('Simulated network failure.');
    }
    final postReactions =
        reactions.putIfAbsent(postId, () => <String, PostReaction>{});
    final next = resolveReaction(postReactions[user.uid], tapped);
    if (next == null) {
      postReactions.remove(user.uid);
    } else {
      postReactions[user.uid] = next;
    }
  }

  @override
  Future<void> addComment({
    required String postId,
    required AuthUser user,
    required String text,
  }) async {
    final validation = commentValidationError(text);
    if (validation != null) {
      throw PostInteractionException(validation);
    }
    _commentSeq += 1;
    final list = comments.putIfAbsent(postId, () => <PostComment>[]);
    list.add(
      PostComment(
        id: 'c$_commentSeq',
        postId: postId,
        userId: user.uid,
        displayName: commentDisplayName(user),
        photoUrl: user.photoUrl,
        text: text.trim(),
        createdAt: DateTime(2026, 11, 2, 19, 41),
      ),
    );
  }

  @override
  Future<Map<String, CommentReactionState>> loadCommentReactions({
    required String postId,
    required String? uid,
  }) async {
    final postMap = commentReactions[postId] ?? {};
    final result = <String, CommentReactionState>{};
    for (final entry in postMap.entries) {
      var likes = 0;
      var dislikes = 0;
      PostReaction? mine;
      for (final reaction in entry.value.entries) {
        if (reaction.value == PostReaction.like) likes += 1;
        if (reaction.value == PostReaction.dislike) dislikes += 1;
        if (uid != null && reaction.key == uid) mine = reaction.value;
      }
      result[entry.key] = CommentReactionState(
        likeCount: likes,
        dislikeCount: dislikes,
        myReaction: mine,
      );
    }
    return result;
  }

  @override
  Future<void> setCommentReaction({
    required String postId,
    required String commentId,
    required AuthUser user,
    required PostReaction tapped,
  }) async {
    if (throwOnCommentReaction) {
      throw const PostInteractionException('Simulated network failure.');
    }
    final postMap =
        commentReactions.putIfAbsent(postId, () => <String, Map<String, PostReaction>>{});
    final commentMap =
        postMap.putIfAbsent(commentId, () => <String, PostReaction>{});
    final next = resolveReaction(commentMap[user.uid], tapped);
    if (next == null) {
      commentMap.remove(user.uid);
    } else {
      commentMap[user.uid] = next;
    }
  }

  @override
  Future<void> addReply({
    required String postId,
    required String parentCommentId,
    required AuthUser user,
    required String text,
  }) async {
    final validation = commentValidationError(text);
    if (validation != null) {
      throw PostInteractionException(validation);
    }
    final list = comments[postId] ?? [];
    PostComment? parent;
    for (final c in list) {
      if (c.id == parentCommentId) parent = c;
    }
    if (parent == null) {
      throw const PostInteractionException(
        'That comment no longer exists.',
      );
    }
    if (!canReplyTo(list, parent)) {
      throw const PostInteractionException(
        'Replies cannot go deeper than 2 levels.',
      );
    }
    _commentSeq += 1;
    comments.putIfAbsent(postId, () => <PostComment>[]).add(
      PostComment(
        id: 'c$_commentSeq',
        postId: postId,
        userId: user.uid,
        displayName: commentDisplayName(user),
        photoUrl: user.photoUrl,
        text: text.trim(),
        createdAt: DateTime(2026, 11, 2, 19, 41),
        parentCommentId: parentCommentId,
      ),
    );
  }

  // Deletes only the target comment: replies whose parent is gone
  // are promoted to top level by buildCommentTree (the Firestore
  // rules allow deleting only your own comment, so a cascade over
  // other users' replies would fail there too).
  @override
  Future<void> deleteComment({
    required String postId,
    required String commentId,
    required AuthUser user,
  }) async {
    final list = comments[postId];
    if (list == null) {
      throw const PostInteractionException('That comment no longer exists.');
    }
    final index = list.indexWhere((c) => c.id == commentId);
    if (index < 0) {
      throw const PostInteractionException('That comment no longer exists.');
    }
    if (list[index].userId != user.uid) {
      throw const PostInteractionException(
        'You can only delete your own comments.',
      );
    }
    list.removeAt(index);
  }
}

Future<void> _pumpWidget(
  WidgetTester tester,
  FakeInteractions fake, {
  required CommunityPost post,
  AuthUser? user,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CommunityPostInteractionWidget(
            post: post,
            currentUser: user,
            repository: fake,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('reaction toggle semantics', () {
    test('tapping a new reaction sets it', () {
      expect(resolveReaction(null, PostReaction.like), PostReaction.like);
      expect(
        resolveReaction(null, PostReaction.dislike),
        PostReaction.dislike,
      );
    });

    test('tapping the held reaction removes it', () {
      expect(resolveReaction(PostReaction.like, PostReaction.like), isNull);
      expect(
        resolveReaction(PostReaction.dislike, PostReaction.dislike),
        isNull,
      );
    });

    test('tapping the other reaction switches to it', () {
      expect(
        resolveReaction(PostReaction.like, PostReaction.dislike),
        PostReaction.dislike,
      );
      expect(
        resolveReaction(PostReaction.dislike, PostReaction.like),
        PostReaction.like,
      );
    });
  });

  group('comment validation and identity', () {
    test('empty and whitespace-only comments are rejected', () {
      expect(commentValidationError(''), isNotNull);
      expect(commentValidationError('   '), isNotNull);
    });

    test('overlong comments are rejected, 500 chars accepted', () {
      expect(commentValidationError('x' * 501), isNotNull);
      expect(commentValidationError('x' * 500), isNull);
      expect(commentValidationError('hello'), isNull);
    });

    test('display name falls back to email prefix, then Student', () {
      expect(
        commentDisplayName(
          const AuthUser(
            uid: 'u',
            email: 'ana@example.com',
            displayName: '  Ana  ',
          ),
        ),
        'Ana',
      );
      expect(
        commentDisplayName(
          const AuthUser(uid: 'u', email: 'ben@example.com'),
        ),
        'ben',
      );
      expect(
        commentDisplayName(const AuthUser(uid: 'u', email: '')),
        'Student',
      );
    });

    test('local post key is stable and distinguishes posts', () {
      final a = _localPost();
      const b = CommunityPost(
        routeName: 'Cabugao → Vigan City',
        vehicles: ['traditional-jeepney'],
        hours: '',
        fare: 0,
        hubName: 'Cabugao',
        from: 'Cabugao',
        to: 'Vigan City',
      );
      expect(localPostKey(a), localPostKey(_localPost()));
      expect(localPostKey(a), isNot(localPostKey(b)));
    });

    test('comment timestamp formats as expected', () {
      expect(
        formatCommentTime(DateTime(2026, 11, 2, 19, 41)),
        'Nov 2, 2026 · 7:41 PM',
      );
    });

    test('rate guard blocks within 10s and allows after', () {
      final guard = CommentRateGuard();
      final now = DateTime(2026, 11, 2, 19, 41);
      expect(
        guard.canSubmit(postId: 'p', uid: 'u', now: now),
        isTrue,
      );
      guard.markSubmitted(postId: 'p', uid: 'u', now: now);
      expect(
        guard.canSubmit(
          postId: 'p',
          uid: 'u',
          now: now.add(const Duration(seconds: 5)),
        ),
        isFalse,
      );
      expect(
        guard.canSubmit(
          postId: 'p',
          uid: 'u',
          now: now.add(const Duration(seconds: 10)),
        ),
        isTrue,
      );
      expect(
        guard.canSubmit(postId: 'p', uid: 'other', now: now),
        isTrue,
      );
    });
  });

  group('CommunityPostInteractionWidget', () {
    testWidgets('like toggles on and off with correct counts', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));

      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));

      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
    });

    testWidgets('dislike toggles on and off with correct counts', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Dislike'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_down), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Dislike'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
    });

    testWidgets('switching like to dislike updates both counts', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Dislike'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.byIcon(Icons.thumb_down), findsOneWidget);
      // Like back to 0, dislike now 1, comments still 0.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      // The single '1' must be the dislike count, not the like count:
      // the like button is unselected again.
      final likeButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Like'),
          matching: find.byType(TextButton),
        ),
      );
      expect(likeButton.onPressed, isNotNull);
    });

    testWidgets('one reaction per user: a second user reacts independently',
        (tester) async {
      final fake = FakeInteractions();
      // User A already liked; user B opens the same post.
      fake.reactions['p1'] = {'user-a': PostReaction.like};
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userB,
      );
      // B holds no reaction, but the count from A is visible.
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      // A's reaction is untouched: the stored map holds both users.
      expect(fake.reactions['p1']?.length, 2);
      expect(fake.reactions['p1']?['user-a'], PostReaction.like);
      expect(fake.reactions['p1']?['user-b'], PostReaction.like);
    });

    testWidgets('failed reaction shows an error and keeps old counts', (
      tester,
    ) async {
      final fake = FakeInteractions()..throwOnReaction = true;
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.text('Simulated network failure.'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
    });

    testWidgets('pending shared posts render no interaction row', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p2', status: PostStatus.pending),
        user: _userA,
      );
      expect(find.text('Like'), findsNothing);
      expect(find.text('Dislike'), findsNothing);
      expect(find.text('Comment'), findsNothing);
    });

    testWidgets('local posts show the interaction row', (tester) async {
      final fake = FakeInteractions();
      await _pumpWidget(tester, fake, post: _localPost(), user: _userA);
      expect(find.text('Like'), findsOneWidget);
      expect(find.text('Dislike'), findsOneWidget);
      expect(find.text('Comment'), findsOneWidget);
    });

    testWidgets('signed-out users see counts but cannot react', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
      );
      await tester.tap(find.text('Comment'));
      await tester.pumpAndSettle();
      expect(find.text('Comments (0)'), findsNothing);
    });

    testWidgets('comment sheet validates, submits, and counts', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Comment'));
      await tester.pumpAndSettle();
      expect(find.text('Comments (0)'), findsOneWidget);

      // Empty submit is rejected, nothing is stored.
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(find.text('Write a comment first.'), findsOneWidget);
      expect(find.text('Comments (0)'), findsOneWidget);

      // Valid submit appears with name and text; count becomes 1.
      await tester.enterText(find.byType(TextField), 'Maganda ang ruta!');
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(find.text('Maganda ang ruta!'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Comments (1)'), findsOneWidget);

      // Closing the sheet refreshes the row count.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('overlong comments are rejected in the sheet', (
      tester,
    ) async {
      final fake = FakeInteractions();
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Comment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x' * 501);
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(
        find.text('Comments are limited to 500 characters.'),
        findsOneWidget,
      );
      expect(find.text('Comments (0)'), findsOneWidget);
    });

    testWidgets('own comments can be deleted, others cannot', (
      tester,
    ) async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [
        PostComment(
          id: 'c-b',
          postId: 'p1',
          userId: _userB.uid,
          displayName: 'Ben',
          text: 'Comment from Ben',
          createdAt: DateTime(2026, 11, 2, 19, 30),
        ),
      ];
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Comment'));
      await tester.pumpAndSettle();
      expect(find.text('Comment from Ben'), findsOneWidget);
      expect(find.byTooltip('Delete comment'), findsNothing);

      // Add an own comment, then delete it.
      await tester.enterText(find.byType(TextField), 'My own comment');
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(find.text('Comments (2)'), findsOneWidget);
      expect(find.byTooltip('Delete comment'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete comment'));
      await tester.pumpAndSettle();
      expect(find.text('My own comment'), findsNothing);
      expect(find.text('Comment from Ben'), findsOneWidget);
      expect(find.text('Comments (1)'), findsOneWidget);
    });

    testWidgets('widget resolves colors from a dark color scheme', (
      tester,
    ) async {
      final fake = FakeInteractions();
      const darkOutline = Color(0xFF343B3D);
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF34D399),
            onSurfaceVariant: Color(0xFFB0B8B5),
            outline: darkOutline,
          ),
        ),
      );
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, darkOutline);
      expect(find.text('Like'), findsOneWidget);
    });
  group('comment reactions', () {
    test('reaction id binds one user to one comment', () {
      expect(commentReactionId('c1', 'user-a'), 'c1_user-a');
      expect(
        commentReactionId('c1', 'user-a'),
        isNot(commentReactionId('c1', 'user-b')),
      );
      expect(
        commentReactionId('c1', 'user-a'),
        isNot(commentReactionId('c2', 'user-a')),
      );
    });

    test('fake comment reaction toggles, switches, and stays single',
        () async {
      final fake = FakeInteractions();
      await fake.setCommentReaction(
        postId: 'p1',
        commentId: 'c1',
        user: _userA,
        tapped: PostReaction.like,
      );
      var state = await fake.loadCommentReactions(postId: 'p1', uid: 'user-a');
      expect(state['c1']?.likeCount, 1);
      expect(state['c1']?.myReaction, PostReaction.like);

      // Same tap again removes it (no duplicate).
      await fake.setCommentReaction(
        postId: 'p1',
        commentId: 'c1',
        user: _userA,
        tapped: PostReaction.like,
      );
      state = await fake.loadCommentReactions(postId: 'p1', uid: 'user-a');
      expect(state['c1']?.likeCount, 0);
      expect(state['c1']?.myReaction, isNull);

      // Switch: like -> dislike moves the count, never both.
      await fake.setCommentReaction(
        postId: 'p1',
        commentId: 'c1',
        user: _userA,
        tapped: PostReaction.like,
      );
      await fake.setCommentReaction(
        postId: 'p1',
        commentId: 'c1',
        user: _userA,
        tapped: PostReaction.dislike,
      );
      state = await fake.loadCommentReactions(postId: 'p1', uid: 'user-a');
      expect(state['c1']?.likeCount, 0);
      expect(state['c1']?.dislikeCount, 1);
      expect(state['c1']?.myReaction, PostReaction.dislike);
      // One stored reaction per user per comment, by construction.
      expect(fake.commentReactions['p1']?['c1']?.length, 1);
    });

    test('two users react to the same comment independently', () async {
      final fake = FakeInteractions();
      await fake.setCommentReaction(
        postId: 'p1',
        commentId: 'c1',
        user: _userA,
        tapped: PostReaction.like,
      );
      await fake.setCommentReaction(
        postId: 'p1',
        commentId: 'c1',
        user: _userB,
        tapped: PostReaction.like,
      );
      final state =
          await fake.loadCommentReactions(postId: 'p1', uid: 'user-a');
      expect(state['c1']?.likeCount, 2);
      expect(state['c1']?.myReaction, PostReaction.like);
    });
  });

  group('comment replies and tree', () {
    PostComment commentFor(
      String id, {
      String? parent,
      DateTime? at,
    }) =>
        PostComment(
          id: id,
          postId: 'p1',
          userId: 'user-a',
          displayName: 'Ana',
          text: 'text $id',
          createdAt: at ?? DateTime(2026, 11, 2, 19, 41),
          parentCommentId: parent,
        );

    test('depth is 0 / 1 / 2 along the parent chain', () {
      final all = [
        commentFor('c0'),
        commentFor('c1', parent: 'c0'),
        commentFor('c2', parent: 'c1'),
      ];
      expect(commentDepth(all, all[0]), 0);
      expect(commentDepth(all, all[1]), 1);
      expect(commentDepth(all, all[2]), 2);
      expect(canReplyTo(all, all[0]), isTrue);
      expect(canReplyTo(all, all[1]), isTrue);
      expect(canReplyTo(all, all[2]), isFalse);
    });

    test('tree nests replies and promotes orphans to top level', () {
      final all = [
        commentFor('c0', at: DateTime(2026, 11, 2, 19, 40)),
        commentFor('c1', parent: 'c0', at: DateTime(2026, 11, 2, 19, 41)),
        commentFor('orphan', parent: 'gone', at: DateTime(2026, 11, 2, 19, 42)),
      ];
      final roots = buildCommentTree(all);
      expect(roots.map((r) => r.comment.id), ['orphan', 'c0']);
      expect(roots.last.children.map((c) => c.comment.id), ['c1']);
      expect(roots.last.children.single.depth, 1);
    });

    test('fake reply is stored under its parent, depth-2 is rejected',
        () async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [commentFor('c0')];
      await fake.addReply(
        postId: 'p1',
        parentCommentId: 'c0',
        user: _userB,
        text: 'Reply one',
      );
      await fake.addReply(
        postId: 'p1',
        parentCommentId: 'c1',
        user: _userA,
        text: 'Reply two',
      );
      expect(
        () => fake.addReply(
          postId: 'p1',
          parentCommentId: 'c2',
          user: _userB,
          text: 'Too deep',
        ),
        throwsA(isA<PostInteractionException>()),
      );
      expect(fake.comments['p1']?.length, 3);
      final roots = buildCommentTree(fake.comments['p1']!);
      expect(roots.length, 1);
      expect(roots.single.children.length, 1);
      expect(roots.single.children.single.children.length, 1);
    });

    test('deleting a parent keeps its replies visible (promoted)', () async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [
        commentFor('c0'),
        commentFor('c1', parent: 'c0'),
      ];
      await fake.deleteComment(
        postId: 'p1',
        commentId: 'c0',
        user: _userA,
      );
      final roots = buildCommentTree(fake.comments['p1']!);
      expect(roots.map((r) => r.comment.id), ['c1']);
    });

    test('reply to a missing parent is rejected', () async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [commentFor('c0')];
      expect(
        () => fake.addReply(
          postId: 'p1',
          parentCommentId: 'nope',
          user: _userB,
          text: 'Hello?',
        ),
        throwsA(isA<PostInteractionException>()),
      );
    });
  });

  group('comment sheet reactions and replies', () {
    Future<void> openSheet(WidgetTester tester, FakeInteractions fake) async {
      await _pumpWidget(
        tester,
        fake,
        post: _sharedPost(id: 'p1', status: PostStatus.approved),
        user: _userA,
      );
      await tester.tap(find.text('Comment'));
      await tester.pumpAndSettle();
    }

    testWidgets('comment like toggles count in the sheet', (tester) async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [
        PostComment(
          id: 'c-b',
          postId: 'p1',
          userId: _userB.uid,
          displayName: 'Ben',
          text: 'Comment from Ben',
          createdAt: DateTime(2026, 11, 2, 19, 30),
        ),
      ];
      await openSheet(tester, fake);
      expect(find.text('Comment from Ben'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      // The post row's Like sits behind the modal barrier, so the
      // sheet's own Like button is the LAST 'Like' text in the tree.
      await tester.tap(find.text('Like').last);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      var state =
          await fake.loadCommentReactions(postId: 'p1', uid: 'user-a');
      expect(state['c-b']?.likeCount, 1);
      await tester.tap(find.text('Like').last);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up), findsNothing);
      state = await fake.loadCommentReactions(postId: 'p1', uid: 'user-a');
      expect(state['c-b']?.likeCount, 0);
    });

    testWidgets('reply flow shows Replying to, then the reply underneath',
        (tester) async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [
        PostComment(
          id: 'c-b',
          postId: 'p1',
          userId: _userB.uid,
          displayName: 'Ben',
          text: 'Comment from Ben',
          createdAt: DateTime(2026, 11, 2, 19, 30),
        ),
      ];
      await openSheet(tester, fake);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to @Ben'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hi! Welcome!');
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(find.text('Hi! Welcome!'), findsOneWidget);
      expect(find.text('Comments (2)'), findsOneWidget);
      // Submitting a reply auto-expands its parent, so the reply
      // is visible immediately and the button already says Hide.
      expect(find.text('Hide replies'), findsOneWidget);
      await tester.tap(find.text('Hide replies'));
      await tester.pumpAndSettle();
      expect(find.text('View replies (1)'), findsOneWidget);
      expect(find.text('Hi! Welcome!'), findsNothing);
      await tester.tap(find.text('View replies (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Hide replies'), findsOneWidget);
      expect(find.text('Hi! Welcome!'), findsOneWidget);
    });

    testWidgets('depth-2 comment shows no Reply button', (tester) async {
      final fake = FakeInteractions();
      fake.comments['p1'] = [
        PostComment(
          id: 'c0',
          postId: 'p1',
          userId: _userB.uid,
          displayName: 'Ben',
          text: 'Top',
          createdAt: DateTime(2026, 11, 2, 19, 30),
        ),
        PostComment(
          id: 'c1',
          postId: 'p1',
          userId: _userA.uid,
          displayName: 'Ana',
          text: 'Reply one',
          createdAt: DateTime(2026, 11, 2, 19, 31),
          parentCommentId: 'c0',
        ),
        PostComment(
          id: 'c2',
          postId: 'p1',
          userId: _userB.uid,
          displayName: 'Ben',
          text: 'Reply two',
          createdAt: DateTime(2026, 11, 2, 19, 32),
          parentCommentId: 'c1',
        ),
      ];
      await openSheet(tester, fake);
      // Expand both levels: only the top comment and its reply get
      // a Reply button; the depth-2 comment does not.
      await tester.tap(find.text('View replies (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View replies (1)').last);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsNWidgets(2));
      expect(find.text('Reply two'), findsOneWidget);
    });

    testWidgets('failed comment reaction keeps old count and shows error',
        (tester) async {
      final fake = FakeInteractions()..throwOnCommentReaction = true;
      fake.comments['p1'] = [
        PostComment(
          id: 'c-b',
          postId: 'p1',
          userId: _userB.uid,
          displayName: 'Ben',
          text: 'Comment from Ben',
          createdAt: DateTime(2026, 11, 2, 19, 30),
        ),
      ];
      await openSheet(tester, fake);
      await tester.tap(find.text('Like').last);
      await tester.pumpAndSettle();
      expect(find.text('Simulated network failure.'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up), findsNothing);
    });
  });

  });
}
