// Tasks / To-do home screen widgets — Dart side (Android only).
//
// DESIGN (why this shape): like the Schedule widget
// (schedule_widget_service.dart), the Dart side pushes the
// student's tasks as ONE JSON blob and the Kotlin providers
// render from it on every update (updatePeriodMillis 30 min). The
// single source of truth stays the app's stored assignments — the
// SAME SharedPreferences list the Classes screen reads
// (StudentStorage.assignmentsKey), with subject names resolved
// from the SAME stored subjects list (StudentStorage.subjectsKey).
// Nothing here re-lists tasks, so an add, a check-off, or a
// delete flows to the widget with the next sync call.
//
// REAL TASKS ONLY: the approved preview v1 (Nov 11, 2026) showed
// SAMPLE tasks on the 3x3 and 4x3 sizes ("2 of 5 done"). The
// widget shows the REAL stored assignments — pending first,
// due-date order (the same order the Classes screen sorts by) —
// and an honest empty state ("0 pending", "No pending tasks.")
// when there are none. No assignment, due date, or subject is
// ever invented. Done tasks are counted ("N of M done") and
// listed after the pending ones, muted; the preview's
// collapsible Completed section has no widget equivalent, so the
// big size shows the done count as a footer line instead.
//
// TAP: tapping any size opens the app's Classes screen (where
// tasks live). The Kotlin providers launch the app with the
// `homewidget://tasks` URI (HomeWidgetLaunchIntent) and the app
// root listens for it (see _EstudyanteGOAppState in main.dart) —
// only when the dashboard is showing (signed in, profile done);
// on the sign-in or setup screens the tap just opens the app.
//
// The push is best-effort and never throws: widget tests run
// without the plugin, and the Classes screen must never break
// because the widget plugin is unavailable. The provider shows
// the honest empty state ("0 pending", "No pending tasks.")
// when no task data has been pushed yet.
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'student_data.dart';

/// One task as the widget understands it: title + kind + due date
/// + done + the subject's display name (resolved at encode time
/// from the stored subjects — the same lookup the Classes screen
/// uses for its rows).
class TasksWidgetTask {
  const TasksWidgetTask({
    required this.id,
    required this.title,
    required this.kind,
    required this.due,
    required this.done,
    required this.subjectName,
  });

  factory TasksWidgetTask.fromAssignment(
    AssignmentItem item,
    String subjectName,
  ) =>
      TasksWidgetTask(
        id: item.id,
        title: item.title,
        kind: item.kind,
        due: item.due,
        done: item.done,
        subjectName: subjectName,
      );

  factory TasksWidgetTask.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final kind = json['kind'];
    final due = json['due'];
    final done = json['done'];
    final subjectName = json['subjectName'];
    if (id is! String ||
        title is! String ||
        kind is! String ||
        due is! String ||
        done is! bool ||
        subjectName is! String) {
      throw const FormatException('Tasks widget task is malformed');
    }
    return TasksWidgetTask(
      id: id,
      title: title,
      kind: kind,
      due: DateTime.parse(due),
      done: done,
      subjectName: subjectName,
    );
  }

  final String id;
  final String title;

  /// 'assignment' | 'exam' (same values as AssignmentItem.kind).
  final String kind;
  final DateTime due;
  final bool done;

  /// Display name of the task's subject ("Introduction to
  /// Computing"), or '' when the subject is unknown — the
  /// provider then shows the kind only.
  final String subjectName;

  /// "Assignment" / "Exam" — the row subtitle label, same words
  /// as the Classes screen's rows.
  String get kindLabel => kind == 'exam' ? 'Exam' : 'Assignment';

  /// "Nov 12, 2026" — the due date as the Classes screen shows
  /// it (formatDate).
  String get dueLabel => formatDate(due);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'due': due.toIso8601String(),
        'done': done,
        'subjectName': subjectName,
      };

  @override
  bool operator ==(Object other) =>
      other is TasksWidgetTask &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.due == due &&
      other.done == done &&
      other.subjectName == subjectName;

  @override
  int get hashCode =>
      Object.hash(id, title, kind, due, done, subjectName);
}

/// The whole tasks payload the providers read.
class TasksWidgetData {
  const TasksWidgetData({this.tasks = const []});

  factory TasksWidgetData.fromJson(Map<String, dynamic> json) {
    final tasks = json['tasks'];
    if (tasks is! List) {
      throw const FormatException('Tasks widget data is malformed');
    }
    return TasksWidgetData(
      tasks: tasks
          .map((e) => TasksWidgetTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<TasksWidgetTask> tasks;

  /// Not-done tasks, due-date order (the payload is stored in
  /// that order already; this is the provider-facing view).
  List<TasksWidgetTask> get pending =>
      tasks.where((t) => !t.done).toList();

  /// Done tasks, due-date order.
  List<TasksWidgetTask> get completed =>
      tasks.where((t) => t.done).toList();

  int get pendingCount => pending.length;

  /// "2 of 5 done" — the big widget's footer line.
  String get doneLine =>
      '${completed.length} of ${tasks.length} done';

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is TasksWidgetData && _tasksEqual(other.tasks, tasks);

  @override
  int get hashCode => Object.hashAll(tasks);
}

bool _tasksEqual(List<TasksWidgetTask> a, List<TasksWidgetTask> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class TasksWidgetService {
  TasksWidgetService._();

  /// SharedPreferences key (inside the home_widget store) holding
  /// the tasks JSON all three providers read.
  static const String dataKey = 'tasks_widget_data';

  /// Small 4x2 provider.
  static const String providerName = 'TasksWidgetProvider';
  static const String providerQualifiedName =
      'com.estudyantego.app.TasksWidgetProvider';

  /// Square 3x3 provider.
  static const String squareProviderName = 'TasksSquareWidgetProvider';
  static const String squareProviderQualifiedName =
      'com.estudyantego.app.TasksSquareWidgetProvider';

  /// Big 4x3 provider.
  static const String largeProviderName = 'TasksLargeWidgetProvider';
  static const String largeProviderQualifiedName =
      'com.estudyantego.app.TasksLargeWidgetProvider';

  /// URI the providers launch with on tap. The app root listens
  /// for it (HomeWidget.widgetClicked /
  /// initiallyLaunchedFromHomeWidget) and opens the Classes
  /// screen when the dashboard is showing.
  static const String tasksUri = 'homewidget://tasks';

  /// Shown by the providers when there are no pending tasks.
  /// (The Kotlin side carries the same wording; keep them in
  /// sync.)
  static const String emptyTitle = 'No pending tasks.';
  static const String emptySubtitle = 'Add a task to get started.';

  /// How many tasks the payload carries at most (pending first,
  /// then done, due-date order); more than that renders as
  /// "+N more".
  static const int maxTasks = 8;

  /// How many pending tasks each size lists at most.
  static const int smallListCount = 2;
  static const int squareListCount = 4;
  static const int largeListCount = 5;

  /// Pure: resolves a task's subject display name from the stored
  /// subjects — the same lookup the Classes screen uses
  /// (_subjectName: code when present, else name, else ''). The
  /// widget shows the subject NAME (not the code) so the row
  /// reads like the Classes rows' subtitle.
  static String subjectNameFor(List<Subject> subjects, String subjectId) {
    for (final s in subjects) {
      if (s.id == subjectId) return s.name;
    }
    return '';
  }

  /// Pure: encodes the widget payload from the app's stored
  /// assignments + subjects. Pending first (due-date order),
  /// then done (due-date order) — the same due-date sort the
  /// Classes screen applies on load.
  static String encodeData(
    List<AssignmentItem> items,
    List<Subject> subjects,
  ) {
    final sorted = List.of(items)
      ..sort((a, b) => a.due.compareTo(b.due));
    final pending =
        sorted.where((i) => !i.done).toList();
    final done = sorted.where((i) => i.done).toList();
    final ordered = [...pending, ...done].take(maxTasks).toList();
    return jsonEncode(TasksWidgetData(
      tasks: ordered
          .map((i) => TasksWidgetTask.fromAssignment(
              i, subjectNameFor(subjects, i.subjectId)))
          .toList(),
    ).toJson());
  }

  /// Decodes a pushed payload. Returns null for null, empty,
  /// non-map, or malformed JSON — the provider treats that as "no
  /// data yet" and shows the empty state, never a crash.
  static TasksWidgetData? decodeData(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return TasksWidgetData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Pushes the student's current tasks to the widget store, then
  /// asks all THREE providers to refresh. The payload is written
  /// in ONE saveWidgetData call, so a refresh can never leave one
  /// widget showing new tasks with old counts. Best-effort: never
  /// throws, so callers (Classes screen saves, app start) can
  /// fire-and-forget it.
  static Future<void> sync() async {
    try {
      final items = (await StudentStorage.loadList(
              StudentStorage.assignmentsKey))
          .map(AssignmentItem.fromJson)
          .toList();
      final subjects = (await StudentStorage.loadList(
              StudentStorage.subjectsKey))
          .map(Subject.fromJson)
          .toList();
      await HomeWidget.saveWidgetData<String>(
          dataKey, encodeData(items, subjects));
      await HomeWidget.updateWidget(
        androidName: providerName,
        qualifiedAndroidName: providerQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: squareProviderName,
        qualifiedAndroidName: squareProviderQualifiedName,
      );
      await HomeWidget.updateWidget(
        androidName: largeProviderName,
        qualifiedAndroidName: largeProviderQualifiedName,
      );
    } catch (_) {
      // No widget plugin (tests, iOS) or a platform failure: the
      // Classes screen and app start must keep working either way.
    }
  }
}
