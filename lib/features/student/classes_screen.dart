// Classes & Timetable — subject schedule manager (local only).
//
// Conflict detection blocks saving a subject that overlaps another
// subject on the same weekday. "Reminders" surface as the Upcoming
// section in-app, and — since the Nov 8 local notifications build
// — as scheduled system notifications too: every save re-runs the
// notification schedule (see local_notifications.dart).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../onboarding/splash_sound.dart';
import '../top_popup.dart';

import '../app_layout.dart';
import '../local_notifications.dart';
import '../minecraft_tap_animation.dart';
import '../minecraft_theme.dart';
import 'classes_plus_menu.dart';
import 'google_calendar_sync.dart';
import 'google_events.dart';
import 'schedule_scan.dart';
import 'schedule_widget_service.dart';
import 'student_data.dart';
import 'tasks_widget_service.dart';

const _subjectColors = [
  0xFF16A34A,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFEA580C,
  0xFFDB2777,
  0xFF0D9488,
  0xFFDC2626,
  0xFFCA8A04,
];

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({
    super.key,
    this.onPlacementChime,
    this.filesScanner,
    this.googleSync,
  });

  /// Test hook for the class-placement chime (Feature 2): when
  /// provided, a newly placed class calls this instead of
  /// [SplashSound.placeClass], so widget tests can assert the
  /// placement trigger fired without playing audio. Production
  /// call sites leave it null and the real chime plays.
  final VoidCallback? onPlacementChime;

  /// Test hook for the Files scan (Feature 3): when provided, the
  /// scan uses this scanner (fake picker / extractor) instead of
  /// the real [ScheduleFileScanner]. Production call sites leave
  /// it null.
  final ScheduleFileScanner? filesScanner;

  /// Test hook for the Google Schedule sync (Feature 4): when
  /// provided, the sync uses this service (fake connect / fetch)
  /// instead of the real [GoogleCalendarSync]. Production call
  /// sites leave it null.
  final GoogleCalendarSync? googleSync;

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen>
    with SingleTickerProviderStateMixin {
  List<Subject> _subjects = [];
  List<AssignmentItem> _items = [];

  /// Synced Google Calendar events (mock sync — the sample set,
  /// stored locally; same stored set the Hub card renders).
  List<GoogleCalendarEvent> _googleEvents = [];
  String _view = 'today';

  /// Id of the class most recently placed into the timetable
  /// (Feature 2): its tile springs in once via [_PlacedSpringIn],
  /// which clears this id when the animation finishes. Null the
  /// rest of the time, so no other tile ever animates.
  String? _justPlacedId;

  /// Classes placed by the Files scan this session (Feature 3):
  /// their tiles carry a "New" badge until the screen is left.
  final Set<String> _scannedNewIds = {};

  /// Id of the scanned class currently springing in (Feature 3):
  /// its tile springs in once via [_ScannedSpringIn] — spring +
  /// green flash + popping avatar — which clears this id when the
  /// animation finishes. Only one scanned tile animates at a time;
  /// the rest keep their "New" badge and render plainly.
  String? _justScannedId;

  /// A Files scan is running (picker / extraction / placement):
  /// a second Files tap while this is true is ignored, so two
  /// scans can never interleave their placements.
  bool _scanInProgress = false;

  /// Classes placed by the Google Calendar sync this session
  /// (Feature 4): their tiles carry a "New" badge until the
  /// screen is left.
  final Set<String> _syncedNewIds = {};

  /// Id of the synced Google event currently springing in
  /// (Feature 4): its tile springs in once via
  /// [_ScannedSpringIn] — spring + green flash + popping G badge
  /// — which clears this id when the animation finishes. Only one
  /// synced tile animates at a time; the rest keep their "New"
  /// badge and render plainly.
  String? _justSyncedGoogleId;

  /// A Google Calendar sync is running (connect / fetch /
  /// placement): a second Google Schedule tap while this is true
  /// is ignored, so two syncs can never interleave their
  /// placements.
  bool _googleSyncInProgress = false;

  /// The "+" menu (Feature 1): [_menuOpen] owns whether the menu is
  /// in the tree; [_menuController] (0 = closed, 1 = open) drives
  /// the menu spring, the staggered options, and the + button's
  /// squash-bounce + rotate-to-x. No sound on open/close — sound
  /// plays only when a class is placed (Features 2-4).
  bool _menuOpen = false;
  late final AnimationController _menuController;
  late final Animation<double> _fabScale;
  late final Animation<double> _fabTurns;

  @override
  void initState() {
    super.initState();
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    // Squash-bounce: the + dips to 0.84, then springs back past 1
    // (elastic overshoot) and settles. Plays in reverse on close.
    _fabScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.84), weight: 30),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.84,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]).animate(_menuController);
    // + rotates 45 degrees into an x while the menu is open.
    _fabTurns = Tween<double>(begin: 0.0, end: 0.125).animate(
      CurvedAnimation(parent: _menuController, curve: Curves.easeInOut),
    );
    _load();
  }

  @override
  void dispose() {
    _menuController.dispose();
    super.dispose();
  }

  bool get _reducedMotion => MediaQuery.of(context).disableAnimations;

  void _openMenu() {
    setState(() => _menuOpen = true);
    if (_reducedMotion) {
      // Reduced motion: instant show, no spring/wobble/stagger.
      _menuController.value = 1.0;
    } else {
      // Underdamped spring: rises, overshoots ~17%, wobbles once,
      // then settles (damping ratio ~0.5).
      _menuController.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1.0, stiffness: 260.0, damping: 16.0),
          0.0,
          1.0,
          0.0,
        ),
      );
    }
  }

  Future<void> _closeMenu() async {
    if (_reducedMotion) {
      _menuController.value = 0.0;
      if (mounted) setState(() => _menuOpen = false);
      return;
    }
    await _menuController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeIn,
    );
    if (mounted) setState(() => _menuOpen = false);
  }

  void _toggleMenu() {
    if (_menuOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  Future<void> _load() async {
    final subjects = await StudentStorage.loadList(StudentStorage.subjectsKey);
    final items = await StudentStorage.loadList(StudentStorage.assignmentsKey);
    final googleEvents = await loadGoogleEvents();
    if (!mounted) return;
    setState(() {
      _subjects = subjects.map(Subject.fromJson).toList();
      _googleEvents = googleEvents;
      _items = items.map(AssignmentItem.fromJson).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
    });
    // Refresh the Schedule home screen widgets from the stored
    // schedule (best-effort, never blocks this screen).
    unawaited(ScheduleWidgetService.sync());
  }

  /// Google-event tap (its list card): the Edit / Remove sheet.
  /// Edits and removals save locally and re-render this screen;
  /// the Hub reloads the same stored set when it opens.
  Future<void> _onGoogleEventTap(GoogleCalendarEvent event) async {
    await showGoogleEventActionSheet(
      context,
      event: event,
      onUpdated: (updated) async {
        setState(() {
          final i = _googleEvents.indexWhere((e) => e.id == updated.id);
          if (i >= 0) _googleEvents[i] = updated;
        });
        await saveGoogleEvents(_googleEvents);
        unawaited(ScheduleWidgetService.sync());
      },
      onRemoved: (removed) async {
        setState(() => _googleEvents.removeWhere((e) => e.id == removed.id));
        await saveGoogleEvents(_googleEvents);
        unawaited(ScheduleWidgetService.sync());
      },
    );
  }

  Future<void> _saveSubjects() async {
    await StudentStorage.saveList(
      StudentStorage.subjectsKey,
      _subjects.map((s) => s.toJson()).toList(),
    );
    requestLocalNotificationRefresh();
    unawaited(ScheduleWidgetService.sync());
  }

  Future<void> _saveItems() async {
    await StudentStorage.saveList(
      StudentStorage.assignmentsKey,
      _items.map((i) => i.toJson()).toList(),
    );
    requestLocalNotificationRefresh();
    // Home screen widgets (Nov 11): the tasks changed —
    // push the stored assignments to the Tasks widget.
    unawaited(TasksWidgetService.sync());
  }

  void _snack(String m) {
    if (mounted) {
      TopPopup.show(context, message: m);
    }
  }

  String _subjectName(String id) {
    for (final s in _subjects) {
      if (s.id == id) return s.name;
    }
    return 'Subject';
  }

  Future<void> _openSubjectForm({Subject? existing}) async {
    final result = await showModalBottomSheet<Subject>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubjectForm(existing: existing, subjects: _subjects),
    );
    if (result == null) return;
    final isNew = existing == null;
    setState(() {
      _subjects.removeWhere((s) => s.id == result.id);
      _subjects.add(result);
      // New placement only: the tile springs in once and the
      // pop-chime plays. Edits re-save in place, silently.
      if (isNew) _justPlacedId = result.id;
    });
    await _saveSubjects();
    if (isNew) _playPlacementChime();
    _snack(existing == null ? 'Subject added.' : 'Subject updated.');
  }

  /// Placement chime (Feature 2): soft pop, always-on, no mute
  /// toggle — plays only when a class is placed into the Schedule,
  /// never on menu open, form open, or edit. The [SplashSound]
  /// call is best-effort (silence on failure); tests inject
  /// [ClassesScreen.onPlacementChime] to observe the trigger.
  void _playPlacementChime() {
    if (widget.onPlacementChime != null) {
      widget.onPlacementChime!();
    } else {
      SplashSound.placeClass();
    }
  }

  /// Files scan (Feature 3): pick a file, read its real text
  /// (photo OCR / PDF text layer / plain text — see
  /// [ScheduleFileScanner]), and place every class found into the
  /// timetable one by one. No sound on pick or scan — the
  /// placement chime plays once per class placed (see
  /// [_placeScannedClasses]). Nothing is invented: a file with no
  /// parseable entries shows an honest empty state instead.
  Future<void> _scanFromFiles() async {
    if (_scanInProgress) return;
    _scanInProgress = true;
    try {
      final scanner = widget.filesScanner ?? ScheduleFileScanner();
      File? file;
      try {
        file = await scanner.pickFile();
      } catch (_) {
        // The picker itself failed (no file was chosen): say so
        // plainly instead of crashing the flow — the student can
        // tap Files again.
        if (!mounted) return;
        _snack('Couldn\'t open the file picker. Try again.');
        return;
      }
      if (file == null) return; // User cancelled the picker.
      if (!mounted) return;
      // Non-nullable copy: `file` is captured by the dialog's
      // closures below, so flow analysis cannot promote it.
      final pickedFile = file;
      final result = await showDialog<ScheduleScanResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ScanProgressDialog(
          fileName: pickedFile.path.split('/').last,
          scan: () => scanner.extractAndParse(pickedFile),
        ),
      );
      if (result == null || !mounted) return;
      switch (result.status) {
        case ScheduleScanStatus.cancelled:
          return;
        case ScheduleScanStatus.found:
          await _placeScannedClasses(result.classes, result.fileName);
        case ScheduleScanStatus.noClasses:
        case ScheduleScanStatus.noText:
        case ScheduleScanStatus.unsupported:
          await _showScanEmptyState(result);
      }
    } finally {
      _scanInProgress = false;
    }
  }

  /// Place scanned classes into the timetable one by one, ~0.5 s
  /// apart: each lands with the spring-in + green flash + popping
  /// avatar ([_ScannedSpringIn]), a "New" badge, and one placement
  /// chime. A class that conflicts with a class already on the
  /// timetable (including one placed earlier in this same scan)
  /// is skipped, never force-added, and the skip is reported in
  /// the final toast.
  Future<void> _placeScannedClasses(
    List<ScannedClass> found,
    String fileName,
  ) async {
    var placed = 0;
    var skipped = 0;
    var colorIndex = 0;
    for (var i = 0; i < found.length; i++) {
      final subject = found[i].toSubject(
        id: newId(),
        color: _subjectColors[colorIndex % _subjectColors.length],
      );
      colorIndex++;
      if (findConflict(_subjects, subject) != null) {
        skipped++;
        continue;
      }
      setState(() {
        _subjects.add(subject);
        _scannedNewIds.add(subject.id);
        _justScannedId = subject.id;
      });
      await _saveSubjects();
      _playPlacementChime();
      placed++;
      if (i < found.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    final noun = placed == 1 ? 'class' : 'classes';
    if (placed > 0 && skipped == 0) {
      _snack('$placed $noun added from $fileName.');
    } else if (placed > 0) {
      _snack(
        '$placed $noun added from $fileName. $skipped skipped (time conflict).',
      );
    } else {
      _snack(
        skipped == 1
            ? 'No classes added — the class conflicts with your schedule.'
            : 'No classes added — all $skipped classes conflict with your schedule.',
      );
    }
  }

  /// Honest empty state for a scan that found nothing to place:
  /// no invented classes, just what happened and what file format
  /// the scan understands.
  Future<void> _showScanEmptyState(ScheduleScanResult result) async {
    final (title, body) = switch (result.status) {
      ScheduleScanStatus.noClasses => (
        'No classes found',
        'We couldn\'t find any class entries in ${result.fileName}.\n\n'
            'Each class needs its own line with days and a time, for example:\n'
            'Discrete Math | Mon, Wed, Fri | 8:00 AM - 9:30 AM | Room 101\n\n'
            'Photos, PDFs with text, and text files (.txt, .md, .csv) work best.',
      ),
      ScheduleScanStatus.noText => (
        'No text found',
        'We couldn\'t read any text from ${result.fileName}. '
            'If this is a scanned PDF with no text layer, try a photo of the page instead — photos are read on-device.',
      ),
      ScheduleScanStatus.unsupported => (
        'File type not supported',
        'This file type can\'t be scanned yet. Try a photo, a PDF, or a text file (.txt, .md, .csv).',
      ),
      _ => ('Nothing to add', 'No classes were found in ${result.fileName}.'),
    };
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('schedule-scan-empty'),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const Key('scan-empty-ok'),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Google Schedule sync (Feature 4): connect the student's
  /// REAL Google Calendar (Google Sign-In + calendar.readonly
  /// scope) and fetch their upcoming events — see
  /// [GoogleCalendarSync]. No sound on connect or sync: the
  /// placement chime plays once per class placed (see
  /// [_placeSyncedGoogleEvents]). Nothing is invented: a failed
  /// or unconfigured sync says so plainly, and the 4 placeholder
  /// sample events are never presented as synced results.
  Future<void> _syncFromGoogle() async {
    if (_googleSyncInProgress) return;
    _googleSyncInProgress = true;
    try {
      final sync = widget.googleSync ?? GoogleCalendarSync();
      final result = await showDialog<GoogleCalendarSyncResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _GoogleSyncProgressDialog(sync: sync.sync),
      );
      if (result == null || !mounted) return;
      switch (result.status) {
        case GoogleCalendarSyncStatus.cancelled:
          return; // Dismissed the chooser / consent: nothing to do.
        case GoogleCalendarSyncStatus.setupMissing:
          await _showGoogleSetupMissing();
        case GoogleCalendarSyncStatus.failed:
          _snack(
            'Couldn\'t sync Google Calendar. Check your connection and try again.',
          );
        case GoogleCalendarSyncStatus.noEvents:
          await _showGoogleSyncEmpty(result.accountEmail);
        case GoogleCalendarSyncStatus.synced:
          await _placeSyncedGoogleEvents(result.events);
      }
    } finally {
      _googleSyncInProgress = false;
    }
  }

  /// Place synced Google events into the timetable one by one,
  /// ~0.5 s apart: each lands with the spring-in + green flash +
  /// popping G badge ([_ScannedSpringIn]), a "New" badge, and one
  /// placement chime — the same treatment as the Files scan
  /// placements.
  ///
  /// - The FIRST successful real sync replaces the stored set:
  ///   the 4 placeholder sample events (Discrete Mathematics,
  ///   Life and Works of Rizal, NSTP 1, Vigan) were never the
  ///   student's real calendar, so they go away the moment real
  ///   events arrive. Later syncs merge: events already synced
  ///   are skipped, never duplicated.
  /// - An event whose title matches a class already on the
  ///   timetable is skipped (the class already represents it —
  ///   the merged list would hide it anyway) and reported in the
  ///   final toast.
  Future<void> _placeSyncedGoogleEvents(
    List<GoogleCalendarEvent> fetched,
  ) async {
    final firstRealSync = !await isGoogleCalendarRealSyncDone();
    if (firstRealSync) {
      setState(() => _googleEvents = []);
    }
    final existingIds = _googleEvents.map((e) => e.id).toSet();
    final classNames = _subjects.map((s) => s.name).toSet();
    var placed = 0;
    var skipped = 0;
    for (var i = 0; i < fetched.length; i++) {
      final event = fetched[i];
      if (existingIds.contains(event.id) || classNames.contains(event.title)) {
        skipped++;
        continue;
      }
      setState(() {
        _googleEvents.add(event);
        _syncedNewIds.add(event.id);
        _justSyncedGoogleId = event.id;
      });
      await saveGoogleEvents(_googleEvents);
      _playPlacementChime();
      placed++;
      if (i < fetched.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }
    }
    if (firstRealSync) await markGoogleCalendarRealSyncDone();
    if (!mounted) return;
    final noun = placed == 1 ? 'class' : 'classes';
    if (placed > 0 && skipped == 0) {
      _snack('$placed $noun synced from Google Calendar.');
    } else if (placed > 0) {
      _snack(
        '$placed $noun synced from Google Calendar. '
        '$skipped already on your timetable.',
      );
    } else {
      _snack(
        skipped == 1
            ? 'No classes added — the synced event is already on your timetable.'
            : 'No classes added — the synced events are already on your timetable.',
      );
    }
    unawaited(ScheduleWidgetService.sync());
  }

  /// Honest setup-missing state: the real sync cannot run until
  /// the Google Cloud Console steps are done. Only Steven can do
  /// these (his own Console, project estudyantego) — the app never
  /// logs into his Console for him. No fake "connected" state.
  Future<void> _showGoogleSetupMissing() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('google-sync-setup-missing'),
        title: const Text('Google Calendar isn\'t connected yet'),
        content: const Text(
          'To sync your real Google Calendar, set this up once in '
          'Google Cloud Console (project estudyantego):\n\n'
          '1. APIs & Services → Library → search "Google Calendar API" → Enable.\n'
          '2. APIs & Services → OAuth consent screen → add this scope:\n'
          'https://www.googleapis.com/auth/calendar.readonly\n'
          '3. Make sure an Android OAuth client exists for com.estudyantego.app — the google-services.json in the app currently lists no OAuth client at all.\n'
          '4. If the app is in Testing, add your Google account as a test user.\n\n'
          'Then tap Google Schedule again. The 4 sample events listed now are placeholders, not your real calendar — they are replaced by your real events on the first successful sync.',
        ),
        actions: [
          TextButton(
            key: const Key('google-setup-ok'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Honest empty state for a sync that connected fine but found
  /// no timed events in the next 4 weeks: no invented classes,
  /// just what was checked.
  Future<void> _showGoogleSyncEmpty(String accountEmail) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('google-sync-empty'),
        title: const Text('No classes found'),
        content: Text(
          'No class events were found in your Google Calendar'
          '${accountEmail.isEmpty ? '' : ' ($accountEmail)'}'
          ' for the next 4 weeks.\n\n'
          'Only events with a day and time sync — all-day events are skipped. Add a class to your calendar, then sync again.',
        ),
        actions: [
          TextButton(
            key: const Key('google-sync-empty-ok'),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSubject(Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete subject?'),
        content: Text(
          '${s.name} and its assignments and exams will also be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _subjects.removeWhere((x) => x.id == s.id);
      _items.removeWhere((i) => i.subjectId == s.id);
    });
    await _saveSubjects();
    await _saveItems();
  }

  Future<void> _openItemForm() async {
    if (_subjects.isEmpty) {
      _snack('Add a subject first, then attach deadlines to it.');
      return;
    }
    final result = await showModalBottomSheet<AssignmentItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemForm(subjects: _subjects),
    );
    if (result == null) return;
    setState(() {
      _items.add(result);
      _items.sort((a, b) => a.due.compareTo(b.due));
    });
    await _saveItems();
    _snack(result.kind == 'exam' ? 'Exam added.' : 'Assignment added.');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = nextClass(_subjects, now);
    final upcoming = _items.where((i) => !i.done).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final done = _items.where((i) => i.done).toList();

    // Stack (not Scaffold.floatingActionButton): the menu overlay
    // and the tap-outside barrier must sit above the Scaffold body
    // but below the round + button, so the button stays tappable
    // (x to close) while the menu is open.
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Classes & Timetable')),
          body: ListView(
            padding: AppLayout.pagePaddingTab,
            children: [
              if (next != null)
                MinecraftCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const MinecraftIconBadge(
                        icon: Icons.upcoming_outlined,
                        backgroundColor: MinecraftColors.skyBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Upcoming: ${next.subject.name}',
                              style: MinecraftText.title(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${weekdayName(next.date.weekday)} · ${formatMinutes(next.subject.startMin)}–${formatMinutes(next.subject.endMin)}${next.subject.room.isEmpty ? '' : ' · ${next.subject.room}'}',
                              style: MinecraftText.body(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const MinecraftStatusChip('Next up'),
                    ],
                  ),
                )
              else
                MinecraftCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(
                      'No upcoming classes.',
                      style: MinecraftText.title(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      'Add a subject to build your timetable.',
                      style: MinecraftText.body(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppLayout.headerGap),
              _MinecraftSegmented(
                options: const [('today', 'Today'), ('week', 'Week')],
                groupValue: _view,
                onChanged: (value) => setState(() => _view = value),
              ),
              const SizedBox(height: AppLayout.cardGap),
              if (_view == 'today') ...[
                // Today list: today's classes + every synced Google
                // event, time order — the same merged entries the Hub
                // card's Today list renders, so the two can never
                // diverge. Google cards carry the G badge, their day
                // prefix, and open the Edit / Remove sheet on tap.
                if (todayListEntries(
                  _subjects,
                  _googleEvents,
                  now.weekday,
                ).isEmpty)
                  MinecraftCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        'No classes today.',
                        style: MinecraftText.title(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                else
                  for (final entry in todayListEntries(
                    _subjects,
                    _googleEvents,
                    now.weekday,
                  ))
                    entry.isGoogle && entry.googleEvent != null
                        ? _googleTile(entry.googleEvent!)
                        : _subjectTile(
                            entry.subject!,
                            isNext:
                                // 'Next up' only when the next class
                                // is TODAY — the same subject meeting
                                // tomorrow is not next up (its id
                                // matches, its date does not).
                                next != null &&
                                next.subject.id == entry.subject!.id &&
                                next.date.year == now.year &&
                                next.date.month == now.month &&
                                next.date.day == now.day,
                          ),
              ] else ...[
                for (var day = 1; day <= 7; day++)
                  if (entriesForDay(
                    _subjects,
                    _googleEvents,
                    day,
                  ).isNotEmpty) ...[
                    Text(
                      weekdayName(day),
                      style: MinecraftText.heading(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    for (final entry in entriesForDay(
                      _subjects,
                      _googleEvents,
                      day,
                    ))
                      entry.isGoogle && entry.googleEvent != null
                          ? _googleTile(entry.googleEvent!)
                          : _subjectTile(entry.subject!),
                    const SizedBox(height: AppLayout.cardGap),
                  ],
                if (_subjects.isEmpty && _googleEvents.isEmpty)
                  MinecraftCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        'No subjects yet.',
                        style: MinecraftText.title(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: MinecraftSectionHeader(
                      icon: Icons.assignment_outlined,
                      title: 'Assignments & Exams',
                      iconColor: MinecraftColors.gold,
                    ),
                  ),
                  TextButton(
                    onPressed: _openItemForm,
                    child: const Text('Add'),
                  ),
                ],
              ),
              if (upcoming.isEmpty && done.isEmpty)
                MinecraftCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(
                      'No assignments yet.',
                      style: MinecraftText.title(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                )
              else ...[
                for (final i in upcoming) _itemTile(i),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'Done',
                    style: MinecraftText.heading(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 17,
                    ),
                  ),
                  for (final i in done) _itemTile(i),
                ],
              ],
              const SizedBox(height: 72),
            ],
          ),
        ),
        if (_menuOpen) ...[
          // Tap-outside barrier: transparent, closes the menu.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 88,
            child: ClassesPlusMenu(
              animation: _menuController,
              // Feature 2: "Set Schedule Manual" restores the old
              // "+ Add subject" form as the menu's entry point —
              // same form, same save path and storage, only the
              // entry point changes. Feature 3: "Files" scans a
              // picked file for class entries and places them one
              // by one. Feature 4: "Google Schedule" syncs the
              // student's real Google Calendar (see
              // [GoogleCalendarSync]) and places its events one
              // by one, same treatment as Files.
              onManual: () => _openSubjectForm(),
              onFiles: _scanFromFiles,
              onGoogle: _syncFromGoogle,
              onDismiss: _closeMenu,
            ),
          ),
        ],
        // Blocky 58px grass + button at bottom right (same spot
        // as the old round + button): squash-bounces and rotates
        // to x while the menu is open.
        Positioned(
          right: 16,
          bottom: 16,
          child: Hero(
            tag: 'classes-plus-fab',
            child: MinecraftFabButton(
              key: const Key('classes-plus-fab'),
              tooltip: 'Add',
              onPressed: _toggleMenu,
              child: ScaleTransition(
                scale: _fabScale,
                child: RotationTransition(
                  turns: _fabTurns,
                  child: const Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One synced Google Calendar event as a list card: white G
  /// badge, "Google Calendar" source, time range, place/teacher.
  /// Tapping opens the Edit / Remove sheet (the same sheet as
  /// the Hub card's blocks and rows).
  ///
  /// Feature 4: the synced event currently landing springs in
  /// with flash + popping G badge; every other synced event
  /// keeps its "New" badge and renders plainly.
  Widget _googleTile(GoogleCalendarEvent event) {
    if (event.id == _justSyncedGoogleId) {
      return _ScannedSpringIn(
        // Stable key (only one tile is ever wrapped at a time):
        // tests assert the spring-in is present mid-animation.
        key: const Key('synced-google-spring'),
        onDone: () {
          if (mounted && _justSyncedGoogleId == event.id) {
            setState(() => _justSyncedGoogleId = null);
          }
        },
        builder: (badgePop) => _googleTileBody(event, badgePop: badgePop),
      );
    }
    return _googleTileBody(event);
  }

  Widget _googleTileBody(
    GoogleCalendarEvent event, {
    Animation<double>? badgePop,
  }) {
    final detail = [
      'Google Calendar',
      googleEventRange(event),
      if (event.place.isNotEmpty) event.place,
      if (event.teacher.isNotEmpty) event.teacher,
    ].join(' · ');
    // Quest badge: the G mark in a 46px block with a 3px ink
    // border, matching the subject tiles' letter blocks.
    final badge = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? MinecraftColors.darkBorder
              : MinecraftColors.border,
          width: MinecraftShapes.cardBorderWidth,
        ),
      ),
      alignment: Alignment.center,
      child: const GBadge(size: 30),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MinecraftCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: badgePop == null
              ? badge
              : ScaleTransition(scale: badgePop, child: badge),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: MinecraftText.title(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const GBadge(),
              // Feature 4: events placed by the Google sync carry a
              // "New" badge for the rest of the session.
              if (_syncedNewIds.contains(event.id)) ...[
                const SizedBox(width: 6),
                MinecraftStatusChip('New', key: Key('synced-new-${event.id}')),
              ],
            ],
          ),
          subtitle: Text(
            detail,
            style: MinecraftText.body(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          onTap: () => _onGoogleEventTap(event),
        ),
      ),
    );
  }

  Widget _subjectTile(Subject s, {bool isNext = false}) {
    // Feature 3: the scanned class currently landing springs in
    // with flash + popping avatar; every other scanned class
    // keeps its "New" badge and renders plainly.
    if (s.id == _justScannedId) {
      return _ScannedSpringIn(
        // Stable key (only one tile is ever wrapped at a time):
        // tests assert the spring-in is present mid-animation.
        key: const Key('scanned-subject-spring'),
        onDone: () {
          if (mounted && _justScannedId == s.id) {
            setState(() => _justScannedId = null);
          }
        },
        builder: (avatarPop) =>
            _subjectTileBody(s, avatarPop: avatarPop, isNext: isNext),
      );
    }
    // Feature 2: the class that was just placed springs into the
    // timetable once; every other tile renders plainly, and the
    // wrapper comes off when the animation finishes.
    if (s.id == _justPlacedId) {
      return _PlacedSpringIn(
        // Stable key (only one tile is ever wrapped at a time):
        // tests assert the spring-in is present mid-animation.
        key: const Key('placed-subject-spring'),
        onDone: () {
          if (mounted && _justPlacedId == s.id) {
            setState(() => _justPlacedId = null);
          }
        },
        child: _subjectTileBody(s, isNext: isNext),
      );
    }
    return _subjectTileBody(s, isNext: isNext);
  }

  /// One class as a quest card (Minecraft restyle, Feature 3):
  /// the subject's color as a 46px letter block with a 3px ink
  /// border, Baloo 2 title, code/time/teacher/room details, and
  /// the real status chips — 'Next up' for the next class, 'New'
  /// for a class the Files scan just placed. There is no per-class
  /// XP in the app, so no XP number is shown (never invented).
  ///
  /// The tile stays a [ListTile] inside the blocky card: the
  /// existing tests find class tiles as ListTiles.
  Widget _subjectTileBody(
    Subject s, {
    Animation<double>? avatarPop,
    bool isNext = false,
  }) {
    final badge = Container(
      key: const Key('quest-badge'),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Color(s.color),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? MinecraftColors.darkBorder
              : MinecraftColors.border,
          width: MinecraftShapes.cardBorderWidth,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
        style: MinecraftText.heading(color: Colors.white, fontSize: 22),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MinecraftCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: avatarPop == null
              ? badge
              : ScaleTransition(scale: avatarPop, child: badge),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  s.name,
                  style: MinecraftText.title(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (isNext) ...[
                const SizedBox(width: 6),
                const MinecraftStatusChip('Next up'),
              ],
              // Feature 3: classes placed by the Files scan carry a
              // "New" badge for the rest of the session.
              if (_scannedNewIds.contains(s.id)) ...[
                const SizedBox(width: 6),
                MinecraftStatusChip('New', key: Key('scanned-new-${s.id}')),
              ],
            ],
          ),
          subtitle: Text(
            '${s.code.isEmpty ? '' : '${s.code} · '}${formatMinutes(s.startMin)}–${formatMinutes(s.endMin)}${s.teacher.isEmpty ? '' : ' · ${s.teacher}'}${s.room.isEmpty ? '' : ' · ${s.room}'}',
            style: MinecraftText.body(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _openSubjectForm(existing: s),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _deleteSubject(s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemTile(AssignmentItem i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MinecraftCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: MinecraftIconBadge(
            icon: i.kind == 'exam'
                ? Icons.quiz_outlined
                : Icons.assignment_outlined,
            backgroundColor: i.kind == 'exam'
                ? MinecraftColors.gold
                : MinecraftColors.skyBlue,
            iconColor: i.kind == 'exam' ? MinecraftColors.ink : Colors.white,
          ),
          title: Text(
            i.title,
            style: MinecraftText.title(
              color: Theme.of(context).colorScheme.onSurface,
            ).copyWith(decoration: i.done ? TextDecoration.lineThrough : null),
          ),
          subtitle: Text(
            '${_subjectName(i.subjectId)} · ${i.kind == 'exam' ? 'Exam' : 'Assignment'} · due ${formatDate(i.due)}',
            style: MinecraftText.body(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: i.done,
                onChanged: (v) async {
                  setState(() {
                    final idx = _items.indexWhere((x) => x.id == i.id);
                    if (idx >= 0) {
                      _items[idx] = AssignmentItem(
                        id: i.id,
                        subjectId: i.subjectId,
                        title: i.title,
                        kind: i.kind,
                        due: i.due,
                        done: v ?? false,
                      );
                    }
                  });
                  await _saveItems();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  setState(() => _items.removeWhere((x) => x.id == i.id));
                  await _saveItems();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blocky Today / Week segmented control (Minecraft restyle,
/// Feature 3): 3px ink border, 14px corners, grass-green active
/// segment with a white Baloo 2 label. Same values and callback
/// as the iOS segmented control it replaces — look only.
class _MinecraftSegmented extends StatelessWidget {
  const _MinecraftSegmented({
    required this.options,
    required this.groupValue,
    required this.onChanged,
  });

  final List<(String, String)> options;
  final String groupValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? MinecraftColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
        ),
        boxShadow: isDark ? null : const [MinecraftShapes.cardShadow],
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('classes-view-${options[i].$1}'),
                  onTap: () => onChanged(options[i].$1),
                  borderRadius: BorderRadius.circular(11),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: options[i].$1 == groupValue
                          ? MinecraftColors.grassGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      options[i].$2,
                      textAlign: TextAlign.center,
                      style: MinecraftText.button(
                        color: options[i].$1 == groupValue
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Spring-in entrance for a class that was just placed into the
/// timetable (Feature 2): the tile scales up from 0.85 with an
/// underdamped spring (same feel as the + menu — rises, overshoots,
/// settles) and fades in, once. Only the newly placed tile is
/// wrapped; the rest of the list never re-animates. When the
/// spring settles, [onDone] fires so the parent unwraps the tile.
/// Reduced motion: no animation — the tile shows instantly and
/// [onDone] still fires.
class _PlacedSpringIn extends StatefulWidget {
  const _PlacedSpringIn({super.key, required this.child, required this.onDone});

  final Widget child;
  final VoidCallback onDone;

  @override
  State<_PlacedSpringIn> createState() => _PlacedSpringInState();
}

class _PlacedSpringInState extends State<_PlacedSpringIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _doneNotified = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(_controller);
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    // Underdamped spring: overshoots ~17%, wobbles once, settles
    // (damping ratio ~0.5) — the same spring as the + menu.
    _controller
        .animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1.0, stiffness: 260.0, damping: 16.0),
            0.0,
            1.0,
            0.0,
          ),
        )
        .then((_) => _notifyDone());
  }

  void _notifyDone() {
    if (_doneNotified || !mounted) return;
    _doneNotified = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyDone());
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: _scale.value,
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Spring-in entrance for a class placed by the Files scan
/// (Feature 3): the tile scales up from 0.85 with an underdamped
/// spring (same feel as the + menu — rises, overshoots, settles)
/// and fades in, once, while a green flash washes over the tile
/// and fades out. The avatar pops separately: it scales up from
/// 0.4 with an elastic overshoot, handed to the tile through
/// [builder]. Only the newly placed scanned tile is wrapped; the
/// rest of the list never re-animates. When the spring settles,
/// [onDone] fires so the parent unwraps the tile. Reduced motion:
/// no animation — the tile shows instantly and [onDone] still
/// fires.
class _ScannedSpringIn extends StatefulWidget {
  const _ScannedSpringIn({
    super.key,
    required this.builder,
    required this.onDone,
  });

  /// Builds the tile; [avatarPop] scales the avatar 0.4 → 1 with
  /// an elastic pop as the tile springs in.
  final Widget Function(Animation<double> avatarPop) builder;
  final VoidCallback onDone;

  @override
  State<_ScannedSpringIn> createState() => _ScannedSpringInState();
}

class _ScannedSpringInState extends State<_ScannedSpringIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _avatarPop;
  late final Animation<double> _flash;
  bool _doneNotified = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(_controller);
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _avatarPop = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.elasticOut),
      ),
    );
    // Green flash: full strength as the tile lands, gone by the
    // time the spring settles.
    _flash = Tween<double>(begin: 0.32, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOut),
      ),
    );
    // Underdamped spring: overshoots ~17%, wobbles once, settles
    // (damping ratio ~0.5) — the same spring as the + menu. The
    // tile is unwrapped when the next scanned class lands, which
    // cancels this animation mid-flight; the error is swallowed
    // so the cancelled spring never surfaces as a test failure.
    _controller
        .animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1.0, stiffness: 260.0, damping: 16.0),
            0.0,
            1.0,
            0.0,
          ),
        )
        .then((_) => _notifyDone())
        .catchError((_) {});
  }

  void _notifyDone() {
    if (_doneNotified || !mounted) return;
    _doneNotified = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyDone());
      return widget.builder(const AlwaysStoppedAnimation(1.0));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: _scale.value,
          alignment: Alignment.center,
          child: Stack(
            children: [
              widget.builder(_avatarPop),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: MinecraftColors.grassGreen
                          .withValues(alpha: _flash.value.clamp(0.0, 1.0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The extracting state for a Files scan (Feature 3): a sweeping
/// green scan line travels over a document preview while the real
/// extraction runs — no fake delay, the line runs for exactly the
/// extraction duration. Starts the extraction once in initState
/// and pops with the result.
class _ScanProgressDialog extends StatefulWidget {
  const _ScanProgressDialog({required this.fileName, required this.scan});

  final String fileName;
  final Future<ScheduleScanResult> Function() scan;

  @override
  State<_ScanProgressDialog> createState() => _ScanProgressDialogState();
}

class _ScanProgressDialogState extends State<_ScanProgressDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  late final Animation<double> _sweepY;
  bool _sweepStarted = false;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _sweepY = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _sweep, curve: Curves.easeInOut));
    widget.scan().then(
      (result) {
        if (mounted) Navigator.pop(context, result);
      },
      onError: (_) {
        // The scanner catches its own failures, but a rejected
        // future must never leave this dialog hanging.
        if (mounted) {
          Navigator.pop(
            context,
            ScheduleScanResult(
              status: ScheduleScanStatus.noText,
              fileName: widget.fileName,
            ),
          );
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the sweep line stays still (build positions
    // it mid-document). MediaQuery is only readable here, not in
    // initState.
    if (!_sweepStarted) {
      _sweepStarted = true;
      if (!MediaQuery.of(context).disableAnimations) {
        _sweep.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return AlertDialog(
      key: const Key('schedule-scan-progress'),
      title: const Text('Scanning file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.fileName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // Document preview: faint text lines with the green
          // scan line sweeping over them.
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF0C1410),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, child) {
                final y = reducedMotion ? 0.5 : _sweepY.value;
                return Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 5; i++)
                            Container(
                              height: 6,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: y * (120 - 4),
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        decoration: const BoxDecoration(
                          color: MinecraftColors.grassGreen,
                          boxShadow: [
                            BoxShadow(
                              color: MinecraftColors.grassGreen,
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text('Reading text from ${widget.fileName}…'),
        ],
      ),
    );
  }
}

/// The connecting / syncing state for a Google Schedule sync
/// (Feature 4): a spinner with the real phase — "Connecting to
/// Google Calendar…" while the Google account + calendar scope
/// authorize, "Syncing your calendar…" while the Calendar API
/// fetch runs. No fake delay: the phase text changes only when
/// the real step starts, and the dialog pops with the real result.
/// Starts the sync once in initState.
class _GoogleSyncProgressDialog extends StatefulWidget {
  const _GoogleSyncProgressDialog({required this.sync});

  final Future<GoogleCalendarSyncResult> Function({
    required void Function(GoogleCalendarSyncPhase phase) onPhase,
  })
  sync;

  @override
  State<_GoogleSyncProgressDialog> createState() =>
      _GoogleSyncProgressDialogState();
}

class _GoogleSyncProgressDialogState extends State<_GoogleSyncProgressDialog> {
  GoogleCalendarSyncPhase _phase = GoogleCalendarSyncPhase.connecting;

  @override
  void initState() {
    super.initState();
    widget
        .sync(
          onPhase: (phase) {
            if (mounted) setState(() => _phase = phase);
          },
        )
        .then(
          (result) {
            if (mounted) Navigator.pop(context, result);
          },
          onError: (_) {
            // The sync maps its own failures to a status, but a
            // rejected future must never leave this dialog hanging.
            if (mounted) {
              Navigator.pop(
                context,
                const GoogleCalendarSyncResult(
                  status: GoogleCalendarSyncStatus.failed,
                ),
              );
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('google-sync-progress'),
      title: const Text('Google Schedule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            _phase == GoogleCalendarSyncPhase.connecting
                ? 'Connecting to Google Calendar…'
                : 'Syncing your calendar…',
          ),
        ],
      ),
    );
  }
}

class _SubjectForm extends StatefulWidget {
  const _SubjectForm({this.existing, required this.subjects});

  final Subject? existing;
  final List<Subject> subjects;

  @override
  State<_SubjectForm> createState() => _SubjectFormState();
}

class _SubjectFormState extends State<_SubjectForm> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _teacher = TextEditingController();
  final _room = TextEditingController();
  final _days = <int>{};
  int _startMin = 8 * 60;
  int _endMin = 9 * 60;
  int _color = _subjectColors.first;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _code.text = e.code;
      _teacher.text = e.teacher;
      _room.text = e.room;
      _days.addAll(e.days);
      _startMin = e.startMin;
      _endMin = e.endMin;
      _color = e.color;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _teacher.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (isStart ? _startMin : _endMin) ~/ 60,
        minute: (isStart ? _startMin : _endMin) % 60,
      ),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMin = minutes;
      } else {
        _endMin = minutes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Minecraft restyle (Feature 3): blocky sheet — Baloo 2 title,
    // grass day toggles, blocky time tiles and color blocks, and
    // the save button labelled 'Place Block (Save)'. The fields
    // are the SAME Manual form (subject, code, teacher, room,
    // days, start/end, color) — NO Repeat option is added here:
    // Repeat exists only in the preview and is not approved.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const MinecraftIconBadge(
                  icon: Icons.view_in_ar_outlined,
                  backgroundColor: MinecraftColors.grassGreen,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.existing == null
                            ? 'Add Subject Block'
                            : 'Edit Subject Block',
                        style: MinecraftText.heading(
                          color: onSurface,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        widget.existing == null
                            ? 'Place a new class block into your week.'
                            : 'Change this class block.',
                        style: MinecraftText.body(color: onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Subject name'),
            ),
            const SizedBox(height: AppSpacing.s8),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Subject code'),
            ),
            const SizedBox(height: AppSpacing.s8),
            TextField(
              controller: _teacher,
              decoration: const InputDecoration(labelText: 'Teacher'),
            ),
            const SizedBox(height: AppSpacing.s8),
            TextField(
              controller: _room,
              decoration: const InputDecoration(
                labelText: 'Classroom / location',
              ),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Text('Days', style: MinecraftText.title(color: onSurface)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var day = 1; day <= 7; day++)
                  _DayToggle(
                    label: weekdayName(day),
                    selected: _days.contains(day),
                    onTap: () => setState(() {
                      if (_days.contains(day)) {
                        _days.remove(day);
                      } else {
                        _days.add(day);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: _TimeTile(
                    label: 'Start: ${formatMinutes(_startMin)}',
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimeTile(
                    label: 'End: ${formatMinutes(_endMin)}',
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text('Color', style: MinecraftText.title(color: onSurface)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in _subjectColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: _color == c ? 40 : 32,
                      height: _color == c ? 40 : 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? MinecraftColors.darkBorder
                              : MinecraftColors.border,
                          width: _color == c ? 3 : 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: _color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppLayout.headerGap),
            SizedBox(
              width: double.infinity,
              child: MinecraftBlockButton(
                label: 'Place Block (Save)',
                icon: Icons.save_outlined,
                // Feature 6: saving a class plays the level-up
                // fanfare.
                sound: MinecraftSoundKind.levelup,
                onPressed: () {
                  if (_name.text.trim().isEmpty) {
                    TopPopup.show(context, message: 'Enter a subject name.');
                    return;
                  }
                  if (_days.isEmpty) {
                    TopPopup.show(context, message: 'Pick at least one day.');
                    return;
                  }
                  if (_endMin <= _startMin) {
                    TopPopup.show(
                      context,
                      message: 'End time must be after start time.',
                    );
                    return;
                  }
                  final candidate = Subject(
                    id: widget.existing?.id ?? newId(),
                    name: _name.text.trim(),
                    code: _code.text.trim(),
                    teacher: _teacher.text.trim(),
                    room: _room.text.trim(),
                    days: _days.toList()..sort(),
                    startMin: _startMin,
                    endMin: _endMin,
                    color: _color,
                  );
                  final conflict = findConflict(
                    widget.subjects,
                    candidate,
                    excludeId: widget.existing?.id,
                  );
                  if (conflict != null) {
                    TopPopup.show(
                      context,
                      message:
                          'Schedule conflict with $conflict. Pick another time.',
                    );
                    return;
                  }
                  Navigator.pop(context, candidate);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One blocky day toggle for the Add Subject sheet (Feature 3):
/// grass fill + white Baloo 2 label when selected, paper fill +
/// ink border when not. Same selection state as the FilterChip
/// it replaces — look only.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Feature 6: day toggles play select. The wrapper only
    // observes the pointer; the InkWell still owns the toggle.
    return MinecraftTapAnimation(
      sound: MinecraftSoundKind.select,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? MinecraftColors.grassGreen
                  : (isDark ? MinecraftColors.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? MinecraftColors.darkBorder
                    : MinecraftColors.border,
                width: 2.5,
              ),
            ),
            child: Text(
              label,
              style: MinecraftText.button(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One blocky start/end time tile for the Add Subject sheet
/// (Feature 3): the 'Start: 8:00 AM' / 'End: 9:00 AM' label in
/// Baloo 2 plus a clock badge; tapping opens the same time
/// picker as before — look only.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MinecraftCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: MinecraftText.button(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const MinecraftIconBadge(
            icon: Icons.schedule,
            backgroundColor: MinecraftColors.skyBlue,
            size: 32,
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.subjects});

  final List<Subject> subjects;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late String _subjectId;
  final _title = TextEditingController();
  String _kind = 'assignment';
  DateTime _due = DateTime.now();

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjects.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add deadline',
            style: MinecraftText.heading(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          DropdownButtonFormField<String>(
            value: _subjectId,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: [
              for (final s in widget.subjects)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _subjectId = v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: AppSpacing.s8),
          _MinecraftSegmented(
            options: const [('assignment', 'Assignment'), ('exam', 'Exam')],
            groupValue: _kind,
            onChanged: (value) => setState(() => _kind = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Due: ${formatDate(_due)}',
              style: MinecraftText.button(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            trailing: const MinecraftIconBadge(
              icon: Icons.calendar_month,
              backgroundColor: MinecraftColors.skyBlue,
              size: 32,
              iconSize: 18,
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _due,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _due = picked);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          SizedBox(
            width: double.infinity,
            child: MinecraftBlockButton(
              label: 'Save',
              icon: Icons.save_outlined,
              onPressed: () {
                if (_title.text.trim().isEmpty) {
                  TopPopup.show(context, message: 'Enter a title.');
                  return;
                }
                Navigator.pop(
                  context,
                  AssignmentItem(
                    id: newId(),
                    subjectId: _subjectId,
                    title: _title.text.trim(),
                    kind: _kind,
                    due: _due,
                    done: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
