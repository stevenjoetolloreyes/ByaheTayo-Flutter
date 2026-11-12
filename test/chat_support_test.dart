// Tests for Chat Support (Nov 11, 2026, preview v17).
//
// Covers the pure assistant logic (topic detection + auto-replies,
// exact preview wording), the Meta-style flow through a fake
// repository (bot greeting, topic auto-replies, Yes/No help-check,
// Steven joins only after No, Close/Start, 5-star rating), the
// direct Chat with Admin screen (no bot, no auto-reply, no rating),
// the admin Support Inbox (list, unread badge, reply), and the
// Account tab wiring (Chat Support row first in Account Actions
// with NEW tag, no "Chat with Admin" row).
import 'dart:async';

import 'package:estudyantego/features/chat_support.dart';
import 'package:estudyantego/features/chat_support_screen.dart';
import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/support_inbox_screen.dart';
import 'package:estudyantego/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

/// In-memory [SupportRepository] with Firestore-like ordering
/// (messages oldest first, conversations newest first). Stream
/// emissions mirror the real repo: every mutation re-emits.
class FakeSupportRepository implements SupportRepository {
  int _counter = 0;
  int _tick = 0;

  DateTime _now() {
    _tick += 1;
    return DateTime(2026, 11, 11, 9, 30).add(Duration(seconds: _tick));
  }

  String _nextId(String prefix) {
    _counter += 1;
    return '$prefix-$_counter';
  }

  final Map<String, SupportConversation> _conversations = {};
  final Map<String, List<SupportMessage>> _messages = {};

  final Map<String, StreamController<List<SupportConversation>>>
  _studentControllers = {};
  StreamController<List<SupportConversation>>? _adminController;
  final Map<String, StreamController<List<SupportMessage>>>
  _messageControllers = {};
  final Map<String, StreamController<SupportConversation?>>
  _conversationControllers = {};

  List<SupportConversation> _sortedConversations() {
    final list = _conversations.values.toList();
    list.sort((a, b) {
      final aTime = a.updatedAt;
      final bTime = b.updatedAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  void _emitAll() {
    for (final entry in _studentControllers.entries) {
      entry.value.add(
        _sortedConversations()
            .where((c) => c.studentUid == entry.key)
            .toList(),
      );
    }
    _adminController?.add(_sortedConversations());
    for (final entry in _messageControllers.entries) {
      entry.value.add(List.of(_messages[entry.key] ?? const []));
    }
    for (final entry in _conversationControllers.entries) {
      entry.value.add(_conversations[entry.key]);
    }
  }

  SupportConversation _with({
    required SupportConversation base,
    String? lastMessage,
    String? lastSender,
    SupportTopic? topic,
    int? unreadForAdmin,
    int? unreadForStudent,
    bool? closed,
    int? rating,
  }) {
    return SupportConversation(
      id: base.id,
      studentUid: base.studentUid,
      studentName: base.studentName,
      lastMessage: lastMessage ?? base.lastMessage,
      lastMessageAt: _now(),
      lastSender: lastSender ?? base.lastSender,
      topic: topic ?? base.topic,
      unreadForAdmin: unreadForAdmin ?? base.unreadForAdmin,
      unreadForStudent: unreadForStudent ?? base.unreadForStudent,
      closed: closed ?? base.closed,
      rating: rating ?? base.rating,
      createdAt: base.createdAt,
      updatedAt: _now(),
    );
  }

  SupportConversation _newConversation({
    required String studentUid,
    required String studentName,
  }) {
    final id = _nextId('conv');
    final now = _now();
    final conversation = SupportConversation(
      id: id,
      studentUid: studentUid,
      studentName: studentName,
      lastMessage: supportGreeting,
      lastMessageAt: now,
      lastSender: 'assistant',
      unreadForAdmin: 0,
      unreadForStudent: 0,
      closed: false,
      createdAt: now,
      updatedAt: now,
    );
    _conversations[id] = conversation;
    _messages[id] = [
      SupportMessage(
        id: _nextId('msg'),
        sender: SupportSender.assistant,
        text: supportGreeting,
        system: false,
        createdAt: now,
      ),
    ];
    return conversation;
  }

  @override
  Stream<List<SupportConversation>> watchForStudent(String uid) {
    final controller =
        StreamController<List<SupportConversation>>.broadcast();
    _studentControllers[uid] = controller;
    controller.onListen = () => controller.add(
      _sortedConversations().where((c) => c.studentUid == uid).toList(),
    );
    return controller.stream;
  }

  @override
  Stream<List<SupportConversation>> watchAllForAdmin() {
    final controller =
        StreamController<List<SupportConversation>>.broadcast();
    _adminController = controller;
    controller.onListen = () => controller.add(_sortedConversations());
    return controller.stream;
  }

  @override
  Stream<SupportConversation?> watchConversation(String conversationId) {
    final controller =
        StreamController<SupportConversation?>.broadcast();
    _conversationControllers[conversationId] = controller;
    controller.onListen =
        () => controller.add(_conversations[conversationId]);
    return controller.stream;
  }

  @override
  Stream<List<SupportMessage>> watchMessages(String conversationId) {
    final controller = StreamController<List<SupportMessage>>.broadcast();
    _messageControllers[conversationId] = controller;
    controller.onListen =
        () => controller.add(List.of(_messages[conversationId] ?? const []));
    return controller.stream;
  }

  @override
  Future<({SupportConversation conversation, bool isNew})>
  openOrCreateForStudent({
    required String studentUid,
    required String studentName,
  }) async {
    final existing = _sortedConversations()
        .where((c) => c.studentUid == studentUid)
        .toList();
    if (existing.isNotEmpty) {
      return (conversation: existing.first, isNew: false);
    }
    return (conversation: _newConversation(
      studentUid: studentUid,
      studentName: studentName,
    ), isNew: true);
  }

  @override
  Future<SupportConversation> createFreshForStudent({
    required String studentUid,
    required String studentName,
  }) async {
    final created = _newConversation(
      studentUid: studentUid,
      studentName: studentName,
    );
    _emitAll();
    return created;
  }

  @override
  Future<void> sendStudentMessage({
    required SupportConversation conversation,
    required String text,
    SupportTopic? topic,
  }) async {
    final base = _conversations[conversation.id]!;
    _messages[conversation.id]!.add(
      SupportMessage(
        id: _nextId('msg'),
        sender: SupportSender.student,
        text: text,
        system: false,
        topic: topic,
        createdAt: _now(),
      ),
    );
    _conversations[conversation.id] = _with(
      base: base,
      lastMessage: text,
      lastSender: 'student',
      topic: topic,
      unreadForAdmin: base.unreadForAdmin + 1,
    );
    _emitAll();
  }

  @override
  Future<String> sendAssistantMessage({
    required SupportConversation conversation,
    required String text,
  }) async {
    final id = _nextId('msg');
    final base = _conversations[conversation.id]!;
    _messages[conversation.id]!.add(
      SupportMessage(
        id: id,
        sender: SupportSender.assistant,
        text: text,
        system: false,
        createdAt: _now(),
      ),
    );
    _conversations[conversation.id] = _with(
      base: base,
      lastMessage: text,
      lastSender: 'assistant',
    );
    _emitAll();
    return id;
  }

  @override
  Future<void> sendAdminMessage({
    required SupportConversation conversation,
    required String text,
    bool system = false,
  }) async {
    final base = _conversations[conversation.id]!;
    _messages[conversation.id]!.add(
      SupportMessage(
        id: _nextId('msg'),
        sender: SupportSender.admin,
        text: text,
        system: system,
        createdAt: _now(),
      ),
    );
    _conversations[conversation.id] = _with(
      base: base,
      lastMessage: text,
      lastSender: 'admin',
      unreadForStudent: system
          ? base.unreadForStudent
          : base.unreadForStudent + 1,
    );
    _emitAll();
  }

  @override
  Future<void> markAdminRead(String conversationId) async {
    final base = _conversations[conversationId];
    if (base == null) return;
    _conversations[conversationId] =
        _with(base: base, unreadForAdmin: 0);
    _emitAll();
  }

  @override
  Future<void> markStudentRead(String conversationId) async {
    final base = _conversations[conversationId];
    if (base == null) return;
    _conversations[conversationId] =
        _with(base: base, unreadForStudent: 0);
    _emitAll();
  }

  @override
  Future<void> closeConversation(String conversationId) async {
    final base = _conversations[conversationId];
    if (base == null) return;
    _conversations[conversationId] = _with(base: base, closed: true);
    _emitAll();
  }

  @override
  Future<void> rateConversation(String conversationId, int stars) async {
    final base = _conversations[conversationId];
    if (base == null) return;
    _conversations[conversationId] = _with(base: base, rating: stars);
    _emitAll();
  }
}

const _student = AuthUser(
  uid: 'student-1',
  email: 'maria@example.com',
  displayName: 'Maria Santos',
  emailVerified: true,
);

/// Pumps frames until pending zero-duration timers + stream events
/// flush. Never pumpAndSettle: the typing bubble animates forever.
Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpChatSupport(
  WidgetTester tester,
  FakeSupportRepository repository, {
  SupportChatMode mode = SupportChatMode.assisted,
}) async {
  final screen = mode == SupportChatMode.assisted
      ? ChatSupportScreen(
          repository: repository,
          user: _student,
          studentName: 'Maria',
          typingDelay: Duration.zero,
          connectingDelay: Duration.zero,
          ratingThanksDelay: Duration.zero,
        )
      : ChatWithAdminScreen(
          repository: repository,
          user: _student,
          studentName: 'Maria',
          typingDelay: Duration.zero,
          connectingDelay: Duration.zero,
          ratingThanksDelay: Duration.zero,
        );
  await tester.pumpWidget(
    MaterialApp(
      theme: minecraftThemeData(Brightness.light),
      home: screen,
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _sendText(
  WidgetTester tester,
  String text,
) async {
  await tester.enterText(
    find.byKey(const Key('chat-support-input')),
    text,
  );
  await tester.tap(find.byKey(const Key('chat-support-send')));
  await _pumpFrames(tester);
}

void main() {
  group('detectSupportTopic', () {
    test('apk wins: install / download / apk', () {
      expect(detectSupportTopic('How do I install the APK?'),
          SupportTopic.apk);
      expect(detectSupportTopic('where is the download link'),
          SupportTopic.apk);
    });

    test('schedule: schedule / class', () {
      expect(detectSupportTopic('My class schedule is not showing'),
          SupportTopic.schedule);
      expect(detectSupportTopic('my classes are missing'),
          SupportTopic.schedule);
    });

    test('fares: fare / bus', () {
      expect(detectSupportTopic('How much is the fare to Vigan?'),
          SupportTopic.fares);
      expect(detectSupportTopic('which bus goes to Cabugao'),
          SupportTopic.fares);
    });

    test('account: account / sign-in / profile / password', () {
      expect(detectSupportTopic("I can't sign in"), SupportTopic.account);
      expect(detectSupportTopic('my profile is wrong'), SupportTopic.account);
      expect(
          detectSupportTopic('I forgot my password'), SupportTopic.account);
    });

    test('anything else falls back to other', () {
      expect(detectSupportTopic('hello there'), SupportTopic.other);
      expect(detectSupportTopic(''), SupportTopic.other);
    });
  });

  group('supportAutoReply', () {
    test('schedule gives the Classes refresh / re-scan steps', () {
      final reply = supportAutoReply(SupportTopic.schedule);
      expect(reply, contains('Classes'));
      expect(reply, contains('re-scan your schedule file'));
      expect(reply, contains('internet'));
    });

    test('fares gives Cabugao to Vigan ₱60 / ₱48', () {
      final reply = supportAutoReply(SupportTopic.fares);
      expect(reply, contains('₱60'));
      expect(reply, contains('₱48'));
      expect(reply, contains('Fares'));
    });

    test('account gives the right-account + profile checks', () {
      final reply = supportAutoReply(SupportTopic.account);
      expect(reply, contains('right account'));
      expect(reply, contains('Account'));
    });

    test('apk gives Android 8.0+, 161 MB, Install unknown apps', () {
      final reply = supportAutoReply(SupportTopic.apk);
      expect(reply, contains('Android 8.0'));
      expect(reply, contains('161 MB'));
      expect(reply, contains('Install unknown apps'));
    });

    test('other falls back to the fixed message', () {
      expect(
        supportAutoReply(SupportTopic.other),
        supportFallbackMessage,
      );
      expect(
        supportFallbackMessage,
        contains("We've got your message — Steven will reply soon."),
      );
    });
  });

  group('supportFirstName + supportInboxTime', () {
    test('first name is the first word of the display name', () {
      expect(supportFirstName('Maria Santos', 'maria@example.com'), 'Maria');
      expect(supportFirstName(null, 'juan@example.com'), 'juan');
      expect(supportFirstName(null, null), 'Student');
    });

    test('inbox time: today time, yesterday, older date', () {
      final now = DateTime(2026, 11, 11, 12, 0);
      expect(
        supportInboxTime(DateTime(2026, 11, 11, 9, 32), now: now),
        '9:32 AM',
      );
      expect(
        supportInboxTime(DateTime(2026, 11, 10, 18, 5), now: now),
        'Yesterday',
      );
      expect(
        supportInboxTime(DateTime(2026, 11, 9, 18, 5), now: now),
        'Nov 9, 2026',
      );
    });
  });

  group('ChatSupportScreen flow', () {
    testWidgets('a new conversation opens bot-first with the greeting',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      expect(find.text(supportGreeting), findsOneWidget);
      expect(find.text('Chat Support'), findsOneWidget);
      // Inline topic chips under the greeting.
      expect(
        find.byKey(const Key('chat-support-topic-greeting-schedule')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('chat-support-topic-greeting-admin')),
        findsOneWidget,
      );
      // Quick Help row above the input.
      expect(find.byKey(const Key('quick-help-schedule')), findsOneWidget);
      expect(find.byKey(const Key('quick-help-admin')), findsOneWidget);
    });

    testWidgets('typed fare question gets the ₱60/₱48 auto-reply + help-check',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      await _sendText(tester, 'How much is the fare from Cabugao to Vigan?');

      expect(find.text('How much is the fare from Cabugao to Vigan?'),
          findsOneWidget);
      expect(find.textContaining('₱60'), findsOneWidget);
      expect(find.textContaining('₱48'), findsOneWidget);
      expect(find.text('Did this help?'), findsOneWidget);
    });

    testWidgets('Yes keeps the bot: great message, Steven never joins',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      await _sendText(tester, 'How much is the fare to Vigan?');
      await tester.tap(find.byKey(const Key('chat-support-help-yes')));
      await _pumpFrames(tester);

      expect(find.text(supportGreatMessage), findsOneWidget);
      expect(find.text(supportStevenJoinsMessage), findsNothing);
      expect(find.text('Did this help?'), findsNothing);
    });

    testWidgets(
        'No connects Steven: connecting then join, no more bot replies',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      await _sendText(tester, 'My class schedule is not showing');
      // Schedule auto-reply arrived (not the fallback).
      expect(find.textContaining('Classes'), findsWidgets);
      await tester.tap(find.byKey(const Key('chat-support-help-no')));
      await _pumpFrames(tester);

      // Steven joined only after No.
      expect(find.text(supportStevenJoinsMessage), findsOneWidget);
      // One auto-reply label so far (the schedule answer).
      expect(find.text(supportAssistantLabel), findsOneWidget);

      // A follow-up goes to Steven only — no new bot answer.
      await _sendText(tester, 'It is still missing, please help');
      expect(find.text(supportAssistantLabel), findsOneWidget);
      expect(find.text('It is still missing, please help'), findsOneWidget);
    });

    testWidgets('Quick Help Fares chip posts the topic and answers it',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      await tester.tap(find.byKey(const Key('quick-help-fares')));
      await _pumpFrames(tester);

      // The chip posted the topic and the assistant answered it.
      expect(find.textContaining('₱60'), findsOneWidget);
      expect(find.textContaining('₱48'), findsOneWidget);
      expect(find.text('Did this help?'), findsOneWidget);
    });

    testWidgets('Close asks, rates, thanks, ends, and starts fresh',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      await _sendText(tester, 'hello');
      await tester.tap(find.byKey(const Key('chat-support-close')));
      await _pumpFrames(tester);

      // Confirm dialog first.
      expect(find.text('Close this chat?'), findsOneWidget);
      await tester.tap(find.text('Close chat'));
      await _pumpFrames(tester);

      // Rating step (Chat Support only).
      expect(find.text(supportHowWasExperience), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-support-star-5')));
      await _pumpFrames(tester);

      // Ended panel + fresh start.
      expect(find.text(supportEndedMessage), findsOneWidget);
      expect(find.text('Start a new conversation'), findsOneWidget);
      expect(
        find.byKey(const Key('chat-support-input')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('chat-support-new-conversation')),
      );
      await _pumpFrames(tester);

      // Fresh empty chat: greeting again, working input box.
      expect(find.text(supportGreeting), findsOneWidget);
      expect(find.byKey(const Key('chat-support-input')), findsOneWidget);
      expect(find.text(supportEndedMessage), findsNothing);
    });

    testWidgets('greeting chips: Chat with Admin opens the direct screen',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(tester, repository);

      await tester.tap(
        find.byKey(const Key('chat-support-topic-greeting-admin')),
      );
      await _pumpFrames(tester);

      expect(find.text('Chat with Admin'), findsWidgets);
      expect(
        find.textContaining('Admin · Steven Joe T. Reyes'),
        findsOneWidget,
      );
      // Direct screen: no bot greeting, no Quick Help. (The
      // greeting still lives on the covered Chat Support route
      // below, so only hit-testable widgets count here.)
      expect(find.text(supportGreeting).hitTestable(), findsNothing);
      expect(
        find.byKey(const Key('quick-help-schedule')).hitTestable(),
        findsNothing,
      );
    });
  });

  group('ChatWithAdminScreen', () {
    testWidgets('direct chat: no auto-reply, no Quick Help, no rating',
        (tester) async {
      final repository = FakeSupportRepository();
      await _pumpChatSupport(
        tester,
        repository,
        mode: SupportChatMode.directAdmin,
      );

      expect(find.text('Chat with Admin'), findsOneWidget);
      expect(find.byKey(const Key('quick-help-schedule')), findsNothing);

      await _sendText(tester, 'How do I upgrade my plan?');
      await _pumpFrames(tester);

      // No bot answer at all.
      expect(find.text(supportAssistantLabel), findsNothing);
      expect(find.text('Did this help?'), findsNothing);
      expect(find.text('How do I upgrade my plan?'), findsOneWidget);

      // Close skips the rating step.
      await tester.tap(find.byKey(const Key('chat-support-close')));
      await _pumpFrames(tester);
      await tester.tap(find.text('Close chat'));
      await _pumpFrames(tester);

      expect(find.text(supportHowWasExperience), findsNothing);
      expect(find.text(supportEndedMessage), findsOneWidget);
    });
  });

  group('SupportInboxScreen', () {
    testWidgets('lists conversations, badge clears on open, reply works',
        (tester) async {
      final repository = FakeSupportRepository();
      // Seed two threads: Maria (unread) and Juan (read).
      final maria = await repository.openOrCreateForStudent(
        studentUid: 'student-1',
        studentName: 'Maria',
      );
      await repository.sendStudentMessage(
        conversation: maria.conversation,
        text: 'Hi! My class schedule is not showing in the app.',
        topic: SupportTopic.schedule,
      );
      final juan = await repository.createFreshForStudent(
        studentUid: 'student-2',
        studentName: 'Juan',
      );
      await repository.sendStudentMessage(
        conversation: juan,
        text: 'How much is the fare from Cabugao to Vigan?',
        topic: SupportTopic.fares,
      );
      await repository.markAdminRead(juan.id);

      await tester.pumpWidget(
        MaterialApp(
          theme: minecraftThemeData(Brightness.light),
          home: Scaffold(
            appBar: AppBar(title: const Text('Support Inbox')),
            body: SupportInboxScreen(
              repository: repository,
              adminEmail: 'stevenjoereyes0625@gmail.com',
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('Juan'), findsOneWidget);
      expect(
        find.text('Hi! My class schedule is not showing in the app.'),
        findsOneWidget,
      );
      // Maria's unread badge; Juan's is cleared.
      expect(find.text('1'), findsOneWidget);

      // Open Maria: badge clears, student message on the left.
      await tester.tap(find.text('Maria'));
      await _pumpFrames(tester);
      expect(find.text('Student · via Chat Support'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('support-admin-messages')),
          matching: find.text(
            'Hi! My class schedule is not showing in the app.',
          ),
        ),
        findsOneWidget,
      );
      expect(repository._conversations[maria.conversation.id]!.unreadForAdmin,
          0);

      // Steven replies: bubble appears on the right.
      await tester.enterText(
        find.byKey(const Key('support-admin-input')),
        'Try refreshing Classes first.',
      );
      await tester.tap(find.byKey(const Key('support-admin-send')));
      await _pumpFrames(tester);
      expect(find.text('Try refreshing Classes first.'), findsOneWidget);

      // Back returns to the list (AppBar title + body header).
      await tester.tap(find.byTooltip('Back'));
      await _pumpFrames(tester);
      expect(find.text('Support Inbox'), findsNWidgets(2));
    });

    testWidgets('empty inbox is honest', (tester) async {
      final repository = FakeSupportRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: minecraftThemeData(Brightness.light),
          home: Scaffold(
            body: SupportInboxScreen(
              repository: repository,
              adminEmail: 'stevenjoereyes0625@gmail.com',
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('No support conversations yet.'), findsOneWidget);
    });
  });

  group('Account tab wiring', () {
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'byahetayo_onboarding_done': true,
        'byahetayo_profile_setup_done_uid-1': true,
        'byahetayo_profile_uid-1':
            '{"displayName":"Steven Reyes","email":"steven@example.com"}',
      });
      await tester.pumpWidget(EstudyanteGOApp(
        authService: FakeAuthService(
          user: const AuthUser(
            uid: 'uid-1',
            email: 'steven@example.com',
            displayName: 'Steven Reyes',
            emailVerified: true,
          ),
        ),
        permissionService: FakePermissionService(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sidebar-item-Account')));
      await tester.pumpAndSettle();
    }

    testWidgets('Chat Support is the first Account Actions row with NEW',
        (tester) async {
      await pumpApp(tester);

      await tester.ensureVisible(find.text('Chat Support'));
      await tester.pumpAndSettle();
      expect(find.text('Chat Support'), findsOneWidget);
      expect(find.text('Message the EstudyanteGO team'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      // No "Chat with Admin" row on the Account tab (preview v13).
      expect(find.text('Chat with Admin'), findsNothing);
    });
  });
}
