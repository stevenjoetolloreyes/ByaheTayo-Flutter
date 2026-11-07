// Student Hub data layer — models, local storage, pure helpers,
// and the bundled content sets.
//
// STORAGE: SharedPreferences JSON lists, local-first. There is no
// account backend in this app, so nothing here claims cloud sync.
// Every load/save is best-effort (widget tests run without storage
// and simply get empty lists).
//
// BUNDLED CONTENT HONESTY:
// - Quotes: short attributed quotes from public figures, plus the
//   app's own daily rotation (day-of-year). No network, no invented
//   authors.
// - Bible verses: a CURATED selection in the King James Version,
//   which is public domain. This is NOT the full Bible text —
//   bundling a whole copyrighted translation offline would need a
//   license this app does not have. Book/chapter navigation and
//   search work within this bundled set only.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}${DateTime.now().millisecond}';

// ---------------------------------------------------------------- models

class AllowanceTxn {
  AllowanceTxn({
    required this.id,
    required this.kind, // 'income' | 'expense'
    required this.amount,
    required this.category,
    required this.note,
    required this.date,
  });

  final String id;
  final String kind;
  final double amount;
  final String category;
  final String note;
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'amount': amount,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
      };

  static AllowanceTxn fromJson(Map<String, dynamic> j) => AllowanceTxn(
        id: j['id'] as String,
        kind: j['kind'] as String,
        amount: (j['amount'] as num).toDouble(),
        category: j['category'] as String,
        note: j['note'] as String? ?? '',
        date: DateTime.parse(j['date'] as String),
      );
}

class SavingsGoal {
  SavingsGoal({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
  });

  final String id;
  final String name;
  final double target;
  final double saved;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'target': target, 'saved': saved};

  static SavingsGoal fromJson(Map<String, dynamic> j) => SavingsGoal(
        id: j['id'] as String,
        name: j['name'] as String,
        target: (j['target'] as num).toDouble(),
        saved: (j['saved'] as num).toDouble(),
      );
}

class BudgetLimit {
  BudgetLimit({required this.id, required this.category, required this.limit});

  final String id;
  final String category;
  final double limit;

  Map<String, dynamic> toJson() =>
      {'id': id, 'category': category, 'limit': limit};

  static BudgetLimit fromJson(Map<String, dynamic> j) => BudgetLimit(
        id: j['id'] as String,
        category: j['category'] as String,
        limit: (j['limit'] as num).toDouble(),
      );
}

class Subject {
  Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.teacher,
    required this.room,
    required this.days, // 1 = Monday .. 7 = Sunday (DateTime.weekday)
    required this.startMin,
    required this.endMin,
    required this.color,
  });

  final String id;
  final String name;
  final String code;
  final String teacher;
  final String room;
  final List<int> days;
  final int startMin;
  final int endMin;
  final int color;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'teacher': teacher,
        'room': room,
        'days': days,
        'startMin': startMin,
        'endMin': endMin,
        'color': color,
      };

  static Subject fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        room: j['room'] as String? ?? '',
        days: (j['days'] as List).map((e) => e as int).toList(),
        startMin: j['startMin'] as int,
        endMin: j['endMin'] as int,
        color: j['color'] as int,
      );
}

class AssignmentItem {
  AssignmentItem({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.kind, // 'assignment' | 'exam'
    required this.due,
    required this.done,
  });

  final String id;
  final String subjectId;
  final String title;
  final String kind;
  final DateTime due;
  final bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'title': title,
        'kind': kind,
        'due': due.toIso8601String(),
        'done': done,
      };

  static AssignmentItem fromJson(Map<String, dynamic> j) => AssignmentItem(
        id: j['id'] as String,
        subjectId: j['subjectId'] as String,
        title: j['title'] as String,
        kind: j['kind'] as String,
        due: DateTime.parse(j['due'] as String),
        done: j['done'] as bool? ?? false,
      );
}

/// One recorded grade for a subject (Study tab → Grades, Nov 6,
/// 2026). The app had subjects but no grade storage at all, so the
/// preview's GWA panel had nothing real to compute from — this
/// additive record is the minimum that makes Grades real. Grades
/// are the user's own entries (1.00–5.00, Philippine scale);
/// nothing is seeded, so a fresh install shows GWA "—" and
/// "No grade yet" per subject instead of the preview's sample
/// 1.58 / 8 subjects.
class GradeRecord {
  GradeRecord({
    required this.subjectId,
    required this.grade,
    required this.units,
    required this.semester,
  });

  final String subjectId;

  /// Philippine grade, 1.00 (best) to 5.00 (failed).
  final double grade;

  /// Units the grade counts for in the GWA weighting.
  final int units;

  /// 1 = 1st Semester, 2 = 2nd Semester.
  final int semester;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'grade': grade,
        'units': units,
        'semester': semester,
      };

  static GradeRecord fromJson(Map<String, dynamic> j) => GradeRecord(
        subjectId: j['subjectId'] as String,
        grade: (j['grade'] as num).toDouble(),
        units: (j['units'] as num?)?.toInt() ?? 3,
        semester: (j['semester'] as num?)?.toInt() ?? 1,
      );
}

/// One study file the user added (Study tab → Files). Only
/// metadata is stored — name, size, type, folder — never the file
/// bytes; the file itself stays where the user picked it. Nothing
/// is seeded: the preview's Lectures / Activities / Reviewers
/// folders start at 0 files and the storage bar at 0 B of 5 GB.
class StudyFile {
  StudyFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.kind,
    required this.folder,
    required this.added,
  });

  final String id;
  final String name;

  /// File size in bytes (0 when the picker could not report it).
  final int sizeBytes;

  /// 'pdf' | 'doc' | 'ppt' | 'img' | 'other'.
  final String kind;

  /// 'Lectures' | 'Activities' | 'Reviewers'.
  final String folder;

  final DateTime added;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sizeBytes': sizeBytes,
        'kind': kind,
        'folder': folder,
        'added': added.toIso8601String(),
      };

  static StudyFile fromJson(Map<String, dynamic> j) => StudyFile(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Untitled file',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        kind: j['kind'] as String? ?? 'other',
        folder: j['folder'] as String? ?? 'Lectures',
        added: DateTime.tryParse(j['added'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class Note {
  Note({
    required this.id,
    required this.title,
    required this.subject,
    required this.body,
    required this.favorite,
    required this.updated,
  });

  final String id;
  final String title;
  final String subject;
  final String body;
  final bool favorite;
  final DateTime updated;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'body': body,
        'favorite': favorite,
        'updated': updated.toIso8601String(),
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String,
        subject: j['subject'] as String? ?? '',
        body: j['body'] as String? ?? '',
        favorite: j['favorite'] as bool? ?? false,
        updated: DateTime.parse(j['updated'] as String),
      );
}

class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    required this.subject,
  });

  final String id;
  final String front;
  final String back;
  final String subject;

  Map<String, dynamic> toJson() =>
      {'id': id, 'front': front, 'back': back, 'subject': subject};

  static Flashcard fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String,
        back: j['back'] as String,
        subject: j['subject'] as String? ?? '',
      );
}

class QuizQuestion {
  QuizQuestion({
    required this.type, // 'mcq' | 'tf' | 'id'
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.answer,
    required this.explanation,
  });

  final String type;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String answer;
  final String explanation;

  Map<String, dynamic> toJson() => {
        'type': type,
        'question': question,
        'options': options,
        'correctIndex': correctIndex,
        'answer': answer,
        'explanation': explanation,
      };

  static QuizQuestion fromJson(Map<String, dynamic> j) => QuizQuestion(
        type: j['type'] as String,
        question: j['question'] as String,
        options: (j['options'] as List? ?? []).map((e) => e as String).toList(),
        correctIndex: j['correctIndex'] as int? ?? 0,
        answer: j['answer'] as String? ?? '',
        explanation: j['explanation'] as String? ?? '',
      );
}

class Quiz {
  Quiz({
    required this.id,
    required this.title,
    required this.subject,
    required this.timeLimitSec,
    required this.questions,
  });

  final String id;
  final String title;
  final String subject;
  final int timeLimitSec;
  final List<QuizQuestion> questions;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'timeLimitSec': timeLimitSec,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  static Quiz fromJson(Map<String, dynamic> j) => Quiz(
        id: j['id'] as String,
        title: j['title'] as String,
        subject: j['subject'] as String? ?? '',
        timeLimitSec: j['timeLimitSec'] as int? ?? 0,
        questions: (j['questions'] as List)
            .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class QuizAttempt {
  QuizAttempt({
    required this.id,
    required this.quizTitle,
    required this.score,
    required this.total,
    required this.date,
  });

  final String id;
  final String quizTitle;
  final int score;
  final int total;
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'quizTitle': quizTitle,
        'score': score,
        'total': total,
        'date': date.toIso8601String(),
      };

  static QuizAttempt fromJson(Map<String, dynamic> j) => QuizAttempt(
        id: j['id'] as String,
        quizTitle: j['quizTitle'] as String,
        score: j['score'] as int,
        total: j['total'] as int,
        date: DateTime.parse(j['date'] as String),
      );
}

class AttendanceRecord {
  AttendanceRecord({
    required this.id,
    required this.subject,
    required this.date,
    required this.status, // present|absent|late|excused|half
    required this.note,
    required this.reason,
  });

  final String id;
  final String subject;
  final DateTime date;
  final String status;
  final String note;
  final String reason;

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'date': date.toIso8601String(),
        'status': status,
        'note': note,
        'reason': reason,
      };

  static AttendanceRecord fromJson(Map<String, dynamic> j) =>
      AttendanceRecord(
        id: j['id'] as String,
        subject: j['subject'] as String,
        date: DateTime.parse(j['date'] as String),
        status: j['status'] as String,
        note: j['note'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
      );
}

class CommuteExpense {
  CommuteExpense({
    required this.id,
    required this.routeKey,
    required this.amount,
    required this.date,
    required this.note,
  });

  final String id;
  final String routeKey;
  final double amount;
  final DateTime date;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'routeKey': routeKey,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };

  static CommuteExpense fromJson(Map<String, dynamic> j) => CommuteExpense(
        id: j['id'] as String,
        routeKey: j['routeKey'] as String,
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
        note: j['note'] as String? ?? '',
      );
}

class JournalEntry {
  JournalEntry({
    required this.id,
    required this.kind, // 'devotional' | 'prayer'
    required this.ref,
    required this.text,
    required this.date,
    required this.answered,
  });

  final String id;
  final String kind;
  final String ref;
  final String text;
  final DateTime date;
  final bool answered;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'ref': ref,
        'text': text,
        'date': date.toIso8601String(),
        'answered': answered,
      };

  static JournalEntry fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'] as String,
        kind: j['kind'] as String,
        ref: j['ref'] as String? ?? '',
        text: j['text'] as String,
        date: DateTime.parse(j['date'] as String),
        answered: j['answered'] as bool? ?? false,
      );
}

class QuoteCollection {
  QuoteCollection({required this.name, required this.ids});

  final String name;
  final List<String> ids;

  Map<String, dynamic> toJson() => {'name': name, 'ids': ids};

  static QuoteCollection fromJson(Map<String, dynamic> j) => QuoteCollection(
        name: j['name'] as String,
        ids: (j['ids'] as List).map((e) => e as String).toList(),
      );
}

// ---------------------------------------------------------------- storage

class StudentStorage {
  static const txnsKey = 'byahetayo_student_allowance_txns';
  static const goalsKey = 'byahetayo_student_allowance_goals';
  static const budgetsKey = 'byahetayo_student_allowance_budgets';
  static const subjectsKey = 'byahetayo_student_subjects';
  static const assignmentsKey = 'byahetayo_student_assignments';
  static const notesKey = 'byahetayo_student_notes';
  static const flashcardsKey = 'byahetayo_student_flashcards';
  static const quizzesKey = 'byahetayo_student_quizzes';
  static const attemptsKey = 'byahetayo_student_quiz_attempts';
  static const gradesKey = 'byahetayo_student_grades';
  static const studyFilesKey = 'byahetayo_student_files';
  static const attendanceKey = 'byahetayo_student_attendance';
  static const attendanceGoalKey = 'byahetayo_student_attendance_goal';
  static const quoteFavsKey = 'byahetayo_student_quote_favs';
  static const quoteCollectionsKey = 'byahetayo_student_quote_collections';
  static const quoteHistoryKey = 'byahetayo_student_quote_history';
  static const bibleFavsKey = 'byahetayo_student_bible_favs';
  static const bibleJournalKey = 'byahetayo_student_bible_journal';
  static const biblePlanKey = 'byahetayo_student_bible_plan';
  static const commuteFavsKey = 'byahetayo_student_commute_favs';
  static const commuteExpensesKey = 'byahetayo_student_commute_expenses';
  static const checkinsKey = 'byahetayo_student_checkins';

  static Future<List<Map<String, dynamic>>> loadList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveList(
      String key, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(items));
    } catch (_) {}
  }

  static Future<List<String>> loadStrings(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(key) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveStrings(String key, List<String> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, items);
    } catch (_) {}
  }

  static Future<double> loadDouble(String key, double fallback) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------- pure helpers

String peso(double amount) {
  final fixed = amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final frac = parts[1];
  return '₱${buf.toString()}${frac == '00' ? '' : '.$frac'}';
}

String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final suffix = h >= 12 ? 'PM' : 'AM';
  var h12 = h % 12;
  if (h12 == 0) h12 = 12;
  return '$h12:${m.toString().padLeft(2, '0')} $suffix';
}

String formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String weekdayName(int weekday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[(weekday - 1).clamp(0, 6)];
}

double allowanceBalance(List<AllowanceTxn> txns) {
  var balance = 0.0;
  for (final t in txns) {
    balance += t.kind == 'income' ? t.amount : -t.amount;
  }
  return balance;
}

({double income, double expense}) monthTotals(
    List<AllowanceTxn> txns, int year, int month) {
  var income = 0.0;
  var expense = 0.0;
  for (final t in txns) {
    if (t.date.year == year && t.date.month == month) {
      if (t.kind == 'income') {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
  }
  return (income: income, expense: expense);
}

/// Last [count] months of expenses, oldest first, for the bar chart.
List<({String label, double amount})> lastMonthsExpense(
    List<AllowanceTxn> txns, DateTime now, int count) {
  final out = <({String label, double amount})>[];
  for (var i = count - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i, 1);
    final totals = monthTotals(txns, month.year, month.month);
    const short = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    out.add((label: short[month.month - 1], amount: totals.expense));
  }
  return out;
}

/// Returns the name of the first conflicting subject, or null.
/// Conflict = same weekday + overlapping [startMin, endMin).
String? findConflict(List<Subject> subjects, Subject candidate,
    {String? excludeId}) {
  for (final s in subjects) {
    if (s.id == excludeId) continue;
    for (final day in candidate.days) {
      if (!s.days.contains(day)) continue;
      if (candidate.startMin < s.endMin && s.startMin < candidate.endMin) {
        return s.name;
      }
    }
  }
  return null;
}

List<Subject> classesOnDay(List<Subject> subjects, int weekday) {
  final list = subjects.where((s) => s.days.contains(weekday)).toList();
  list.sort((a, b) => a.startMin.compareTo(b.startMin));
  return list;
}

/// Next upcoming class: later today first, then the next day that has
/// classes. Returns null when there are no subjects at all.
({Subject subject, DateTime date})? nextClass(
    List<Subject> subjects, DateTime now) {
  if (subjects.isEmpty) return null;
  final nowMin = now.hour * 60 + now.minute;
  for (var offset = 0; offset < 7; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final todays = classesOnDay(subjects, day.weekday);
    for (final s in todays) {
      if (offset == 0 && s.startMin <= nowMin) continue;
      return (subject: s, date: day);
    }
  }
  return null;
}

({int total, int present, int absent, int late, int excused, int half, double percent})
attendanceStats(List<AttendanceRecord> records) {
  var present = 0;
  var absent = 0;
  var late = 0;
  var excused = 0;
  var half = 0;
  for (final r in records) {
    switch (r.status) {
      case 'present':
        present++;
        break;
      case 'absent':
        absent++;
        break;
      case 'late':
        late++;
        break;
      case 'excused':
        excused++;
        break;
      case 'half':
        half++;
        break;
    }
  }
  final total = records.length;
  // Present% = full presents + lates + half of half-days, over all
  // records except excused ones (excused absences don't count
  // against attendance). 0 when there is nothing to rate.
  final denom = total - excused;
  final percent = denom <= 0
      ? 0.0
      : (present + late + half * 0.5) / denom * 100;
  return (
    total: total,
    present: present,
    absent: absent,
    late: late,
    excused: excused,
    half: half,
    percent: percent,
  );
}

/// Score a quiz: MCQ/TF by selected index, identification by
/// case-insensitive trimmed text match.
int scoreQuiz(Quiz quiz, List<int> selected, List<String> typed) {
  var score = 0;
  for (var i = 0; i < quiz.questions.length; i++) {
    final q = quiz.questions[i];
    if (q.type == 'id') {
      final given = i < typed.length ? typed[i].trim().toLowerCase() : '';
      if (given.isNotEmpty && given == q.answer.trim().toLowerCase()) {
        score++;
      }
    } else {
      if (i < selected.length && selected[i] == q.correctIndex) score++;
    }
  }
  return score;
}

int dayOfYear(DateTime d) {
  return DateTime(d.year, d.month, d.day)
          .difference(DateTime(d.year, 1, 1))
          .inDays +
      1;
}

String csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String toCsv(List<List<String>> rows) {
  return rows.map((r) => r.map(csvEscape).join(',')).join('\n');
}

// ---------------------------------------------------------------- bundled quotes

class BundledQuote {
  const BundledQuote({
    required this.id,
    required this.text,
    required this.author,
    required this.category,
  });

  final String id;
  final String text;
  final String author;
  final String category;
}

const quoteCategories = [
  'Inspirational',
  'Motivational',
  'Education & Success',
  'Faith & Positivity',
  'Love & Friendship',
];

const bundledQuotes = [
  BundledQuote(
      id: 'q01',
      text: 'Education is the most powerful weapon which you can use to change the world.',
      author: 'Nelson Mandela',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q02',
      text: 'The future belongs to those who believe in the beauty of their dreams.',
      author: 'Eleanor Roosevelt',
      category: 'Inspirational'),
  BundledQuote(
      id: 'q03',
      text: "It always seems impossible until it's done.",
      author: 'Nelson Mandela',
      category: 'Motivational'),
  BundledQuote(
      id: 'q04',
      text: 'The only way to do great work is to love what you do.',
      author: 'Steve Jobs',
      category: 'Motivational'),
  BundledQuote(
      id: 'q05',
      text: 'Success is not final, failure is not fatal: it is the courage to continue that counts.',
      author: 'Winston Churchill',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q06',
      text: "Believe you can and you're halfway there.",
      author: 'Theodore Roosevelt',
      category: 'Motivational'),
  BundledQuote(
      id: 'q07',
      text: 'It does not matter how slowly you go as long as you do not stop.',
      author: 'Confucius',
      category: 'Motivational'),
  BundledQuote(
      id: 'q08',
      text: 'Do what you can, with what you have, where you are.',
      author: 'Theodore Roosevelt',
      category: 'Inspirational'),
  BundledQuote(
      id: 'q09',
      text: 'Learning never exhausts the mind.',
      author: 'Leonardo da Vinci',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q10',
      text: 'The journey of a thousand miles begins with one step.',
      author: 'Lao Tzu',
      category: 'Inspirational'),
  BundledQuote(
      id: 'q11',
      text: 'Knowledge is power.',
      author: 'Francis Bacon',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q12',
      text: 'An investment in knowledge pays the best interest.',
      author: 'Benjamin Franklin',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q13',
      text: "Faith is taking the first step even when you don't see the whole staircase.",
      author: 'Martin Luther King Jr.',
      category: 'Faith & Positivity'),
  BundledQuote(
      id: 'q14',
      text: 'A friend is someone who knows all about you and still loves you.',
      author: 'Elbert Hubbard',
      category: 'Love & Friendship'),
  BundledQuote(
      id: 'q15',
      text: 'Friendship is the only cement that will ever hold the world together.',
      author: 'Woodrow Wilson',
      category: 'Love & Friendship'),
  BundledQuote(
      id: 'q16',
      text: 'The harder I work, the luckier I get.',
      author: 'Samuel Goldwyn',
      category: 'Motivational'),
  BundledQuote(
      id: 'q17',
      text: "Don't watch the clock; do what it does. Keep going.",
      author: 'Sam Levenson',
      category: 'Motivational'),
  BundledQuote(
      id: 'q18',
      text: 'The secret of getting ahead is getting started.',
      author: 'Mark Twain',
      category: 'Motivational'),
  BundledQuote(
      id: 'q19',
      text: 'Education is not preparation for life; education is life itself.',
      author: 'John Dewey',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q20',
      text: 'Live as if you were to die tomorrow. Learn as if you were to live forever.',
      author: 'Mahatma Gandhi',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q21',
      text: 'The mind is not a vessel to be filled, but a fire to be kindled.',
      author: 'Plutarch',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q22',
      text: 'Hope is being able to see that there is light despite all of the darkness.',
      author: 'Desmond Tutu',
      category: 'Faith & Positivity'),
  BundledQuote(
      id: 'q23',
      text: 'Faith is the strength by which a shattered world shall emerge into the light.',
      author: 'Helen Keller',
      category: 'Faith & Positivity'),
  BundledQuote(
      id: 'q24',
      text: 'No one can make you feel inferior without your consent.',
      author: 'Eleanor Roosevelt',
      category: 'Inspirational'),
  BundledQuote(
      id: 'q25',
      text: 'The best and most beautiful things in the world cannot be seen or even touched — they must be felt with the heart.',
      author: 'Helen Keller',
      category: 'Love & Friendship'),
  BundledQuote(
      id: 'q26',
      text: 'To love and be loved is to feel the sun from both sides.',
      author: 'David Viscott',
      category: 'Love & Friendship'),
  BundledQuote(
      id: 'q27',
      text: 'Success usually comes to those who are too busy to be looking for it.',
      author: 'Henry David Thoreau',
      category: 'Education & Success'),
  BundledQuote(
      id: 'q28',
      text: 'The best way to predict the future is to create it.',
      author: 'Abraham Lincoln',
      category: 'Inspirational'),
  BundledQuote(
      id: 'q29',
      text: 'A true friend is one who overlooks your failures and tolerates your success.',
      author: 'Doug Larson',
      category: 'Love & Friendship'),
  BundledQuote(
      id: 'q30',
      text: 'What we achieve inwardly will change outer reality.',
      author: 'Plutarch',
      category: 'Inspirational'),
];

BundledQuote quoteOfDay(DateTime date) {
  return bundledQuotes[(dayOfYear(date) - 1) % bundledQuotes.length];
}

// ---------------------------------------------------------------- bundled verses

class BundledVerse {
  const BundledVerse({
    required this.id,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.topics,
  });

  final String id;
  final String book;
  final int chapter;
  final String verse;
  final String text;
  final List<String> topics;

  String get ref => '$book $chapter:$verse';
}

const verseTopics = [
  'Faith',
  'Hope',
  'Love',
  'Strength',
  'Peace',
  'Guidance',
  'Gratitude',
];

const bundledVerses = [
  BundledVerse(
      id: 'v01',
      book: 'John',
      chapter: 3,
      verse: '16',
      text: 'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
      topics: ['Faith', 'Love']),
  BundledVerse(
      id: 'v02',
      book: 'Psalm',
      chapter: 23,
      verse: '1',
      text: 'The LORD is my shepherd; I shall not want.',
      topics: ['Peace', 'Guidance']),
  BundledVerse(
      id: 'v03',
      book: 'Philippians',
      chapter: 4,
      verse: '13',
      text: 'I can do all things through Christ which strengtheneth me.',
      topics: ['Strength']),
  BundledVerse(
      id: 'v04',
      book: 'Jeremiah',
      chapter: 29,
      verse: '11',
      text: 'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.',
      topics: ['Hope', 'Guidance']),
  BundledVerse(
      id: 'v05',
      book: 'Proverbs',
      chapter: 3,
      verse: '5-6',
      text: 'Trust in the LORD with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths.',
      topics: ['Guidance', 'Faith']),
  BundledVerse(
      id: 'v06',
      book: 'Isaiah',
      chapter: 41,
      verse: '10',
      text: 'Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee; yea, I will uphold thee with the right hand of my righteousness.',
      topics: ['Strength', 'Peace']),
  BundledVerse(
      id: 'v07',
      book: 'Romans',
      chapter: 8,
      verse: '28',
      text: 'And we know that all things work together for good to them that love God, to them who are the called according to his purpose.',
      topics: ['Hope', 'Faith']),
  BundledVerse(
      id: 'v08',
      book: 'Joshua',
      chapter: 1,
      verse: '9',
      text: 'Have not I commanded thee? Be strong and of a good courage; be not afraid, neither be thou dismayed: for the LORD thy God is with thee whithersoever thou goest.',
      topics: ['Strength']),
  BundledVerse(
      id: 'v09',
      book: 'Matthew',
      chapter: 11,
      verse: '28',
      text: 'Come unto me, all ye that labour and are heavy laden, and I will give you rest.',
      topics: ['Peace']),
  BundledVerse(
      id: 'v10',
      book: 'Psalm',
      chapter: 46,
      verse: '1',
      text: 'God is our refuge and strength, a very present help in trouble.',
      topics: ['Strength', 'Peace']),
  BundledVerse(
      id: 'v11',
      book: 'Matthew',
      chapter: 5,
      verse: '16',
      text: 'Let your light so shine before men, that they may see your good works, and glorify your Father which is in heaven.',
      topics: ['Faith']),
  BundledVerse(
      id: 'v12',
      book: '1 Corinthians',
      chapter: 13,
      verse: '4',
      text: 'Charity suffereth long, and is kind; charity envieth not; charity vaunteth not itself, is not puffed up,',
      topics: ['Love']),
  BundledVerse(
      id: 'v13',
      book: 'Romans',
      chapter: 12,
      verse: '12',
      text: 'Rejoicing in hope; patient in tribulation; continuing instant in prayer;',
      topics: ['Hope', 'Faith']),
  BundledVerse(
      id: 'v14',
      book: 'Philippians',
      chapter: 4,
      verse: '6',
      text: 'Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God;',
      topics: ['Peace']),
  BundledVerse(
      id: 'v15',
      book: 'Psalm',
      chapter: 37,
      verse: '4',
      text: 'Delight thyself also in the LORD; and he shall give thee the desires of thine heart.',
      topics: ['Hope']),
  BundledVerse(
      id: 'v16',
      book: 'Matthew',
      chapter: 6,
      verse: '33',
      text: 'But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you.',
      topics: ['Guidance']),
  BundledVerse(
      id: 'v17',
      book: 'Isaiah',
      chapter: 40,
      verse: '31',
      text: 'But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.',
      topics: ['Strength', 'Hope']),
  BundledVerse(
      id: 'v18',
      book: '2 Timothy',
      chapter: 1,
      verse: '7',
      text: 'For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind.',
      topics: ['Strength']),
  BundledVerse(
      id: 'v19',
      book: 'Psalm',
      chapter: 119,
      verse: '105',
      text: 'Thy word is a lamp unto my feet, and a light unto my path.',
      topics: ['Guidance']),
  BundledVerse(
      id: 'v20',
      book: 'Proverbs',
      chapter: 16,
      verse: '3',
      text: 'Commit thy works unto the LORD, and thy thoughts shall be established.',
      topics: ['Guidance']),
  BundledVerse(
      id: 'v21',
      book: 'Lamentations',
      chapter: 3,
      verse: '22-23',
      text: "It is of the LORD'S mercies that we are not consumed, because his compassions fail not. They are new every morning: great is thy faithfulness.",
      topics: ['Hope', 'Gratitude']),
  BundledVerse(
      id: 'v22',
      book: '1 Thessalonians',
      chapter: 5,
      verse: '18',
      text: 'In every thing give thanks: for this is the will of God in Christ Jesus concerning you.',
      topics: ['Gratitude']),
  BundledVerse(
      id: 'v23',
      book: 'Psalm',
      chapter: 100,
      verse: '4',
      text: 'Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name.',
      topics: ['Gratitude']),
  BundledVerse(
      id: 'v24',
      book: 'Colossians',
      chapter: 3,
      verse: '23',
      text: 'And whatsoever ye do, do it heartily, as to the Lord, and not unto men;',
      topics: ['Faith']),
  BundledVerse(
      id: 'v25',
      book: 'James',
      chapter: 1,
      verse: '5',
      text: 'If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him.',
      topics: ['Guidance']),
  BundledVerse(
      id: 'v26',
      book: 'Matthew',
      chapter: 7,
      verse: '7',
      text: 'Ask, and it shall be given you; seek, and ye shall find; knock, and it shall be opened unto you:',
      topics: ['Faith']),
  BundledVerse(
      id: 'v27',
      book: 'Hebrews',
      chapter: 11,
      verse: '1',
      text: 'Now faith is the substance of things hoped for, the evidence of things not seen.',
      topics: ['Faith']),
  BundledVerse(
      id: 'v28',
      book: 'Psalm',
      chapter: 27,
      verse: '1',
      text: 'The LORD is my light and my salvation; whom shall I fear? the LORD is the strength of my life; of whom shall I be afraid?',
      topics: ['Strength']),
  BundledVerse(
      id: 'v29',
      book: 'Romans',
      chapter: 15,
      verse: '13',
      text: 'Now the God of hope fill you with all joy and peace in believing, that ye may abound in hope, through the power of the Holy Ghost.',
      topics: ['Hope', 'Peace']),
  BundledVerse(
      id: 'v30',
      book: '1 Peter',
      chapter: 5,
      verse: '7',
      text: 'Casting all your care upon him; for he careth for you.',
      topics: ['Peace']),
];

BundledVerse verseOfDay(DateTime date) {
  return bundledVerses[(dayOfYear(date) - 1) % bundledVerses.length];
}

/// 7-day reading plan: each day pairs a theme with two bundled verses.
const biblePlanDays = [
  ('Day 1 · Trust', ['v05', 'v26']),
  ('Day 2 · Strength', ['v03', 'v17']),
  ('Day 3 · Peace', ['v09', 'v30']),
  ('Day 4 · Hope', ['v04', 'v21']),
  ('Day 5 · Guidance', ['v19', 'v25']),
  ('Day 6 · Love', ['v01', 'v12']),
  ('Day 7 · Gratitude', ['v22', 'v23']),
];

BundledVerse? findVerse(String id) {
  for (final v in bundledVerses) {
    if (v.id == id) return v;
  }
  return null;
}

/// One daily sign-in record. This is SEPARATE from the Attendance
/// Sheet (class attendance): a sign-in is a daily app check-in that
/// earns local points. Dates are calendar dates on the device
/// (Asia/Manila for this user); the daily reset is simply "a new
/// calendar date has no record yet".
class CheckinRecord {
  CheckinRecord({
    required this.id,
    required this.date,
    required this.dayIndex,
    required this.points,
  });

  final String id;
  final DateTime date;
  final int dayIndex; // 1..7 within the current 7-day cycle.
  final int points;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': dateKey(date),
        'dayIndex': dayIndex,
        'points': points,
      };

  factory CheckinRecord.fromJson(Map<String, dynamic> json) {
    final parts = (json['date'] as String? ?? '').split('-');
    return CheckinRecord(
      id: json['id'] as String? ?? newId(),
      date: parts.length == 3
          ? DateTime(int.parse(parts[0]), int.parse(parts[1]),
              int.parse(parts[2]))
          : DateTime.now(),
      dayIndex: (json['dayIndex'] as int? ?? 1).clamp(1, 7),
      points: json['points'] as int? ?? 0,
    );
  }
}

/// Local calendar-date key, 'YYYY-MM-DD'. All streak math uses these
/// keys, so a day boundary is exact and timezone-free on-device.
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// True when a check-in record exists for [today]'s calendar date.
/// This is the duplicate guard: one check-in per day, enforced both
/// in the UI (button hidden) and in the save handler (re-checked).
bool hasCheckedInToday(List<CheckinRecord> records, DateTime today) {
  final key = dateKey(today);
  return records.any((r) => dateKey(r.date) == key);
}

/// Consecutive-day streak ending today (if checked in today) or
/// yesterday (if not yet). A missed day breaks the streak to 0.
int checkinStreak(List<CheckinRecord> records, DateTime today) {
  final days = records.map((r) => dateKey(r.date)).toSet();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(dateKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (days.contains(dateKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Day index for the NEXT check-in, given the current [streak].
/// Day 7 completes a cycle; the check-in after that starts a new one.
int nextCycleDay(int streak) => (streak % 7) + 1;

/// How many cells of the current 7-day cycle are already checked.
/// A streak that just completed a cycle (multiple of 7) shows all 7.
int cycleCheckedCount(int streak) {
  if (streak <= 0) return 0;
  final mod = streak % 7;
  return mod == 0 ? 7 : mod;
}

/// Reward points for a cycle day: 10 per day, 50 on Day 7
/// (the completion reward). Totals are always re-derived from the
/// record log (see [totalCheckinPoints]), never from a stored
/// counter that could drift.
int pointsForDay(int dayIndex) => dayIndex == 7 ? 50 : 10;

/// How many cells of the CURRENT 7-day cycle are already checked.
/// When today is already checked in, the streak includes today (a
/// just-completed cycle shows all 7). When not, a streak that ended
/// on a completed cycle means today starts a fresh cycle (0 cells).
int currentCycleChecked(List<CheckinRecord> records, DateTime today) {
  final streak = checkinStreak(records, today);
  if (hasCheckedInToday(records, today)) {
    return cycleCheckedCount(streak);
  }
  return streak % 7;
}

/// Total points ever earned from check-ins, computed from the log.
int totalCheckinPoints(List<CheckinRecord> records) {
  var sum = 0;
  for (final r in records) {
    sum += r.points;
  }
  return sum;
}
