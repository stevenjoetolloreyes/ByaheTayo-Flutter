// Tests for Files storage enforcement (Builder 2, Nov 11, 2026):
// real usage + plan-limit enforcement + the real storage bar.
//
// Rules pinned here:
// * Usage is the real local sum of the stored files' sizeBytes —
//   never invented, never a second sum beside the panel's.
// * Adding a file that would take usage over the admin-assigned
//   plan limit is BLOCKED: the file is not saved and the message
//   names the plan and its limit and says to ask the admin to
//   upgrade. There is no self-serve Subscribe offer anywhere.
// * Exactly at the limit is allowed; 1 byte over is blocked.
// * The Files storage bar shows the real usage against the real
//   plan limit: Free 2 GB, Standard 12 GB, Pro 30 GB.
import 'package:estudyantego/features/study_tab.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/subscription_membership.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _gb = 1024 * 1024 * 1024;

StudyFile _file(String id, int sizeBytes) => StudyFile(
  id: id,
  name: '$id.pdf',
  sizeBytes: sizeBytes,
  kind: 'pdf',
  folder: 'Lectures',
  added: DateTime(2026, 11, 5),
);

Future<void> _pumpTab(
  WidgetTester tester, {
  Map<String, Object>? prefs,
  SubscriptionPlanId plan = SubscriptionPlanId.free,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StudyTab(plan: plan)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('study-nav-files')));
  await tester.pumpAndSettle();
}

String _filesJson(List<(String, int)> files) =>
    '[${files.map((f) => '{"id":"${f.$1}","name":"${f.$1}.pdf",'
    '"sizeBytes":${f.$2},"kind":"pdf","folder":"Lectures",'
    '"added":"2026-11-05T00:00:00.000"}').join(',')}]';

void main() {
  group('studyFilesUsedBytes — real local usage sum', () {
    test('empty list is 0', () {
      expect(studyFilesUsedBytes(const []), 0);
    });

    test('sums sizeBytes across files', () {
      expect(
        studyFilesUsedBytes([_file('f1', 2048), _file('f2', 512)]),
        2560,
      );
    });

    test('zero-size files add nothing', () {
      expect(
        studyFilesUsedBytes([_file('f1', 0), _file('f2', 1536)]),
        1536,
      );
    });
  });

  group('studyFileAddFits — block-when-over, allow-when-under', () {
    test('under the limit is allowed', () {
      expect(
        studyFileAddFits(
          usedBytes: _gb,
          newFileBytes: 512 * 1024 * 1024,
          plan: SubscriptionPlanId.free,
        ),
        isTrue,
      );
    });

    test('over the limit is blocked on every plan', () {
      // Free: 1 GB used + a 1 GB + 1 byte file would pass 2 GB.
      expect(
        studyFileAddFits(
          usedBytes: _gb,
          newFileBytes: _gb + 1,
          plan: SubscriptionPlanId.free,
        ),
        isFalse,
      );
      // Standard: 11 GB used + a 1 GB + 1 byte file would pass 12 GB.
      expect(
        studyFileAddFits(
          usedBytes: 11 * _gb,
          newFileBytes: _gb + 1,
          plan: SubscriptionPlanId.standard,
        ),
        isFalse,
      );
      // Pro: 29 GB used + a 1 GB + 1 byte file would pass 30 GB.
      expect(
        studyFileAddFits(
          usedBytes: 29 * _gb,
          newFileBytes: _gb + 1,
          plan: SubscriptionPlanId.pro,
        ),
        isFalse,
      );
    });

    test('a new file bigger than the whole limit is blocked even at 0 used', () {
      expect(
        studyFileAddFits(
          usedBytes: 0,
          newFileBytes: 2 * _gb + 1,
          plan: SubscriptionPlanId.free,
        ),
        isFalse,
      );
    });

    test('exactly at the limit is allowed', () {
      expect(
        studyFileAddFits(
          usedBytes: _gb,
          newFileBytes: _gb,
          plan: SubscriptionPlanId.free,
        ),
        isTrue,
      );
      expect(
        studyFileAddFits(
          usedBytes: 0,
          newFileBytes: 12 * _gb,
          plan: SubscriptionPlanId.standard,
        ),
        isTrue,
      );
      expect(
        studyFileAddFits(
          usedBytes: 0,
          newFileBytes: 30 * _gb,
          plan: SubscriptionPlanId.pro,
        ),
        isTrue,
      );
    });

    test('1 byte over the limit is blocked', () {
      expect(
        studyFileAddFits(
          usedBytes: _gb,
          newFileBytes: _gb + 1,
          plan: SubscriptionPlanId.free,
        ),
        isFalse,
      );
      expect(
        studyFileAddFits(
          usedBytes: 0,
          newFileBytes: 12 * _gb + 1,
          plan: SubscriptionPlanId.standard,
        ),
        isFalse,
      );
      expect(
        studyFileAddFits(
          usedBytes: 0,
          newFileBytes: 30 * _gb + 1,
          plan: SubscriptionPlanId.pro,
        ),
        isFalse,
      );
    });
  });

  group('studyFileOverLimitMessage — honest, admin-assigned upgrade', () {
    test('Free names the plan, its 2 GB limit, and the admin prompt', () {
      final message = studyFileOverLimitMessage(plan: SubscriptionPlanId.free);
      expect(message, contains('Free'));
      expect(message, contains('2 GB'));
      expect(message, contains('over your limit'));
      expect(message, contains('Ask the admin to upgrade your plan'));
      expect(message, isNot(contains('Subscribe')));
    });

    test('Standard names 12 GB', () {
      final message = studyFileOverLimitMessage(
        plan: SubscriptionPlanId.standard,
      );
      expect(message, contains('Standard'));
      expect(message, contains('12 GB'));
      expect(message, contains('Ask the admin to upgrade your plan'));
      expect(message, isNot(contains('Subscribe')));
    });

    test('Pro names 30 GB', () {
      final message = studyFileOverLimitMessage(plan: SubscriptionPlanId.pro);
      expect(message, contains('Pro'));
      expect(message, contains('30 GB'));
      expect(message, contains('Ask the admin to upgrade your plan'));
      expect(message, isNot(contains('Subscribe')));
    });
  });

  group('Files storage bar — real usage against the real plan limit', () {
    testWidgets('Free: empty files show 0 B of 2 GB used — Free plan', (
      tester,
    ) async {
      await _pumpTab(tester, plan: SubscriptionPlanId.free);
      expect(find.text('0 B of 2 GB used — Free plan'), findsOneWidget);
      expect(find.text('0 B of 5 GB used'), findsNothing);
    });

    testWidgets('Standard: real usage of 12 GB', (tester) async {
      await _pumpTab(
        tester,
        plan: SubscriptionPlanId.standard,
        prefs: {
          'byahetayo_student_files': _filesJson([
            ('f1', 2048),
            ('f2', 512),
          ]),
        },
      );
      expect(
        find.text('2.5 KB of 12 GB used — Standard plan'),
        findsOneWidget,
      );
    });

    testWidgets('Pro: real usage of 30 GB', (tester) async {
      await _pumpTab(
        tester,
        plan: SubscriptionPlanId.pro,
        prefs: {
          'byahetayo_student_files': _filesJson([
            ('f1', 2048),
            ('f2', 512),
          ]),
        },
      );
      expect(find.text('2.5 KB of 30 GB used — Pro plan'), findsOneWidget);
    });

    testWidgets('Free: a 1.50 GB file shows against the 2 GB limit', (
      tester,
    ) async {
      await _pumpTab(
        tester,
        plan: SubscriptionPlanId.free,
        prefs: {
          'byahetayo_student_files': _filesJson([
            ('f1', (1.5 * _gb).round()),
          ]),
        },
      );
      expect(
        find.text('1.50 GB of 2 GB used — Free plan'),
        findsOneWidget,
      );
    });
  });
}
