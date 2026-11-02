// Post approval workflow gaps: author-visible rejections, rejection
// reasons, and the In Review / Waiting Approval wording.
//
// Covers: (1) a rejected shared post is visible only to its author
// (with status + reason) and never to other users; (2) an admin can
// reject with an optional reason (max 300 chars) that the author
// sees, and cannot attach a reason without rejecting; (3) the new
// wording in the user badge, the share confirmation path, and the
// admin section headers.
import 'package:estudyantego/features/communities_tab.dart';
import 'package:estudyantego/features/community_admin.dart';
import 'package:estudyantego/features/community_post_repository.dart';
import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _author = AuthUser(uid: 'author-1', email: 'author@example.com');
const _other = AuthUser(uid: 'other-1', email: 'other@example.com');
const _admin = AuthUser(
  uid: 'admin-1',
  email: 'stevenjoereyes0625@gmail.com',
);

CommunityPost _sharedPost({
  required String id,
  required String authorUid,
  required PostStatus status,
  String? rejectionReason,
}) =>
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
      authorUid: authorUid,
      createdAt: DateTime(2026, 11, 2),
      rejectionReason: rejectionReason,
    );

void main() {
  group('rejected post visibility', () {
    test('author sees own rejected post, nobody else does', () {
      final rejected = _sharedPost(
        id: 'r1',
        authorUid: 'author-1',
        status: PostStatus.rejected,
      );
      expect(sharedPostVisibleTo(rejected, _author), isTrue);
      expect(sharedPostVisibleTo(rejected, _other), isFalse);
      // Admins review rejected posts in Post approvals, not in the
      // main list, so main-list visibility stays author-only.
      expect(sharedPostVisibleTo(rejected, _admin), isFalse);
      expect(sharedPostVisibleTo(rejected, null), isFalse);
    });

    test('fake repository returns own rejected posts to the author only',
        () async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'r1',
        authorUid: 'author-1',
        status: PostStatus.rejected,
      ));
      final authorPosts = await repo.loadVisiblePosts(_author);
      expect(authorPosts.map((p) => p.id), contains('r1'));
      expect(await repo.loadVisiblePosts(_other), isEmpty);
      expect(await repo.loadVisiblePosts(_admin), isEmpty);
    });
  });

  group('rejection reason validation', () {
    test('a reason cannot accompany an approval', () {
      expect(
        postStatusUpdateError(
          status: PostStatus.approved,
          rejectionReason: 'Not a real route.',
        ),
        isNotNull,
      );
      expect(
        postStatusUpdateError(
          status: PostStatus.approved,
          clearRejectionReason: true,
        ),
        isNotNull,
      );
    });

    test('a reason longer than 300 characters is refused', () {
      final tooLong = 'x' * (kMaxRejectionReasonLength + 1);
      expect(
        postStatusUpdateError(
          status: PostStatus.rejected,
          rejectionReason: tooLong,
        ),
        isNotNull,
      );
      expect(
        postStatusUpdateError(
          status: PostStatus.rejected,
          rejectionReason: 'x' * kMaxRejectionReasonLength,
        ),
        isNull,
      );
    });

    test('a reason on a rejection, and an empty reason, are valid', () {
      expect(
        postStatusUpdateError(
          status: PostStatus.rejected,
          rejectionReason: 'Duplicate route.',
        ),
        isNull,
      );
      expect(
        postStatusUpdateError(
          status: PostStatus.rejected,
          rejectionReason: '   ',
        ),
        isNull,
      );
    });
  });

  group('fake repository rejection reason storage', () {
    test('rejecting with a reason stores it', () async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.pending,
      ));
      final post = repo.stored.single;
      await repo.updatePostStatus(
        post,
        PostStatus.rejected,
        rejectionReason: 'Duplicate route.',
      );
      expect(repo.stored.single.status, PostStatus.rejected);
      expect(repo.stored.single.rejectionReason, 'Duplicate route.');
    });

    test('rejecting without a reason clears a stale reason', () async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.approved,
        rejectionReason: 'Old reason.',
      ));
      final post = repo.stored.single;
      await repo.updatePostStatus(
        post,
        PostStatus.rejected,
        clearRejectionReason: true,
      );
      expect(repo.stored.single.status, PostStatus.rejected);
      expect(repo.stored.single.rejectionReason, isNull);
    });

    test('rejecting without reason details leaves a reason untouched',
        () async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.approved,
        rejectionReason: 'Old reason.',
      ));
      final post = repo.stored.single;
      await repo.updatePostStatus(post, PostStatus.rejected);
      expect(repo.stored.single.rejectionReason, 'Old reason.');
    });

    test('attaching a reason to an approval throws', () async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.pending,
      ));
      final post = repo.stored.single;
      await expectLater(
        repo.updatePostStatus(
          post,
          PostStatus.approved,
          rejectionReason: 'Should not stick.',
        ),
        throwsArgumentError,
      );
      expect(repo.stored.single.status, PostStatus.pending);
    });
  });

  group('author rejected card in the Communities tab', () {
    Future<void> pumpTab(
      WidgetTester tester,
      AuthUser user,
      FakePostRepository repo,
    ) async {
      SharedPreferences.setMockInitialValues({samplePostSeededKey: true});
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunitiesTab(
              currentUser: user,
              postRepository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('author sees Rejected badge, reason, no interactions',
        (tester) async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'r1',
        authorUid: 'author-1',
        status: PostStatus.rejected,
        rejectionReason: 'Route already covered.',
      ));
      await pumpTab(tester, _author, repo);
      expect(find.text('Rejected'), findsOneWidget);
      expect(
        find.text('Rejection reason: Route already covered.'),
        findsOneWidget,
      );
      // Rejected shared posts are not public, so they get no
      // interaction row (the widget itself enforces the same gate).
      expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
      expect(find.byIcon(Icons.thumb_down_outlined), findsNothing);
      expect(find.byIcon(Icons.comment_outlined), findsNothing);
    });

    testWidgets('other users never see the rejected post', (tester) async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'r1',
        authorUid: 'author-1',
        status: PostStatus.rejected,
        rejectionReason: 'Route already covered.',
      ));
      await pumpTab(tester, _other, repo);
      expect(find.text('No shared posts yet.'), findsOneWidget);
      expect(find.text('Rejected'), findsNothing);
    });

    testWidgets('pending card shows In Review', (tester) async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.pending,
      ));
      await pumpTab(tester, _author, repo);
      expect(find.text('In Review'), findsOneWidget);
    });

    testWidgets('details sheet shows Rejected status and the reason',
        (tester) async {
      final repo = FakePostRepository();
      repo.stored.add(_sharedPost(
        id: 'r1',
        authorUid: 'author-1',
        status: PostStatus.rejected,
        rejectionReason: 'Route already covered.',
      ));
      await pumpTab(tester, _author, repo);
      await tester.tap(find.text('View Route'));
      await tester.pumpAndSettle();
      expect(find.text('Rejection reason'), findsOneWidget);
      expect(find.text('Route already covered.'), findsOneWidget);
    });
  });

  group('admin reject dialog', () {
    testWidgets('admin headers say Waiting Approval', (tester) async {
      final repo = FakePostRepository();
      final pending = _sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.pending,
      );
      repo.stored.add(pending);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityAdminScreen(
            localPosts: const [],
            onLocalChanged: (_) {},
            sharedPosts: [pending],
            postRepository: repo,
            onSharedChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared posts — Waiting Approval'), findsOneWidget);
      expect(find.text('Local posts — Waiting Approval'), findsOneWidget);
    });

    testWidgets('rejecting with a reason stores it', (tester) async {
      final repo = FakePostRepository();
      final pending = _sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.pending,
      );
      repo.stored.add(pending);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityAdminScreen(
            localPosts: const [],
            onLocalChanged: (_) {},
            sharedPosts: [pending],
            postRepository: repo,
            onSharedChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(find.text('Reject this post?'), findsOneWidget);
      expect(find.text('Reason (optional)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Duplicate route.');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(repo.stored.single.status, PostStatus.rejected);
      expect(repo.stored.single.rejectionReason, 'Duplicate route.');
    });

    testWidgets('cancelling the reject dialog changes nothing',
        (tester) async {
      final repo = FakePostRepository();
      final pending = _sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.pending,
      );
      repo.stored.add(pending);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityAdminScreen(
            localPosts: const [],
            onLocalChanged: (_) {},
            sharedPosts: [pending],
            postRepository: repo,
            onSharedChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repo.stored.single.status, PostStatus.pending);
      expect(repo.stored.single.rejectionReason, isNull);
    });

    testWidgets('rejecting with an empty reason clears a stale reason',
        (tester) async {
      final repo = FakePostRepository();
      final published = _sharedPost(
        id: 'p1',
        authorUid: 'author-1',
        status: PostStatus.approved,
        rejectionReason: 'Old reason.',
      );
      repo.stored.add(published);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityAdminScreen(
            localPosts: const [],
            onLocalChanged: (_) {},
            sharedPosts: [published],
            postRepository: repo,
            onSharedChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(repo.stored.single.status, PostStatus.rejected);
      expect(repo.stored.single.rejectionReason, isNull);
    });
  });
}
