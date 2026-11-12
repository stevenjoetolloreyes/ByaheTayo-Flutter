// Tests for My Data — export + delete account.
//
// Never touches a real account: the remote store, the photo storage
// and auth are all in-memory fakes. The deletion tests prove the
// order (Firestore → Storage photo → local data → Auth user), that
// append-only ledgers are KEPT (never deleted), and that a delete
// without a fresh re-authentication deletes nothing.
import 'dart:convert';
import 'dart:io';

import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/my_data_screen.dart';
import 'package:estudyantego/features/my_data_service.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/profile_photo_storage.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _user = AuthUser(
  uid: 'uid-1',
  email: 'steven@example.com',
  displayName: 'Steven Reyes',
  emailVerified: true,
);

/// In-memory [MyDataRemoteStore]: collections of documents.
/// [denyDelete] holds "collection/docId" entries whose delete throws
/// permission-denied, simulating the Firestore rules (shared posts
/// are admin-only).
class InMemoryMyDataRemoteStore implements MyDataRemoteStore {
  final Map<String, Map<String, Map<String, dynamic>>> docs = {};
  final Set<String> denyDelete = {};

  /// "collection/docId" of every attempted delete, in order.
  final List<String> deleteAttempts = [];

  void put(String collection, String docId, Map<String, dynamic> data) {
    docs.putIfAbsent(collection, () => {})[docId] = data;
  }

  bool has(String collection, String docId) =>
      docs[collection]?.containsKey(docId) ?? false;

  @override
  Future<Map<String, dynamic>?> fetchDoc(
    String collection,
    String docId,
  ) async =>
      docs[collection]?[docId];

  @override
  Future<List<MyDataRemoteDoc>> queryByField(
    String collection,
    String field,
    String value,
  ) async {
    final all = docs[collection] ?? {};
    return all.entries
        .where((e) => e.value[field] == value)
        .map((e) => MyDataRemoteDoc(e.key, e.value))
        .toList();
  }

  @override
  Future<void> deleteDoc(String collection, String docId) async {
    deleteAttempts.add('$collection/$docId');
    if (denyDelete.contains('$collection/$docId')) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
    }
    docs[collection]?.remove(docId);
  }
}

/// In-memory [ProfilePhotoStorage].
class FakePhotoStorage implements ProfilePhotoStorage {
  bool photoExists = true;
  final List<String> deletedUids = [];

  @override
  Future<String> uploadPhoto(String uid, File file) async =>
      'https://example.com/$uid.jpg';

  @override
  Future<String?> cacheRemotePhoto(
    String uid,
    String url, {
    Future<Directory> Function()? documentsDir,
  }) async =>
      null;

  @override
  Future<bool> deletePhoto(String uid) async {
    deletedUids.add(uid);
    final existed = photoExists;
    photoExists = false;
    return existed;
  }
}

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _seedLocalData() async {
  final now = DateTime.now();
  SharedPreferences.setMockInitialValues({
    StudentStorage.subjectsKey: jsonEncode([
      {
        'id': 'subj-1',
        'name': 'CT101',
        'code': 'CT101',
        'days': ['Mon'],
        'startTime': '07:30',
        'endTime': '09:30',
        'room': 'CC105',
      },
      {
        'id': 'subj-2',
        'name': 'CT102',
        'code': 'CT102',
        'days': ['Mon'],
        'startTime': '10:00',
        'endTime': '12:00',
        'room': 'CC105',
      },
    ]),
    StudentStorage.assignmentsKey: jsonEncode([
      {'id': 'a-1', 'title': 'Lab 1', 'due': '2026-11-20'},
    ]),
    StudentStorage.studyFilesKey: jsonEncode([
      {'id': 'f-1', 'name': 'notes.pdf'},
      {'id': 'f-2', 'name': 'slides.pdf'},
    ]),
    StudentStorage.notesKey: jsonEncode([
      {'id': 'n-1', 'title': 'Chapter 1'},
      {'id': 'n-2', 'title': 'Chapter 2'},
    ]),
    StudentStorage.quizzesKey: jsonEncode([
      {'id': 'q-1', 'title': 'Quiz 1'},
    ]),
    StudentStorage.txnsKey: jsonEncode([
      {'id': 't-1', 'amount': 100.0},
      {'id': 't-2', 'amount': -60.0},
      {'id': 't-3', 'amount': 50.0},
    ]),
    StudentStorage.checkinsKey: jsonEncode([
      {
        'id': 'c-today',
        'date': _dateKey(now),
        'dayIndex': 2,
        'points': 10,
      },
      {
        'id': 'c-yesterday',
        'date': _dateKey(now.subtract(const Duration(days: 1))),
        'dayIndex': 1,
        'points': 10,
      },
    ]),
    StudentStorage.quizPointsKey: 30,
    communityPostsKey: jsonEncode([
      {
        'routeName': 'Cabugao - Vigan',
        'vehicles': ['Modern Jeepney'],
        'hours': '6:00 AM - 6:00 PM',
        'fare': 60.0,
        'hubName': 'Vigan Bus Terminal',
      },
    ]),
  });
}

InMemoryMyDataRemoteStore _seedRemote() {
  final store = InMemoryMyDataRemoteStore();
  store.put('student_profiles', 'uid-1', {
    'school': 'University of Northern Philippines',
    'program': 'Diploma in Computer Technology',
    'yearLevel': '1st Year',
    'profilePhotoUrl': 'https://example.com/uid-1.jpg',
    'plan': 'free',
  });
  store.put('points_wallets', 'uid-1', {
    'account_points_balance': 60,
    'totalEarned': 60,
  });
  store.put('credits_wallets', 'uid-1', {'balance': 5});
  store.put('points_transactions', 'txn-signin-1', {
    'userId': 'uid-1',
    'type': 'signin',
    'points': 10,
    'description': '7-Day Sign-in — Day 1',
    'source': 'signin',
    'referenceId': 'txn-signin-1',
    'date': '2026-11-11',
    'dayIndex': 1,
    'status': 'completed',
  });
  store.put('points_transactions', 'txn-signin-2', {
    'userId': 'uid-1',
    'type': 'signin',
    'points': 50,
    'description': '7-Day Sign-in — Day 7',
    'source': 'signin',
    'referenceId': 'txn-signin-2',
    'date': '2026-11-12',
    'dayIndex': 7,
    'status': 'completed',
  });
  store.put('community_posts', 'post-1', {
    'authorUid': 'uid-1',
    'status': 'approved',
    'routeName': 'Cabugao - Vigan',
  });
  store.put('community_comments', 'comment-1', {
    'userId': 'uid-1',
    'postId': 'post-9',
    'text': 'Sakay na!',
  });
  store.put('community_comments', 'comment-2', {
    'userId': 'uid-1',
    'postId': 'post-9',
    'text': 'Ingat!',
  });
  store.put('community_reactions', 'post-9_uid-1', {
    'userId': 'uid-1',
    'postId': 'post-9',
    'value': 'like',
  });
  store.put('shared_study_files', 'share-1', {
    'fromUid': 'uid-1',
    'toUid': 'uid-2',
    'name': 'notes.pdf',
  });
  store.put('user_friend_codes', 'uid-1', {'code': 'ABC123'});
  store.put('friend_codes', 'ABC123', {'uid': 'uid-1', 'code': 'ABC123'});
  // Another user's data: must never be touched.
  store.put('student_profiles', 'uid-2', {'school': 'Other School'});
  store.put('community_posts', 'post-2', {
    'authorUid': 'uid-2',
    'status': 'approved',
    'routeName': 'Other route',
  });
  return store;
}

Future<MyDataService> _service({
  required InMemoryMyDataRemoteStore remote,
  FakePhotoStorage? photos,
}) async {
  final prefs = await SharedPreferences.getInstance();
  return MyDataService(
    remoteStore: remote,
    photoStorage: photos ?? FakePhotoStorage(),
    profileStore: ProfileStore(prefs),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('delete confirmation gate', () {
    test('only the word DELETE unlocks it', () {
      expect(isMyDataDeleteConfirmationValid('DELETE'), isTrue);
      expect(isMyDataDeleteConfirmationValid('delete'), isTrue);
      expect(isMyDataDeleteConfirmationValid('  Delete  '), isTrue);
      expect(isMyDataDeleteConfirmationValid('DELET'), isFalse);
      expect(isMyDataDeleteConfirmationValid(''), isFalse);
      expect(isMyDataDeleteConfirmationValid('DELETE '), isTrue);
    });
  });

  group('collect — real counts', () {
    test('counts come from the real local + remote data', () async {
      await _seedLocalData();
      final remote = _seedRemote();
      final service = await _service(remote: remote);
      final snapshot = await service.collect(user: _user);

      expect(snapshot.groups[MyDataGroup.profile]!.countLabel, '3 fields');
      expect(snapshot.groups[MyDataGroup.schedule]!.countLabel, '2 classes');
      expect(snapshot.groups[MyDataGroup.study]!.countLabel, '5 items');
      expect(
        snapshot.groups[MyDataGroup.study]!.detail,
        '2 files · 2 notes · 1 quizzes you made or saved in Study.',
      );
      expect(
        snapshot.groups[MyDataGroup.money]!.countLabel,
        '3 transactions',
      );
      // Rewards: ledger 10 + 50, plus 30 local quiz points.
      expect(snapshot.groups[MyDataGroup.rewards]!.countLabel, '90 points');
      expect(
        snapshot.groups[MyDataGroup.rewards]!.json['streakDays'],
        2,
      );
      // Community: 1 shared post + 1 local post + 2 comments.
      expect(
        snapshot.groups[MyDataGroup.community]!.countLabel,
        '4 items',
      );
      expect(
        snapshot.groups[MyDataGroup.community]!.detail,
        '2 posts and 2 comments you shared in Communities.',
      );
      // Another user's documents are never in the snapshot.
      final posts =
          snapshot.groups[MyDataGroup.community]!.json['posts'] as List;
      expect(
        posts.any((p) => (p as Map)['routeName'] == 'Other route'),
        isFalse,
      );
    });

    test('export JSON holds only the selected groups', () async {
      await _seedLocalData();
      final remote = _seedRemote();
      final service = await _service(remote: remote);
      final snapshot = await service.collect(user: _user);

      final json = snapshot.toJson({MyDataGroup.money, MyDataGroup.study});
      expect(json['app'], 'EstudyanteGO');
      expect(json['exportedFor']['email'], 'steven@example.com');
      final groups = json['groups'] as Map;
      expect(groups.keys.toSet(), {'money', 'study'});
      expect((groups['money']['transactions'] as List).length, 3);
      expect((groups['study']['files'] as List).length, 2);
    });

    test('shareMyDataJson writes valid JSON', () async {
      await _seedLocalData();
      final remote = _seedRemote();
      final service = await _service(remote: remote);
      final snapshot = await service.collect(user: _user);
      final file = await shareMyDataJson(
        snapshot.toJson({MyDataGroup.profile}),
        name: 'profile',
      );
      expect(await file.exists(), isTrue);
      final decoded = jsonDecode(await file.readAsString());
      expect(decoded['groups']['profile']['school'],
          'University of Northern Philippines');
      await file.delete();
    });
  });

  group('deleteAccount', () {
    test('refuses to run without a fresh re-authentication', () async {
      await _seedLocalData();
      final remote = _seedRemote();
      final photos = FakePhotoStorage();
      final service = await _service(remote: remote, photos: photos);
      final auth = FakeAuthService(user: _user);

      expect(
        () => service.deleteAccount(
          user: _user,
          auth: auth,
          reauthenticated: false,
        ),
        throwsStateError,
      );
      // Nothing was touched.
      expect(remote.has('student_profiles', 'uid-1'), isTrue);
      expect(photos.deletedUids, isEmpty);
      expect(auth.userDeleted, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StudentStorage.subjectsKey), isNotNull);
    });

    test('deletes in order and keeps the append-only ledgers', () async {
      await _seedLocalData();
      final remote = _seedRemote();
      // Shared posts are admin-only under the current rules.
      remote.denyDelete.add('community_posts/post-1');
      final photos = FakePhotoStorage();
      final service = await _service(remote: remote, photos: photos);
      final auth = FakeAuthService(user: _user);
      auth.reauthenticated = true;

      final report = await service.deleteAccount(
        user: _user,
        auth: auth,
        reauthenticated: true,
      );

      // Firestore: own docs gone, the other user's docs untouched.
      expect(remote.has('student_profiles', 'uid-1'), isFalse);
      expect(remote.has('student_profiles', 'uid-2'), isTrue);
      expect(remote.has('points_wallets', 'uid-1'), isFalse);
      expect(remote.has('credits_wallets', 'uid-1'), isFalse);
      expect(remote.has('user_friend_codes', 'uid-1'), isFalse);
      expect(remote.has('friend_codes', 'ABC123'), isFalse);
      expect(remote.has('community_comments', 'comment-1'), isFalse);
      expect(remote.has('community_comments', 'comment-2'), isFalse);
      expect(remote.has('community_reactions', 'post-9_uid-1'), isFalse);
      expect(remote.has('shared_study_files', 'share-1'), isFalse);
      expect(remote.has('community_posts', 'post-2'), isTrue);
      // The ledger is append-only: still there, reported as kept.
      expect(remote.has('points_transactions', 'txn-signin-1'), isTrue);
      expect(remote.has('points_transactions', 'txn-signin-2'), isTrue);
      final ledger = report.items.firstWhere(
        (i) => i.label == 'Points history (ledger)',
      );
      expect(ledger.outcome, MyDataDeletionOutcome.kept);
      // The admin-only post is kept, not failed.
      final posts = report.items.firstWhere(
        (i) => i.label == 'Community posts',
      );
      expect(posts.outcome, MyDataDeletionOutcome.kept);
      expect(remote.has('community_posts', 'post-1'), isTrue);

      // Storage photo deleted, local data wiped, Auth user last.
      expect(photos.deletedUids, ['uid-1']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StudentStorage.subjectsKey), isNull);
      expect(prefs.getString(StudentStorage.txnsKey), isNull);
      expect(prefs.getString(StudentStorage.quizzesKey), isNull);
      expect(prefs.getString(communityPostsKey), isNull);
      expect(auth.userDeleted, isTrue);
      expect(report.allDeleted, isTrue);

      // Order: Firestore deletes came before the Auth delete (the
      // report lists steps in run order; the sign-in account is last).
      expect(report.items.last.label, 'Sign-in account');
    });
  });

  group('MyDataScreen widget', () {
    late FakeAuthService auth;
    late InMemoryMyDataRemoteStore remote;
    late MyDataService service;
    late List<File> sharedFiles;
    var accountDeleted = false;

    Future<void> pumpScreen(WidgetTester tester) async {
      await _seedLocalData();
      remote = _seedRemote();
      service = await _service(remote: remote);
      auth = FakeAuthService(user: _user);
      auth.reauthPasswordOverride = 'secret123';
      sharedFiles = [];
      accountDeleted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MyDataScreen(
            user: _user,
            authService: auth,
            service: service,
            shareFile: (file) async => sharedFiles.add(file),
            documentsDir: () async => Directory.systemTemp,
            onBack: () {},
            onAccountDeleted: () => accountDeleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('overview shows real counts', (tester) async {
      await pumpScreen(tester);
      expect(find.text('What we hold about you'), findsOneWidget);
      expect(find.text('2 classes'), findsOneWidget);
      expect(find.text('5 items'), findsOneWidget);
      expect(find.text('3 transactions'), findsOneWidget);
      expect(find.text('90 points'), findsOneWidget);
      expect(find.text('4 items'), findsOneWidget);
      expect(find.byKey(const Key('my-data-download-schedule')),
          findsOneWidget);
    });

    testWidgets('export shares the selected groups as JSON',
        (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('my-data-download-all')));
      await tester.tap(find.byKey(const Key('my-data-download-all')));
      await tester.pumpAndSettle();
      expect(find.text('Download my data'), findsOneWidget);

      // Uncheck Study: it must not be in the export.
      await tester.ensureVisible(find.byKey(const Key('my-data-export-study')));
      await tester.tap(find.byKey(const Key('my-data-export-study')));
      await tester.pump();
      await tester.ensureVisible(
          find.byKey(const Key('my-data-request-export')));
      // The export write is synchronous (see shareMyDataJson) and the
      // share callback is a fake, so no runAsync is needed: tap and
      // settle in the normal fake-async zone. (runAsync +
      // pumpAndSettle hangs here — while _exporting is true the
      // spinner keeps scheduling frames and pumpAndSettle inside
      // runAsync never settles: 10-minute test timeout, twice.)
      await tester.tap(find.byKey(const Key('my-data-request-export')));
      await tester.pumpAndSettle();

      expect(sharedFiles, hasLength(1));
      // Sync read on purpose: async file IO never completes in the
      // fake-async zone (same reason shareMyDataJson writes sync).
      final decoded =
          jsonDecode(sharedFiles.single.readAsStringSync());
      final groups = decoded['groups'] as Map;
      expect(groups.containsKey('study'), isFalse);
      expect(groups.containsKey('money'), isTrue);
      expect(find.text('Your export is ready'), findsOneWidget);
    });

    testWidgets('delete flow: DELETE → confirm → password → report',
        (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('my-data-go-delete')));
      await tester.tap(find.byKey(const Key('my-data-go-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete my account'), findsWidgets);

      // The delete button stays disabled until DELETE is typed.
      final deleteButton = find.byKey(const Key('my-data-delete-button'));
      expect(tester.widget<ElevatedButton>(deleteButton).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('my-data-delete-input')),
        'delete',
      );
      await tester.pump();
      expect(tester.widget<ElevatedButton>(deleteButton).onPressed,
          isNotNull);

      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const Key('my-data-confirm-delete')));
      await tester.tap(find.byKey(const Key('my-data-confirm-delete')));
      await tester.pumpAndSettle();

      // Password re-auth, then the deletion runs.
      expect(find.byKey(const Key('my-data-reauth-password')),
          findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('my-data-reauth-password')),
        'secret123',
      );
      await tester.ensureVisible(
          find.byKey(const Key('my-data-reauth-confirm')));
      // No runAsync: the deletion path uses only in-memory fakes,
      // mocked SharedPreferences and synchronous file calls, and the
      // photo path comes from the injected documentsDir (system temp),
      // so nothing here needs the real event loop. (The runAsync +
      // pumpAndSettle form took ~4 minutes and shares the export
      // test's hang risk — see above.)
      await tester.tap(find.byKey(const Key('my-data-reauth-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Your account has been deleted'), findsOneWidget);
      expect(auth.userDeleted, isTrue);
      await tester.ensureVisible(
          find.byKey(const Key('my-data-deletion-done')));
      await tester.tap(find.byKey(const Key('my-data-deletion-done')));
      await tester.pump();
      expect(accountDeleted, isTrue);
    });
  });
}
