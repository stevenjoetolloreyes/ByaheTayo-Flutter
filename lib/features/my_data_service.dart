// My Data — export + delete account (Account → Privacy → My Data).
//
// WHAT THIS IS: the real implementation behind the approved My Data
// preview (v1, Nov 11, 2026). The preview showed SAMPLE counts; this
// file reads the student's REAL data from the exact stores the app
// already uses — no invented numbers, no sample data anywhere:
//
//   Profile   — Firebase Auth (name/email) + the local ProfileStore
//               cache + the Firestore `student_profiles` document.
//   Schedule  — local StudentStorage subjects + assignments, plus
//               synced Google Calendar events (also local).
//   Study     — local StudentStorage files, notes, quizzes.
//   Money     — local StudentStorage allowance transactions (+ the
//               goals and budgets that belong to the same screen).
//   Rewards   — the Firestore points wallet + ledger (via the shared
//               PointsWalletController when the Account tab passes
//               it, else a direct ledger read) + local quiz points
//               and the local check-in log for the streak.
//   Community — Firestore `community_posts` authored by the user,
//               `community_comments` and `community_reactions` by
//               the user, plus the local-only community posts.
//
// EXPORT: there is no export backend in this project, so the export
// is assembled ON-DEVICE, synchronously, from the same snapshot:
// the selected groups become one JSON file that is handed to the
// platform share sheet (save / share), exactly like the allowance
// CSV export. The preview's "Your export is being prepared — we'll
// notify you when it's ready" line is therefore NOT used: the real
// screen says the export is ready the moment the share sheet opens.
//
// DELETE: the order is fixed — Firestore documents, then the Storage
// photo, then local data, then the Firebase Auth user LAST. The
// screen re-authenticates the user immediately before calling
// [deleteAccount] (password or Google, per sign-in method); this
// method refuses to run without that fresh re-authentication, so a
// stale session can never wipe data and then fail to delete the
// Auth user. Every step records its own outcome in
// [MyDataDeletionReport] — nothing is silently skipped.
//
// HONEST LIMITS (read before changing the plan):
// * The Firestore rules (firestore.rules, snapshot at this base)
//   make the points/credits ledgers APPEND-ONLY (update/delete
//   denied) and shared-post deletes ADMIN-ONLY, and friend-request
//   deletes are denied outright. Those documents CANNOT be erased
//   by the app; [deleteAccount] records them as kept, with the
//   reason, instead of pretending. Erasing them needs Steven in the
//   Firebase Console (Admin SDK) — or a rules change he approves.
// * The snapshot's firestore.rules ALSO has a pre-existing brace
//   bug: the `friend_requests` match is missing its closing `}`
//   (after `allow delete: if false;`), so the credits / scan /
//   ad-rewards / admin-settings matches are nested inside it and
//   never apply at the top level. This file does NOT fix that —
//   it is flagged for Steven. Until it is fixed, top-level
//   credits-wallet deletes are denied by the (lack of a) rule and
//   are reported as failed, not deleted.
// * Chat Support messages: the real app has no Chat Support
//   messages yet (Chat Support is preview-only, not built). The
//   delete list still names them because the approved preview does;
//   when Chat Support ships with real storage, its collection
//   belongs in [_remoteDeleteTargets] and in the Community group.
// * App ratings / review notifications are NOT deleted: they are
//   feedback about the app, not in the preview's delete list, and
//   the snapshot's rules have no match for them at all.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'community_post_repository.dart';
import 'community_posts.dart';
import 'credits_repository.dart';
import 'friend_cloud_repository.dart';
import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'points_wallet_repository.dart';
import 'profile_photo_storage.dart';
import 'profile_repository.dart';
import 'shared_study_files.dart';
import 'student/google_events.dart';
import 'student/student_data.dart';

/// The six data groups on the My Data screen (approved preview v1).
enum MyDataGroup {
  profile,
  schedule,
  study,
  money,
  rewards,
  community,
}

/// The word the delete-confirmation field must contain (case
/// insensitive, surrounding whitespace ignored). Shared by the
/// screen and the tests so the gate can never drift from the UI.
const myDataDeleteConfirmationWord = 'DELETE';

/// True when [input] unlocks the delete button.
bool isMyDataDeleteConfirmationValid(String input) =>
    input.trim().toUpperCase() == myDataDeleteConfirmationWord;

/// One group's real data: the count the screen shows, the detail
/// line under it, and the JSON payload the export writes.
class MyDataGroupData {
  const MyDataGroupData({
    required this.group,
    required this.countLabel,
    required this.detail,
    required this.json,
    this.note,
  });

  final MyDataGroup group;

  /// The count chip, e.g. "6 classes", "1,240 points", "3 fields".
  final String countLabel;

  /// The one-line description under the title (preview copy).
  final String detail;

  /// The group's payload inside the export JSON.
  final Map<String, dynamic> json;

  /// Set when part of the group could not be read (e.g. the server
  /// was unreachable): the counts then cover on-device data only.
  final String? note;
}

/// Everything the My Data screen shows, plus the JSON the export
/// writes. Built by [MyDataService.collect] from real data only.
class MyDataSnapshot {
  const MyDataSnapshot({
    required this.user,
    required this.groups,
  });

  final AuthUser user;

  /// One entry per group (all six are always present).
  final Map<MyDataGroup, MyDataGroupData> groups;

  /// The export file for [selected]: one JSON object with the app,
  /// the export time, who it is for, and the selected groups.
  Map<String, dynamic> toJson(Set<MyDataGroup> selected) {
    return {
      'app': 'EstudyanteGO',
      'exportedAt': DateTime.now().toIso8601String(),
      'exportedFor': {
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName,
      },
      'groups': {
        for (final group in MyDataGroup.values)
          if (selected.contains(group))
            group.name: groups[group]!.json,
      },
    };
  }
}

/// One Firestore document, as the My Data flows see it.
class MyDataRemoteDoc {
  const MyDataRemoteDoc(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}

/// The Firestore surface My Data needs, behind an interface so
/// tests use an in-memory fake and never touch a real project.
abstract class MyDataRemoteStore {
  /// The document at `collection/docId`, or null when it does not
  /// exist. Throws on Firestore errors.
  Future<Map<String, dynamic>?> fetchDoc(String collection, String docId);

  /// All documents in [collection] whose [field] equals [value].
  Future<List<MyDataRemoteDoc>> queryByField(
    String collection,
    String field,
    String value,
  );

  /// Deletes `collection/docId`. Throws on Firestore errors
  /// (e.g. permission-denied when the rules forbid the delete).
  Future<void> deleteDoc(String collection, String docId);
}

/// Firestore implementation of [MyDataRemoteStore].
class FirestoreMyDataRemoteStore implements MyDataRemoteStore {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Future<Map<String, dynamic>?> fetchDoc(
    String collection,
    String docId,
  ) async {
    final snap = await _db.collection(collection).doc(docId).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  @override
  Future<List<MyDataRemoteDoc>> queryByField(
    String collection,
    String field,
    String value,
  ) async {
    final snap =
        await _db.collection(collection).where(field, isEqualTo: value).get();
    return snap.docs
        .map((d) => MyDataRemoteDoc(d.id, d.data()))
        .toList();
  }

  @override
  Future<void> deleteDoc(String collection, String docId) async {
    await _db.collection(collection).doc(docId).delete();
  }
}

/// What happened to one deletion target.
enum MyDataDeletionOutcome {
  /// Deleted (or nothing existed to delete).
  deleted,

  /// Kept on purpose: the rules forbid the app from deleting it
  /// (append-only ledger, admin-only post delete, denied friend
  /// requests). Needs Steven in the Console, not the app.
  kept,

  /// The delete was attempted and failed (offline, permission
  /// denied, Storage error). The [MyDataDeletionItem.note] says why.
  failed,
}

/// One line of the deletion report.
class MyDataDeletionItem {
  const MyDataDeletionItem({
    required this.label,
    required this.outcome,
    this.note,
  });

  final String label;
  final MyDataDeletionOutcome outcome;

  /// Why it was kept or why it failed (null when deleted cleanly).
  final String? note;
}

/// The full result of [MyDataService.deleteAccount]: one item per
/// thing the flow touched, in the order it touched them.
class MyDataDeletionReport {
  const MyDataDeletionReport(this.items);

  final List<MyDataDeletionItem> items;

  /// True when every attempted step deleted (kept ledger items do
  /// not count as failures — they were never attempted).
  bool get allDeleted =>
      items.every((i) => i.outcome != MyDataDeletionOutcome.failed);

  /// Items that still exist after the flow (kept by rule + failed).
  List<MyDataDeletionItem> get remaining => items
      .where((i) => i.outcome != MyDataDeletionOutcome.deleted)
      .toList();
}

/// Collects the snapshot and deletes the account. Constructed with
/// the collaborators the screen already has; every collaborator is
/// optional and degrades honestly (no remote store → remote groups
/// read 0 and say the server was unreachable; no wallet controller
/// → the ledger is read directly; no photo storage → the photo
/// step reports "not attempted").
class MyDataService {
  MyDataService({
    this.remoteStore,
    this.photoStorage = const FirebaseProfilePhotoStorage(),
    this.profileStore,
  });

  /// Firestore access, or null when Firebase is not configured
  /// (local-only mode: remote groups are empty, honestly noted).
  final MyDataRemoteStore? remoteStore;

  /// Profile-photo Storage access (null = photo step skipped).
  final ProfilePhotoStorage? photoStorage;

  /// Local profile store (null = local profile keys are removed
  /// directly from SharedPreferences instead).
  final ProfileStore? profileStore;

  /// Reads the student's real data into a [MyDataSnapshot]. Never
  /// throws: a remote failure degrades that group to its on-device
  /// data with a [MyDataGroupData.note] saying so.
  Future<MyDataSnapshot> collect({
    required AuthUser user,
    UserProfile? localProfile,
    PointsWalletController? wallet,
  }) async {
    final remote = remoteStore;
    String? remoteError;

    // ---- Profile: Auth + local cache + remote document. --------
    StudentProfile? remoteProfile;
    if (remote != null) {
      try {
        final doc = await remote.fetchDoc(
          studentProfilesCollection,
          user.uid,
        );
        remoteProfile = StudentProfile.fromDoc(doc);
      } catch (_) {
        remoteError = 'Could not reach the server.';
      }
    }
    final name = (localProfile?.displayName.isNotEmpty ?? false)
        ? localProfile!.displayName
        : (user.displayName ?? user.email.split('@').first);
    final school = remoteProfile?.school ?? localProfile?.school;
    final profileFields = [
      name.trim().isNotEmpty,
      user.email.trim().isNotEmpty,
      (school ?? '').trim().isNotEmpty,
    ].where((present) => present).length;
    final profileData = MyDataGroupData(
      group: MyDataGroup.profile,
      countLabel: '$profileFields fields',
      detail: 'Name, email address, and school on your student profile.',
      json: {
        'name': name,
        'email': user.email,
        'emailVerified': user.emailVerified,
        'school': school,
        'program': remoteProfile?.program ?? localProfile?.program,
        'yearLevel': remoteProfile?.yearLevel ?? localProfile?.year,
        'plan': (remoteProfile?.plan ?? localProfile?.plan)?.name,
        'profilePhotoUrl':
            remoteProfile?.profilePhotoUrl ?? localProfile?.profilePhotoUrl,
      },
      note: remote == null
          ? 'Server data is not available on this device.'
          : remoteError,
    );

    // ---- Schedule: local subjects + assignments + Google events. -
    final subjects = await StudentStorage.loadList(StudentStorage.subjectsKey);
    final assignments =
        await StudentStorage.loadList(StudentStorage.assignmentsKey);
    final googleEvents = await loadGoogleEvents();
    final scheduleData = MyDataGroupData(
      group: MyDataGroup.schedule,
      countLabel: '${subjects.length} classes',
      detail: googleEvents.isEmpty
          ? 'Your saved classes — subject, day, time, and room for each one.'
          : 'Your saved classes — subject, day, time, and room for each '
              'one. Plus ${googleEvents.length} synced calendar events.',
      json: {
        'classes': subjects,
        'assignments': assignments,
        'googleEvents': googleEvents.map((e) => e.toJson()).toList(),
      },
    );

    // ---- Study: local files, notes, quizzes. --------------------
    final files = await StudentStorage.loadList(StudentStorage.studyFilesKey);
    final notes = await StudentStorage.loadList(StudentStorage.notesKey);
    final quizzes = await StudentStorage.loadList(StudentStorage.quizzesKey);
    final studyData = MyDataGroupData(
      group: MyDataGroup.study,
      countLabel: '${files.length + notes.length + quizzes.length} items',
      detail: '${files.length} files · ${notes.length} notes · '
          '${quizzes.length} quizzes you made or saved in Study.',
      json: {
        'files': files,
        'notes': notes,
        'quizzes': quizzes,
      },
    );

    // ---- Money: local allowance transactions (+ goals/budgets). ---
    final txns = await StudentStorage.loadList(StudentStorage.txnsKey);
    final goals = await StudentStorage.loadList(StudentStorage.goalsKey);
    final budgets = await StudentStorage.loadList(StudentStorage.budgetsKey);
    final moneyData = MyDataGroupData(
      group: MyDataGroup.money,
      countLabel: '${txns.length} transactions',
      detail:
          'Your allowance history — money in, money out, and what it was for.',
      json: {
        'transactions': txns,
        'goals': goals,
        'budgets': budgets,
      },
    );

    // ---- Rewards: points balance + streak + ledger. -------------
    final rewardsData = await _collectRewards(user, wallet, remote);

    // ---- Community: own shared posts + comments + reactions,
    //      plus local-only posts. ----------------------------------
    final communityData = await _collectCommunity(user, remote);

    return MyDataSnapshot(user: user, groups: {
      MyDataGroup.profile: profileData,
      MyDataGroup.schedule: scheduleData,
      MyDataGroup.study: studyData,
      MyDataGroup.money: moneyData,
      MyDataGroup.rewards: rewardsData,
      MyDataGroup.community: communityData,
    });
  }

  Future<MyDataGroupData> _collectRewards(
    AuthUser user,
    PointsWalletController? wallet,
    MyDataRemoteStore? remote,
  ) async {
    final quizPoints = await StudentStorage.loadInt(StudentStorage.quizPointsKey);
    final localCheckins =
        await StudentStorage.loadList(StudentStorage.checkinsKey);
    final localRecords = localCheckins.map((j) {
      try {
        return CheckinRecord.fromJson(j);
      } catch (_) {
        return null;
      }
    }).whereType<CheckinRecord>().toList();

    int balance;
    int totalEarned;
    List<CheckinRecord> streakRecords;
    List<Map<String, dynamic>> ledgerJson;
    String? note;
    if (wallet != null && wallet.remote) {
      balance = wallet.balance + quizPoints;
      totalEarned = wallet.totalEarned + quizPoints;
      streakRecords = wallet.derivedRecords;
      ledgerJson = wallet.entries.map(_pointsTransactionJson).toList();
    } else if (remote != null) {
      try {
        final ledger = await remote.queryByField(
          pointsTransactionsCollection,
          'userId',
          user.uid,
        );
        var sum = 0;
        for (final doc in ledger) {
          final points = doc.data['points'];
          if (points is int) sum += points;
        }
        balance = sum + quizPoints;
        totalEarned = sum + quizPoints;
        streakRecords = localRecords;
        ledgerJson = ledger.map((d) => {'id': d.id, ...d.data}).toList();
      } catch (_) {
        balance = quizPoints;
        totalEarned = quizPoints;
        streakRecords = localRecords;
        ledgerJson = [];
        note = 'Could not reach the server — showing on-device points only.';
      }
    } else {
      balance = quizPoints;
      totalEarned = quizPoints;
      streakRecords = localRecords;
      ledgerJson = [];
      note = 'Server data is not available on this device.';
    }
    final streak = checkinStreak(streakRecords, manilaDateTime(DateTime.now()));
    return MyDataGroupData(
      group: MyDataGroup.rewards,
      countLabel: '$balance points',
      detail: 'Your points balance and your $streak-day sign-in streak record.',
      json: {
        'pointsBalance': balance,
        'totalEarned': totalEarned,
        'streakDays': streak,
        'quizPoints': quizPoints,
        'transactions': ledgerJson,
      },
      note: note,
    );
  }

  Future<MyDataGroupData> _collectCommunity(
    AuthUser user,
    MyDataRemoteStore? remote,
  ) async {
    var sharedPosts = <MyDataRemoteDoc>[];
    var comments = <MyDataRemoteDoc>[];
    var reactions = <MyDataRemoteDoc>[];
    String? note;
    if (remote != null) {
      try {
        sharedPosts = await remote.queryByField(
          communityPostsCollection,
          'authorUid',
          user.uid,
        );
        comments = await remote.queryByField(
          'community_comments',
          'userId',
          user.uid,
        );
        reactions = await remote.queryByField(
          'community_reactions',
          'userId',
          user.uid,
        );
      } catch (_) {
        note = 'Could not reach the server — showing on-device posts only.';
      }
    } else {
      note = 'Server data is not available on this device.';
    }
    // Local-only posts live in SharedPreferences ON THIS DEVICE ONLY
    // (see community_posts.dart): they are the user's own posts by
    // construction — authorUid is not persisted locally at all — so
    // every parseable entry counts. Same validity filter as
    // [loadCommunityPosts].
    final localPosts =
        await StudentStorage.loadList(communityPostsKey);
    final myLocalPosts = localPosts.where((j) {
      try {
        final post = CommunityPost.fromJson(j);
        return post.routeName.trim().isNotEmpty ||
            (post.from.trim().isNotEmpty && post.to.trim().isNotEmpty);
      } catch (_) {
        return false;
      }
    }).toList();
    final postCount = sharedPosts.length + myLocalPosts.length;
    return MyDataGroupData(
      group: MyDataGroup.community,
      countLabel: '${postCount + comments.length} items',
      detail: '$postCount posts and ${comments.length} comments you shared '
          'in Communities.',
      json: {
        'posts': [
          for (final d in sharedPosts) {'id': d.id, ...d.data},
          ...myLocalPosts,
        ],
        'comments': [
          for (final d in comments) {'id': d.id, ...d.data},
        ],
        'reactions': [
          for (final d in reactions) {'id': d.id, ...d.data},
        ],
      },
      note: note,
    );
  }

  static Map<String, dynamic> _pointsTransactionJson(PointsTransaction e) {
    return {
      'id': e.id,
      'userId': e.userId,
      'type': e.type,
      'points': e.points,
      'description': e.description,
      'source': e.source,
      'referenceId': e.referenceId,
      'date': e.date,
      'dayIndex': e.dayIndex,
      'status': e.status,
    };
  }

  /// Deletes the account for real, in the fixed order: Firestore
  /// documents, then the Storage photo, then local data, then the
  /// Firebase Auth user LAST.
  ///
  /// [reauthenticated] MUST be true — the screen re-authenticates
  /// the user (password or Google) immediately before calling this.
  /// A false value throws [StateError] and deletes nothing: a stale
  /// session must never wipe data and then fail the Auth delete.
  ///
  /// NEVER call this in a test against a real account: tests pass a
  /// fake [remoteStore], a fake [photoStorage] and a fake [auth].
  Future<MyDataDeletionReport> deleteAccount({
    required AuthUser user,
    required AuthService auth,
    required bool reauthenticated,
    Future<Directory> Function()? documentsDir,
  }) async {
    if (!reauthenticated) {
      throw StateError(
        'My Data delete called without a fresh re-authentication.',
      );
    }
    final items = <MyDataDeletionItem>[];
    final remote = remoteStore;

    // 1. Firestore documents. -------------------------------
    if (remote != null) {
      items.addAll(await _deleteRemoteDocs(user, remote));
    } else {
      items.add(const MyDataDeletionItem(
        label: 'Server data (profile, wallet, posts, comments)',
        outcome: MyDataDeletionOutcome.failed,
        note: 'Server data is not available on this device — nothing '
            'was deleted from the server.',
      ));
    }

    // 2. Storage profile photo. ------------------------------
    final storage = photoStorage;
    if (storage != null) {
      try {
        final deleted = await storage.deletePhoto(user.uid);
        items.add(MyDataDeletionItem(
          label: 'Profile photo',
          outcome: MyDataDeletionOutcome.deleted,
          note: deleted ? null : 'No photo was stored.',
        ));
      } catch (e) {
        items.add(MyDataDeletionItem(
          label: 'Profile photo',
          outcome: MyDataDeletionOutcome.failed,
          note: _shortError(e),
        ));
      }
    }

    // 3. Local data. ------------------------------------------
    items.add(await _deleteLocalData(user, documentsDir));

    // 4. The Firebase Auth user, LAST. ------------------------
    try {
      await auth.deleteCurrentUser();
      items.add(const MyDataDeletionItem(
        label: 'Sign-in account',
        outcome: MyDataDeletionOutcome.deleted,
      ));
    } catch (e) {
      items.add(MyDataDeletionItem(
        label: 'Sign-in account',
        outcome: MyDataDeletionOutcome.failed,
        note: e is AuthException ? e.message : _shortError(e),
      ));
    }
    return MyDataDeletionReport(items);
  }

  /// Step 1 of [deleteAccount]: every Firestore document the app
  /// may delete, attempted one by one. Documents the rules forbid
  /// the app from deleting are NOT attempted — they are reported as
  /// kept with the reason (see the file header).
  Future<List<MyDataDeletionItem>> _deleteRemoteDocs(
    AuthUser user,
    MyDataRemoteStore remote,
  ) async {
    final items = <MyDataDeletionItem>[];
    final uid = user.uid;

    Future<void> deleteOne(String collection, String docId, String label) async {
      try {
        await remote.deleteDoc(collection, docId);
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.deleted,
        ));
      } catch (e) {
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.failed,
          note: _shortError(e),
        ));
      }
    }

    Future<void> deleteQuery(
      String collection,
      String field,
      String label, {
      String? keptWhenDeniedNote,
    }) async {
      List<MyDataRemoteDoc> docs;
      try {
        docs = await remote.queryByField(collection, field, uid);
      } catch (e) {
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.failed,
          note: 'Could not list them: ${_shortError(e)}',
        ));
        return;
      }
      if (docs.isEmpty) {
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.deleted,
          note: 'Nothing stored.',
        ));
        return;
      }
      var failures = 0;
      var deniedFailures = 0;
      String? lastError;
      for (final doc in docs) {
        try {
          await remote.deleteDoc(collection, doc.id);
        } catch (e) {
          failures++;
          if (e is FirebaseException && e.code == 'permission-denied') {
            deniedFailures++;
          }
          lastError = _shortError(e);
        }
      }
      if (failures == 0) {
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.deleted,
          note: '${docs.length} deleted.',
        ));
      } else if (keptWhenDeniedNote != null &&
          deniedFailures == docs.length) {
        // Every delete was refused by the rules (not a network
        // failure): the documents stay, by rule, and the report says
        // so instead of painting the whole deletion as failed.
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.kept,
          note: keptWhenDeniedNote,
        ));
      } else {
        items.add(MyDataDeletionItem(
          label: label,
          outcome: MyDataDeletionOutcome.failed,
          note: '$failures of ${docs.length} could not be deleted'
              '${lastError == null ? '.' : ': $lastError'}',
        ));
      }
    }

    // Owner-deletable single documents.
    await deleteOne(
      studentProfilesCollection,
      uid,
      'Profile (school, program, year)',
    );
    await deleteOne(
      pointsWalletsCollection,
      uid,
      'Points wallet',
    );
    await deleteOne(
      creditsWalletsCollection,
      uid,
      'Credits wallet',
    );
    await deleteOne(
      userFriendCodesCollection,
      uid,
      'Friend code',
    );

    // Own documents found by query.
    await deleteQuery(
      communityPostsCollection,
      'authorUid',
      'Community posts',
      keptWhenDeniedNote: 'Shared posts can only be deleted by an admin '
          'under the current Firestore rules. Steven can remove them in '
          'the Firebase Console.',
    );
    await deleteQuery(
      'community_comments',
      'userId',
      'Community comments',
    );
    await deleteQuery(
      'community_reactions',
      'userId',
      'Community reactions',
    );
    await deleteQuery(
      sharedStudyFilesCollection,
      'fromUid',
      'Files you shared',
    );
    await deleteQuery(
      sharedStudyFilesCollection,
      'toUid',
      'Files shared with you',
    );
    await deleteQuery(
      friendCodesCollection,
      'uid',
      'Friend-code lookup',
    );

    // Kept by rule — never attempted (see the file header).
    items.add(const MyDataDeletionItem(
      label: 'Points history (ledger)',
      outcome: MyDataDeletionOutcome.kept,
      note: 'The points ledger is append-only — the app cannot erase '
          'it. Steven can remove it in the Firebase Console.',
    ));
    items.add(const MyDataDeletionItem(
      label: 'Credits history (ledger)',
      outcome: MyDataDeletionOutcome.kept,
      note: 'The credits ledger is append-only — the app cannot erase '
          'it. Steven can remove it in the Firebase Console.',
    ));
    items.add(const MyDataDeletionItem(
      label: 'Friend requests',
      outcome: MyDataDeletionOutcome.kept,
      note: 'The rules forbid deleting friend requests. Steven can '
          'remove them in the Firebase Console.',
    ));
    return items;
  }

  /// Step 3 of [deleteAccount]: every local trace of the student.
  /// App settings (theme, sidebar, notification prefs) are NOT
  /// touched — only the student's own data.
  Future<MyDataDeletionItem> _deleteLocalData(
    AuthUser user,
    Future<Directory> Function()? documentsDir,
  ) async {
    const localKeys = [
      StudentStorage.subjectsKey,
      StudentStorage.assignmentsKey,
      StudentStorage.notesKey,
      StudentStorage.flashcardsKey,
      StudentStorage.quizzesKey,
      StudentStorage.attemptsKey,
      StudentStorage.gradesKey,
      StudentStorage.studyFilesKey,
      StudentStorage.txnsKey,
      StudentStorage.goalsKey,
      StudentStorage.budgetsKey,
      StudentStorage.attendanceKey,
      StudentStorage.attendanceGoalKey,
      StudentStorage.checkinsKey,
      StudentStorage.quizPointsKey,
      StudentStorage.quoteFavsKey,
      StudentStorage.quoteCollectionsKey,
      StudentStorage.quoteHistoryKey,
      StudentStorage.bibleFavsKey,
      StudentStorage.bibleJournalKey,
      StudentStorage.biblePlanKey,
      StudentStorage.commuteFavsKey,
      StudentStorage.commuteExpensesKey,
      communityPostsKey,
      samplePostSeededKey,
      googleEventsKey,
      googleCalendarRealSyncKey,
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in localKeys) {
        await prefs.remove(key);
      }
      final store = profileStore;
      if (store != null) {
        await store.clearProfile(user.uid);
      } else {
        await prefs.remove(profileDataKey(user.uid));
        await prefs.remove(profileSetupDoneKey(user.uid));
        await prefs.remove(profileSchoolKey);
      }
      // The local copy of the profile photo file. Synchronous file
      // calls on purpose: async file IO can stall a widget test's
      // fake-async pump loop (see profile_photo_storage_test.dart),
      // and this is best-effort cleanup inside a try/catch anyway.
      try {
        final docs = await (documentsDir?.call() ??
            getApplicationDocumentsDirectory());
        final photo = File(localProfilePhotoPath(docs.path, user.uid));
        if (photo.existsSync()) photo.deleteSync();
      } catch (_) {
        // A stuck local photo file never fails the deletion.
      }
      return const MyDataDeletionItem(
        label: 'On-device data (schedule, study, allowance, streak)',
        outcome: MyDataDeletionOutcome.deleted,
      );
    } catch (e) {
      return MyDataDeletionItem(
        label: 'On-device data (schedule, study, allowance, streak)',
        outcome: MyDataDeletionOutcome.failed,
        note: _shortError(e),
      );
    }
  }

  static String _shortError(Object e) {
    if (e is FirebaseException) {
      final message = e.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
      return 'Firestore error (${e.code}).';
    }
    final text = e.toString();
    return text.length > 160 ? '${text.substring(0, 157)}…' : text;
  }
}

/// Writes [json] to a temp file and opens the platform share sheet
/// (save / share), the same pattern as the allowance CSV export.
/// Returns the file so callers/tests can inspect it. The filename
/// carries the group (or 'all') and the Manila date.
///
/// The write is synchronous on purpose: async file IO can stall a
/// widget test's fake-async pump loop (see
/// profile_photo_storage_test.dart), and this is one small JSON file.
Future<File> shareMyDataJson(
  Map<String, dynamic> json, {
  required String name,
}) async {
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final file = File('${Directory.systemTemp.path}/estudyantego-my-data-$name-$stamp.json');
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(json),
  );
  return file;
}
