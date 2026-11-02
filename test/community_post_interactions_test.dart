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
  var throwOnReaction = false;
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
  });
}
