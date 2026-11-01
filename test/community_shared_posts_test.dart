import 'package:cloud_firestore/cloud_firestore.dart';
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

CommunityPost _shared({
  required String id,
  required String authorUid,
  required PostStatus status,
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
    );

void main() {
  group('shared post visibility', () {
    test('approved shared posts are visible to any signed-in user', () {
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'x', status: PostStatus.approved), _other),
        isTrue,
      );
    });

    test('approved shared posts are hidden from signed-out users', () {
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'x', status: PostStatus.approved), null),
        isFalse,
      );
    });

    test('pending shared posts are visible to their author', () {
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'author-1', status: PostStatus.pending), _author),
        isTrue,
      );
    });

    test('pending shared posts are hidden from other users', () {
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'author-1', status: PostStatus.pending), _other),
        isFalse,
      );
    });

    test('pending shared posts are visible to admins', () {
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'author-1', status: PostStatus.pending), _admin),
        isTrue,
      );
    });

    test('rejected shared posts are hidden from everyone, even admins', () {
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'author-1', status: PostStatus.rejected), _admin),
        isFalse,
      );
      expect(
        sharedPostVisibleTo(_shared(id: '1', authorUid: 'author-1', status: PostStatus.rejected), _author),
        isFalse,
      );
    });

    test('local posts are never shared-visible', () {
      const local = CommunityPost(
        routeName: 'A → B',
        vehicles: [],
        hours: '',
        fare: 0,
        hubName: 'Cabugao',
        status: PostStatus.approved,
      );
      expect(sharedPostVisibleTo(local, _author), isFalse);
    });
  });

  group('fake repository mirrors the sharing rule', () {
    test('create stamps author, pending status, and an id', () async {
      final repo = FakePostRepository();
      const draft = CommunityPost(
        routeName: 'Cabugao → Vigan City',
        vehicles: ['traditional-jeepney'],
        hours: '',
        fare: 0,
        hubName: 'Cabugao',
        from: 'Cabugao',
        to: 'Vigan City',
        faresByVehicle: {'traditional-jeepney': 60},
      );
      final created = await repo.createPost(draft, _author);
      expect(created.post.id, isNotNull);
      expect(created.post.authorUid, 'author-1');
      expect(created.post.status, PostStatus.pending);
      expect(created.photoDropped, isFalse);
    });

    test('create drops an oversized photo instead of failing', () async {
      final repo = FakePostRepository();
      final draft = CommunityPost(
        routeName: 'Cabugao → Vigan City',
        vehicles: const ['traditional-jeepney'],
        hours: '',
        fare: 0,
        hubName: 'Cabugao',
        from: 'Cabugao',
        to: 'Vigan City',
        faresByVehicle: const {'traditional-jeepney': 60},
        photoBase64: 'x' * (kMaxSharedDocBytes + 1000),
      );
      final created = await repo.createPost(draft, _author);
      expect(created.photoDropped, isTrue);
      expect(created.post.photoBase64, isNull);
      expect(repo.stored.single.photoBase64, isNull);
    });

    test('load merges approved plus own pending, hides the rest', () async {
      final repo = FakePostRepository();
      repo.stored.addAll([
        _shared(id: 'a', authorUid: 'someone', status: PostStatus.approved),
        _shared(id: 'p', authorUid: 'author-1', status: PostStatus.pending),
        _shared(id: 'q', authorUid: 'someone', status: PostStatus.pending),
        _shared(id: 'r', authorUid: 'author-1', status: PostStatus.rejected),
      ]);
      final visible = await repo.loadVisiblePosts(_author);
      expect(visible.map((p) => p.id), containsAll(['a', 'p']));
      expect(visible.map((p) => p.id), isNot(contains('q')));
      expect(visible.map((p) => p.id), isNot(contains('r')));
      expect(await repo.loadVisiblePosts(null), isEmpty);
    });

    test('admin sees all pending posts', () async {
      final repo = FakePostRepository();
      repo.stored.addAll([
        _shared(id: 'q', authorUid: 'someone', status: PostStatus.pending),
      ]);
      final visible = await repo.loadVisiblePosts(_admin);
      expect(visible.map((p) => p.id), contains('q'));
    });

    test('status update and delete act on the stored post', () async {
      final repo = FakePostRepository();
      repo.stored.add(
        _shared(id: 'a', authorUid: 'x', status: PostStatus.pending),
      );
      final post = repo.stored.single;
      await repo.updatePostStatus(post, PostStatus.approved);
      expect(repo.stored.single.status, PostStatus.approved);
      await repo.deletePost(post);
      expect(repo.stored, isEmpty);
    });
  });

  group('firestore document mapping', () {
    test('create map forces pending and stamps the author', () {
      final doc = sharedPostToDoc(
        const CommunityPost(
          routeName: 'Cabugao → Vigan City',
          vehicles: ['traditional-jeepney'],
          hours: '',
          fare: 0,
          hubName: 'Cabugao',
          from: 'Cabugao',
          to: 'Vigan City',
          faresByVehicle: {'traditional-jeepney': 60},
          status: PostStatus.approved,
        ),
        'uid-9',
      );
      expect(doc['status'], 'pending');
      expect(doc['authorUid'], 'uid-9');
      expect(doc.containsKey('id'), isFalse);
      expect(doc.containsKey('createdAt'), isFalse);
    });

    test('fromDoc parses fields, timestamp, and id', () {
      final post = sharedPostFromDoc('doc-1', {
        'routeName': 'Cabugao → Vigan City',
        'vehicles': ['traditional-jeepney'],
        'hours': '',
        'fare': 0,
        'hubName': 'Cabugao',
        'from': 'Cabugao',
        'to': 'Vigan City',
        'faresByVehicle': {'traditional-jeepney': 60},
        'operatorName': 'CTransco',
        'status': 'approved',
        'authorUid': 'uid-9',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 2)),
      });
      expect(post.id, 'doc-1');
      expect(post.isShared, isTrue);
      expect(post.authorUid, 'uid-9');
      expect(post.status, PostStatus.approved);
      expect(post.createdAt, DateTime(2026, 11, 2));
      expect(post.faresByVehicle['traditional-jeepney'], 60);
    });
  });

  group('communities tab shared section', () {
    Future<void> pumpTab(
      WidgetTester tester, {
      AuthUser? user,
      PostRepository? repository,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunitiesTab(
              currentUser: user,
              postRepository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shared and local posts are chipped distinctly', (
      tester,
    ) async {
      final repo = FakePostRepository();
      repo.stored.add(
        _shared(id: 's1', authorUid: 'x', status: PostStatus.approved),
      );
      // No seed flag: the sample post seeds locally and stays local.
      await pumpTab(tester, user: _other, repository: repo, prefs: {});
      expect(find.text('Shared post'), findsOneWidget);
      expect(find.text('Local post'), findsOneWidget);
      expect(find.text('Cabugao → Vigan City'), findsOneWidget);
      expect(find.text('Vigan City → Cabugao'), findsOneWidget);
    });

    testWidgets('signed-out tab explains sign-in for shared posts', (
      tester,
    ) async {
      await pumpTab(
        tester,
        repository: FakePostRepository(),
        prefs: {samplePostSeededKey: true},
      );
      expect(
        find.text('Sign in to see posts shared by the community.'),
        findsOneWidget,
      );
    });

    testWidgets('signed-in tab without a repository says sharing is unavailable',
        (tester) async {
      await pumpTab(
        tester,
        user: _other,
        prefs: {samplePostSeededKey: true},
      );
      expect(
        find.textContaining("isn't available yet"),
        findsOneWidget,
      );
    });

    testWidgets('create without sharing fails honestly and saves nothing',
        (tester) async {
      await pumpTab(
        tester,
        prefs: {samplePostSeededKey: true},
      );
      await tester.tap(find.text('Share info'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Cabugao');
      await tester.enterText(find.byType(TextField).at(1), 'Vigan City');
      await tester.tap(find.text('Traditional Jeepney'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '60');
      await tester.tap(find.text('Share post'));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't available yet"), findsOneWidget);
      // The sheet stayed open with the error; nothing was saved.
      expect(find.text('Share a route'), findsOneWidget);
      expect(find.text('Cabugao → Vigan City'), findsNothing);
    });

    testWidgets('create signed out with a repository asks for sign-in',
        (tester) async {
      await pumpTab(
        tester,
        repository: FakePostRepository(),
        prefs: {samplePostSeededKey: true},
      );
      await tester.tap(find.text('Share info'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Cabugao');
      await tester.enterText(find.byType(TextField).at(1), 'Vigan City');
      await tester.tap(find.text('Traditional Jeepney'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '60');
      await tester.tap(find.text('Share post'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sign in to share a post with the community.'),
        findsOneWidget,
      );
      expect(find.text('Cabugao → Vigan City'), findsNothing);
    });
  });

  group('admin screen shared review', () {
    testWidgets('shared approve moves the post to Published', (
      tester,
    ) async {
      final repo = FakePostRepository();
      final pending =
          _shared(id: 's1', authorUid: 'x', status: PostStatus.pending);
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
      expect(
        find.text('Shared posts — Pending verification'),
        findsOneWidget,
      );
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(repo.stored.single.status, PostStatus.approved);
      expect(find.text('Shared posts — Published'), findsOneWidget);
    });

    testWidgets('admin screen without a repository says review is unavailable',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityAdminScreen(
            localPosts: const [],
            onLocalChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't available"), findsOneWidget);
    });
  });
}
