// Chat Support — student ↔ admin messaging (Nov 11, 2026).
//
// Built from approved preview v17 (`estudyantego-chat-support-preview`):
// Meta-style flow — the assistant greets first, topic-aware auto-replies
// answer, "Did this help?" decides whether Steven joins, and closing
// asks for a 5-star rating. Chat with Admin is the same conversation
// in direct mode: no bot, no auto-reply, no rating.
//
// DATA: Firestore, following the app's existing patterns
// (`app_reviews.dart`, `app_review_notifications.dart`):
//   support_conversations/{id} — one thread per student conversation
//     (studentUid, studentName = first name only, lastMessage,
//     lastMessageAt, lastSender, topic, unreadForAdmin,
//     unreadForStudent, closed, rating, createdAt, updatedAt).
//   support_conversations/{id}/messages/{messageId} — append-only
//     (sender 'student' | 'admin' | 'assistant', text, system,
//     topic, createdAt). The "AI Assistant" is on-device and
//     rule-based: the student's own client writes the auto-reply
//     (see [detectSupportTopic] / [supportAutoReply]) — there is no
//     backend, no Gemini call, and no invented data. A new
//     conversation is created (never deleting the old one) by
//     "Start a new conversation".
//
// PRIVACY: a student reads only their own conversations
// (studentUid == uid); admins are the allowlisted emails in
// `firestore.rules` (`isAdmin()`). The inbox shows first names only.
// Rules enforce it server-side — see `firestore.rules`.
//
// The repository is lazy on purpose (same pattern as
// FirestoreAppReviewsRepository): constructing it never touches
// Firebase — the instance is resolved only when a read/write
// actually runs, so widget tests that don't initialize Firebase
// don't break. Reads degrade to an empty stream when Firebase
// isn't initialized; writes let the error surface so the screen
// can show its honest error.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'student/student_data.dart' show formatDate;

/// Who sent a support message.
enum SupportSender {
  /// The student.
  student,

  /// Steven, the admin (typed reply, or the auto handoff message
  /// when `system` is true — see [SupportMessage.system]).
  admin,

  /// The on-device assistant (greeting + auto-replies).
  assistant,
}

/// The topic of a student message, detected by [detectSupportTopic].
enum SupportTopic { schedule, fares, account, apk, other }

/// Short label for a topic (Quick Help chips, inbox topic tag).
String supportTopicLabel(SupportTopic topic) {
  switch (topic) {
    case SupportTopic.schedule:
      return 'Schedule';
    case SupportTopic.fares:
      return 'Fares';
    case SupportTopic.account:
      return 'Account';
    case SupportTopic.apk:
      return 'APK install';
    case SupportTopic.other:
      return 'Other';
  }
}

/// The Firestore value stored for a topic.
String supportTopicValue(SupportTopic topic) => topic.name;

SupportTopic supportTopicFromValue(String? value) {
  switch (value) {
    case 'schedule':
      return SupportTopic.schedule;
    case 'fares':
      return SupportTopic.fares;
    case 'account':
      return SupportTopic.account;
    case 'apk':
      return SupportTopic.apk;
    default:
      return SupportTopic.other;
  }
}

/// The assistant's opening greeting (preview v17, exact wording).
const String supportGreeting =
    "Hi! I'm the EstudyanteGO Assistant. What can I help you with today?";

/// Shown after "Yes, that helped" — the chat stays with the bot,
/// Steven never joins.
const String supportGreatMessage = 'Great! Message us anytime.';

/// Transient status shown for ~2s after "No, I need a human".
const String supportConnectingMessage = 'Connecting you to an agent…';

/// Steven's join message — only after the student taps
/// "No, I need a human". Never automatic (preview v17 fix).
const String supportStevenJoinsMessage =
    "Hi, I'm Steven, the admin. I'll help you from here.";

 /// Fallback auto-reply for anything off-topic (also the
/// 'other' topic answer).
const String supportFallbackMessage =
    "Thanks for messaging EstudyanteGO Support! We've got your message — Steven will reply soon.";

 /// The typing indicator text while the assistant answers.
const String supportTypingMessage = 'AI Assistant is typing…';

/// Appended when a conversation is closed.
const String supportEndedMessage = 'This chat has ended.';

/// Rating question asked when closing a Chat Support chat.
const String supportHowWasExperience = 'How was your experience?';

/// Shown after the student taps a star.
const String supportThanksFeedback = 'Thanks for your feedback!';

/// Title of the top popup the student gets on a real admin reply.
const String supportReplyPopupTitle = 'EstudyanteGO replied';

/// Sender labels shown above bubbles.
const String supportAssistantLabel = 'AI ASSISTANT · AUTO-REPLY';
const String supportGreetingLabel = 'ESTUDYANTEGO ASSISTANT';
const String supportAdminLabel = 'STEVEN · ADMIN';
const String supportStudentLabel = 'YOU';

/// Detects the topic of a student message — the preview v17 rules,
/// in the preview's order (APK first: "how do I install" is an
/// install question even when it mentions the app; "my class
/// schedule" is a schedule question because it mentions class).
SupportTopic detectSupportTopic(String text) {
  final t = text.toLowerCase();
  if (RegExp(r'apk|install|download').hasMatch(t)) return SupportTopic.apk;
  if (RegExp(r'schedule|class|classes').hasMatch(t)) {
    return SupportTopic.schedule;
  }
  if (RegExp(r'fare|fares|bus').hasMatch(t)) return SupportTopic.fares;
  if (RegExp(r'account|sign[ -]?in|log[ -]?in|profile|password')
      .hasMatch(t)) {
    return SupportTopic.account;
  }
  return SupportTopic.other;
}

/// The assistant's answer for a topic — preview v17's exact
/// wording, as plain text (numbered steps, no HTML).
String supportAutoReply(SupportTopic topic) {
  switch (topic) {
    case SupportTopic.schedule:
      return "Here's how to get your schedule back:\n"
          '1. Open the Classes tab and pull down to refresh.\n'
          '2. Check your internet connection, then reopen the app.\n'
          '3. If a class is still missing, tap + in Classes and '
          're-scan your schedule file.';
    case SupportTopic.fares:
      return 'Cabugao to Vigan is ₱60 regular / ₱48 discounted. '
          'Check the Fares tab for other routes.';
    case SupportTopic.account:
      return 'Check that you are signed in with the right account, '
          'and check your profile in the Account tab. If you still '
          "can't sign in, Steven will help.";
    case SupportTopic.apk:
      return 'To install the APK:\n'
          '1. Android 8.0 or higher — Android phone only.\n'
          '2. At least 161 MB free space.\n'
          '3. Allow "Install unknown apps" when prompted.\n'
          '4. Then open the downloaded APK to install.';
    case SupportTopic.other:
      return supportFallbackMessage;
  }
}

/// First name for the admin inbox (first names only, preview v15):
/// first word of the display name, else the email local part,
/// else 'Student'.
String supportFirstName(String? displayName, String? email) {
  final name = (displayName ?? '').trim();
  if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
  final mail = (email ?? '').trim();
  if (mail.isNotEmpty) return mail.split('@').first;
  return 'Student';
}

/// Inbox time label: today shows the time ("9:32 AM"), yesterday
/// shows "Yesterday", older shows the date ("Nov 11, 2026").
String supportInboxTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    final h = time.hour;
    final suffix = h >= 12 ? 'PM' : 'AM';
    var h12 = h % 12;
    if (h12 == 0) h12 = 12;
    return '$h12:${time.minute.toString().padLeft(2, '0')} $suffix';
  }
  if (diff == 1) return 'Yesterday';
  return formatDate(time);
}

/// One support conversation (a thread between one student and the
/// admin). The student side opens their latest thread; the admin
/// inbox lists all threads, newest first.
class SupportConversation {
  const SupportConversation({
    required this.id,
    required this.studentUid,
    required this.studentName,
    required this.lastMessage,
    this.lastMessageAt,
    required this.lastSender,
    this.topic,
    required this.unreadForAdmin,
    required this.unreadForStudent,
    required this.closed,
    this.rating,
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id.
  final String id;

  /// Firebase UID of the student this thread belongs to.
  final String studentUid;

  /// Student's first name only (inbox display).
  final String studentName;

  /// Preview of the latest message in the thread.
  final String lastMessage;

  /// When the latest message arrived (null while pending).
  final DateTime? lastMessageAt;

  /// 'student' | 'admin' | 'assistant'.
  final String lastSender;

  /// Detected topic of the latest student message, if any.
  final SupportTopic? topic;

  /// Unread student messages waiting for the admin (badge count).
  final int unreadForAdmin;

  /// Unread admin replies waiting for the student.
  final int unreadForStudent;

  /// True once the student closes the chat.
  final bool closed;

  /// The student's 1–5 star rating on close (Chat Support only).
  final int? rating;

  /// Server timestamp of creation (null while pending).
  final DateTime? createdAt;

  /// Server timestamp of the latest activity (null while pending).
  final DateTime? updatedAt;

  factory SupportConversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    DateTime? asDate(dynamic value) =>
        value is Timestamp ? value.toDate() : null;
    final ratingValue = data['rating'];
    final topicValue = data['topic'];
    return SupportConversation(
      id: doc.id,
      studentUid: data['studentUid'] as String? ?? '',
      studentName: data['studentName'] as String? ?? 'Student',
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: asDate(data['lastMessageAt']),
      lastSender: data['lastSender'] as String? ?? 'student',
      topic: topicValue is String
          ? supportTopicFromValue(topicValue)
          : null,
      unreadForAdmin: (data['unreadForAdmin'] as num?)?.toInt() ?? 0,
      unreadForStudent:
          (data['unreadForStudent'] as num?)?.toInt() ?? 0,
      closed: data['closed'] as bool? ?? false,
      rating: ratingValue is num ? ratingValue.toInt() : null,
      createdAt: asDate(data['createdAt']),
      updatedAt: asDate(data['updatedAt']),
    );
  }
}

/// One message inside a support conversation. Append-only: messages
/// are never edited or deleted (a closed chat is replaced by a new
/// conversation instead).
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.system,
    this.topic,
    this.createdAt,
  });

  /// Firestore document id.
  final String id;

  /// Who sent it.
  final SupportSender sender;

  /// Message text (1–1000 chars, enforced by the rules).
  final String text;

  /// True only for the Steven-join handoff message — written by
  /// the student's client when the student asks for a human, not
  /// typed by Steven himself.
  final bool system;

  /// Detected topic (student messages only).
  final SupportTopic? topic;

  /// Server timestamp (null while pending).
  final DateTime? createdAt;

  factory SupportMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final senderValue = data['sender'] as String? ?? 'student';
    final topicValue = data['topic'];
    final createdAt = data['createdAt'];
    return SupportMessage(
      id: doc.id,
      sender: switch (senderValue) {
        'admin' => SupportSender.admin,
        'assistant' => SupportSender.assistant,
        _ => SupportSender.student,
      },
      text: data['text'] as String? ?? '',
      system: data['system'] as bool? ?? false,
      topic: topicValue is String
          ? supportTopicFromValue(topicValue)
          : null,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
}

/// Reads/writes support conversations and messages. Swappable so
/// widget tests can use a fake.
abstract class SupportRepository {
  /// The student's threads, newest first, live.
  Stream<List<SupportConversation>> watchForStudent(String uid);

  /// All threads for the admin inbox, newest first, live.
  Stream<List<SupportConversation>> watchAllForAdmin();

  /// One thread, live (null when it doesn't exist).
  Stream<SupportConversation?> watchConversation(String conversationId);

  /// A thread's messages, oldest first, live.
  Stream<List<SupportMessage>> watchMessages(String conversationId);

  /// The student's latest thread — the latest open one, else the
  /// latest closed one (so the ended panel shows), else a brand
  /// new thread with the greeting already written. [isNew] is
  /// true only when a thread was just created (the screen shows
  /// the greeting after a short typing pause in that case).
  Future<({SupportConversation conversation, bool isNew})>
  openOrCreateForStudent({
    required String studentUid,
    required String studentName,
  });

  /// Always a brand new thread (greeting already written) — the
  /// "Start a new conversation" action.
  Future<SupportConversation> createFreshForStudent({
    required String studentUid,
    required String studentName,
  });

  /// The student sends a message: writes the message and updates
  /// the thread (last message, topic, admin unread +1).
  Future<void> sendStudentMessage({
    required SupportConversation conversation,
    required String text,
    SupportTopic? topic,
  });

  /// The on-device assistant answers: writes the message and
  /// updates the thread's last message. Returns the new message id
  /// (the screen anchors "Did this help?" to it).
  Future<String> sendAssistantMessage({
    required SupportConversation conversation,
    required String text,
  });

  /// Steven replies from the inbox ([system] false, a real typed
  /// reply — bumps the student's unread count) or the auto handoff
  /// message ([system] true — no unread bump: the student is
  /// watching the chat when it appears).
  Future<void> sendAdminMessage({
    required SupportConversation conversation,
    required String text,
    bool system = false,
  });

  /// The admin opened the thread — clears the admin badge.
  Future<void> markAdminRead(String conversationId);

  /// The student is viewing the thread — clears the student badge.
  Future<void> markStudentRead(String conversationId);

  /// The student closed the chat.
  Future<void> closeConversation(String conversationId);

  /// The student's 1–5 star rating on close (Chat Support only).
  Future<void> rateConversation(String conversationId, int stars);
}

/// Firestore `support_conversations` implementation.
class FirestoreSupportRepository implements SupportRepository {
  /// Lazy — resolved only when a read/write actually runs, so
  /// constructing the repo in the shell build never touches
  /// Firebase (widget tests don't initialize it).
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('support_conversations');

  CollectionReference<Map<String, dynamic>> _messages(String id) =>
      _conversations.doc(id).collection('messages');

  List<SupportConversation> _sortedConversations(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final list =
        snap.docs.map(SupportConversation.fromDoc).toList();
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

  @override
  Stream<List<SupportConversation>> watchForStudent(String uid) {
    try {
      // Single where only (no orderBy) — no composite index
      // needed; newest first is done client-side below.
      return _conversations
          .where('studentUid', isEqualTo: uid)
          .snapshots()
          .map(_sortedConversations);
    } on FirebaseException {
      return Stream.value(const <SupportConversation>[]);
    }
  }

  @override
  Stream<List<SupportConversation>> watchAllForAdmin() {
    try {
      // Single orderBy only — no composite index needed.
      return _conversations
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .map(_sortedConversations);
    } on FirebaseException {
      return Stream.value(const <SupportConversation>[]);
    }
  }

  @override
  Stream<SupportConversation?> watchConversation(String conversationId) {
    try {
      return _conversations.doc(conversationId).snapshots().map(
        (doc) => doc.exists ? SupportConversation.fromDoc(doc) : null,
      );
    } on FirebaseException {
      return Stream.value(null);
    }
  }

  @override
  Stream<List<SupportMessage>> watchMessages(String conversationId) {
    try {
      // No orderBy — no index needed; chronological order is
      // done client-side below.
      return _messages(conversationId).snapshots().map((snap) {
        final list = snap.docs.map(SupportMessage.fromDoc).toList();
        list.sort((a, b) {
          final aTime = a.createdAt;
          final bTime = b.createdAt;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return aTime.compareTo(bTime);
        });
        return list;
      });
    } on FirebaseException {
      return Stream.value(const <SupportMessage>[]);
    }
  }

  Future<SupportConversation?> _latestForStudent(String uid) async {
    final snap = await _conversations
        .where('studentUid', isEqualTo: uid)
        .get();
    final list = _sortedConversations(snap);
    return list.isEmpty ? null : list.first;
  }

  Future<SupportConversation> _createThread({
    required String studentUid,
    required String studentName,
  }) async {
    final ref = _conversations.doc();
    final messageRef = ref.collection('messages').doc();
    final batch = _db.batch();
    batch.set(ref, <String, dynamic>{
      'studentUid': studentUid,
      'studentName': studentName,
      'lastMessage': supportGreeting,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSender': 'assistant',
      'unreadForAdmin': 0,
      'unreadForStudent': 0,
      'closed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(messageRef, <String, dynamic>{
      'sender': 'assistant',
      'text': supportGreeting,
      'system': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    final snap = await ref.get();
    return SupportConversation.fromDoc(snap);
  }

  @override
  Future<({SupportConversation conversation, bool isNew})>
  openOrCreateForStudent({
    required String studentUid,
    required String studentName,
  }) async {
    final existing = await _latestForStudent(studentUid);
    if (existing != null) {
      return (conversation: existing, isNew: false);
    }
    final created = await _createThread(
      studentUid: studentUid,
      studentName: studentName,
    );
    return (conversation: created, isNew: true);
  }

  @override
  Future<SupportConversation> createFreshForStudent({
    required String studentUid,
    required String studentName,
  }) {
    return _createThread(
      studentUid: studentUid,
      studentName: studentName,
    );
  }

  Future<void> _updateThread(
    String conversationId,
    Map<String, dynamic> fields,
  ) {
    return _conversations.doc(conversationId).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> sendStudentMessage({
    required SupportConversation conversation,
    required String text,
    SupportTopic? topic,
  }) async {
    final batch = _db.batch();
    batch.set(_messages(conversation.id).doc(), <String, dynamic>{
      'sender': 'student',
      'text': text,
      'system': false,
      if (topic != null) 'topic': supportTopicValue(topic),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_conversations.doc(conversation.id), <String, dynamic>{
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSender': 'student',
      'topic': topic == null ? null : supportTopicValue(topic),
      'unreadForAdmin': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  @override
  Future<String> sendAssistantMessage({
    required SupportConversation conversation,
    required String text,
  }) async {
    final ref = _messages(conversation.id).doc();
    final batch = _db.batch();
    batch.set(ref, <String, dynamic>{
      'sender': 'assistant',
      'text': text,
      'system': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_conversations.doc(conversation.id), <String, dynamic>{
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSender': 'assistant',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return ref.id;
  }

  @override
  Future<void> sendAdminMessage({
    required SupportConversation conversation,
    required String text,
    bool system = false,
  }) async {
    final batch = _db.batch();
    batch.set(_messages(conversation.id).doc(), <String, dynamic>{
      'sender': 'admin',
      'text': text,
      'system': system,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final update = <String, dynamic>{
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSender': 'admin',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!system) {
      update['unreadForStudent'] = FieldValue.increment(1);
    }
    batch.update(_conversations.doc(conversation.id), update);
    await batch.commit();
  }

  @override
  Future<void> markAdminRead(String conversationId) {
    return _conversations.doc(conversationId).update(
      {'unreadForAdmin': 0, 'updatedAt': FieldValue.serverTimestamp()},
    );
  }

  @override
  Future<void> markStudentRead(String conversationId) {
    return _conversations.doc(conversationId).update(
      {'unreadForStudent': 0, 'updatedAt': FieldValue.serverTimestamp()},
    );
  }

  @override
  Future<void> closeConversation(String conversationId) {
    return _updateThread(conversationId, {'closed': true});
  }

  @override
  Future<void> rateConversation(String conversationId, int stars) {
    return _updateThread(conversationId, {'rating': stars});
  }
}
