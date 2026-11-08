// Tests for user-to-user shared study files (Nov 8, 2026):
// a share is a metadata snapshot addressed to ONE friend UID —
// never a public link, never file bytes. The sender is always the
// author; sharing the same file to the same friend twice is one
// share, never a duplicate.
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/shared_study_files.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sender = AuthUser(uid: 'u-sender', email: 'sender@example.com');
const _friend = AuthUser(uid: 'u-friend', email: 'friend@example.com');
const _stranger = AuthUser(uid: 'u-stranger', email: 'stranger@example.com');

SharedStudyFile _share({
  String id = 's1',
  String fileId = 'f1',
  String name = 'Lecture 1.pdf',
  String fromUid = 'u-sender',
  String toUid = 'u-friend',
}) {
  return SharedStudyFile(
    id: id,
    fileId: fileId,
    name: name,
    sizeBytes: 2048,
    kind: 'pdf',
    folder: 'Lectures',
    added: DateTime(2026, 11, 5),
    fromUid: fromUid,
    fromName: 'Sender',
    toUid: toUid,
    sharedAt: DateTime(2026, 11, 8, 10, 0),
  );
}

void main() {
  group('SharedStudyFile model', () {
    test('toJson/fromJson round-trips every field', () {
      final share = _share();
      final restored = SharedStudyFile.fromJson(
        share.id,
        Map<String, dynamic>.from(share.toJson()),
      );
      expect(restored.id, 's1');
      expect(restored.fileId, 'f1');
      expect(restored.name, 'Lecture 1.pdf');
      expect(restored.sizeBytes, 2048);
      expect(restored.kind, 'pdf');
      expect(restored.folder, 'Lectures');
      expect(restored.added, DateTime(2026, 11, 5));
      expect(restored.fromUid, 'u-sender');
      expect(restored.fromName, 'Sender');
      expect(restored.toUid, 'u-friend');
      expect(restored.sharedAt, DateTime(2026, 11, 8, 10, 0));
    });

    test('fromJson falls back to the stored id and honest defaults', () {
      final restored = SharedStudyFile.fromJson('', {
        'id': 's9',
        'fileId': 'f9',
      });
      expect(restored.id, 's9');
      expect(restored.name, 'Untitled file');
      expect(restored.kind, 'other');
      expect(restored.folder, 'Lectures');
      expect(restored.fromUid, '');
      expect(restored.toUid, '');
    });
  });

  group('validateSharedStudyFile', () {
    test('a complete share is valid', () {
      expect(validateSharedStudyFile(_share()), isNull);
    });

    test('missing recipient is rejected', () {
      expect(
        validateSharedStudyFile(_share(toUid: '')),
        'Choose a friend to share with.',
      );
    });

    test('self-share is rejected', () {
      expect(
        validateSharedStudyFile(_share(toUid: 'u-sender')),
        'You cannot share a file with yourself.',
      );
    });

    test('missing sender and empty name are rejected', () {
      expect(
        validateSharedStudyFile(_share(fromUid: '')),
        'Missing sender.',
      );
      expect(
        validateSharedStudyFile(_share(name: '   ')),
        'Missing file name.',
      );
    });
  });

  group('validateFileName', () {
    test('a normal name is valid', () {
      expect(validateFileName('Lecture 1.pdf'), isNull);
    });

    test('empty and blank names are rejected', () {
      expect(validateFileName(''), 'Enter a name for the file.');
      expect(validateFileName('   '), 'Enter a name for the file.');
    });

    test('101 characters is rejected, 100 is allowed', () {
      expect(
        validateFileName('a' * 101),
        'The name must be 100 characters or fewer.',
      );
      expect(validateFileName('a' * 100), isNull);
    });
  });

  group('LocalSharedStudyFileRepository', () {
    late LocalSharedStudyFileRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = LocalSharedStudyFileRepository();
    });

    test('share then fetchSharedWithMe returns it, newest first',
        () async {
      await repo.share(_share(id: 's1'), _sender);
      await repo.share(
        _share(id: 's2', fileId: 'f2', name: 'Activity 1.docx'),
        _sender,
      );
      // Newest first: s2 was shared after s1.
      final mine = await repo.fetchSharedWithMe('u-friend');
      expect(mine.map((s) => s.id).toList(), ['s2', 's1']);
      expect(mine.first.name, 'Activity 1.docx');
      // Shares to someone else never leak in.
      expect(await repo.fetchSharedWithMe('u-stranger'), isEmpty);
    });

    test('sharing the same file to the same friend twice is one share',
        () async {
      final first = await repo.share(_share(id: 's1'), _sender);
      final second = await repo.share(_share(id: 's-other'), _sender);
      expect(second.id, first.id);
      final mine = await repo.fetchSharedWithMe('u-friend');
      expect(mine.length, 1);
    });

    test('sharing as someone else throws StateError', () async {
      expect(
        () => repo.share(_share(), _stranger),
        throwsStateError,
      );
    });

    test('an invalid share throws ArgumentError', () async {
      expect(
        () => repo.share(_share(toUid: ''), _sender),
        throwsArgumentError,
      );
      expect(
        () => repo.share(_share(toUid: 'u-sender'), _sender),
        throwsArgumentError,
      );
    });

    test('the sender and the recipient can delete, a stranger cannot',
        () async {
      await repo.share(_share(id: 's1'), _sender);
      expect(
        () => repo.delete('s1', _stranger),
        throwsStateError,
      );
      await repo.delete('s1', _friend);
      expect(await repo.fetchSharedWithMe('u-friend'), isEmpty);
      // Deleting a missing share is a no-op, never an error.
      await repo.delete('s1', _sender);
    });

    test('deleteSharesForFile removes only that sender\'s shares of '
        'the file', () async {
      await repo.share(_share(id: 's1', fileId: 'f1'), _sender);
      await repo.share(
        _share(id: 's2', fileId: 'f2', name: 'Activity 1.docx'),
        _sender,
      );
      await repo.deleteSharesForFile('f1', _sender);
      final mine = await repo.fetchSharedWithMe('u-friend');
      expect(mine.map((s) => s.id).toList(), ['s2']);
    });
  });
}
