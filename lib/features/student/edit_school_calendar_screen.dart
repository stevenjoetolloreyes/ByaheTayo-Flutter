// Edit School Calendar page (Nov 9, 2026).
//
// Opens from the green Edit button on the Student Hub's School
// Calendar card. The student edits the school name and the
// Marked Days list (nationwide PH holidays for 2026 are already
// on it; any of them can be renamed or removed, and days the
// school announces can be added). Saving writes the draft back
// through [persistDraft] — system days become name/hide
// overrides, added days become custom days — plus the school
// name under the same [profileSchoolKey] Student Information
// uses, so the hub card and Student Information agree.
//
// There is NO dashed "+ Add a day" button (Steven removed it):
// a round green floating + sits at the BOTTOM-LEFT, opening a
// spring menu with Add Day (name / date / type sheet) and Files
// (scan a memo, screenshot, or announcement for school days and
// insert them one by one). The scan flow mirrors the Allowance
// invoice scan: same FilePicker + NoteExtractService, same green
// scan line and staggered check-offs, same one-by-one insert with
// a green flash, a "New" badge, auto-scroll, an "Inserting i of
// n…" toast, a summary toast, and a soft pop-chime the moment
// each day lands — no sound on menu open, scan, or finish. Days
// already on the list are skipped with an honest toast.
//
// Back discards the draft (preview behaviour): nothing is saved
// until Save is tapped.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../minecraft_theme.dart';
import '../onboarding/onboarding_state.dart';
import '../onboarding/splash_sound.dart';
import '../ph_holidays.dart';
import '../top_popup.dart';
import 'custom_school_days.dart';
import 'note_extract_service.dart';

/// Short date label, e.g. "Nov 1, 2026".
String formatMarkedDayDate(DateTime date) =>
    '${monthShortName(date.month)} ${date.day}, ${date.year}';

/// Date or range label for a Marked Days row, e.g. "Nov 1, 2026"
/// or "Oct 19–25, 2026" for a multi-day school event.
String formatMarkedDayRange(MarkedDayEntry entry) {
  if (entry.end.year == entry.date.year &&
      entry.end.month == entry.date.month &&
      entry.end.day == entry.date.day) {
    return formatMarkedDayDate(entry.date);
  }
  if (entry.end.year == entry.date.year &&
      entry.end.month == entry.date.month) {
    return '${monthShortName(entry.date.month)} ${entry.date.day}–'
        '${entry.end.day}, ${entry.date.year}';
  }
  return '${monthShortName(entry.date.month)} ${entry.date.day} – '
      '${formatMarkedDayDate(entry.end)}';
}

/// The dot colour for a marked-day type on the calendar and in
/// the list (same colours as the hub legend: holiday red, no
/// classes amber, event blue).
Color markedDayTypeColor(MarkedDayType type) => switch (type) {
      MarkedDayType.holiday => Colors.red,
      MarkedDayType.noClasses => const Color(0xFFF59E0B),
      MarkedDayType.event => const Color(0xFF3B82F6),
    };

class EditSchoolCalendarScreen extends StatefulWidget {
  const EditSchoolCalendarScreen({
    super.key,
    required this.school,
    required this.days,
  });

  /// The school shown on the calendar card (null / empty when the
  /// student never set one — the field then pre-fills with the
  /// school the calendar already assumes, University of Northern
  /// Philippines).
  final String? school;

  /// The effective marked days, grouped (one row per multi-day
  /// event) — the draft starts as a copy of this list.
  final List<MarkedDayEntry> days;

  @override
  State<EditSchoolCalendarScreen> createState() =>
      _EditSchoolCalendarScreenState();
}

class _EditSchoolCalendarScreenState
    extends State<EditSchoolCalendarScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _schoolController;
  late List<MarkedDayEntry> _days;
  late final AnimationController _fabController;
  late final ScrollController _listController;

  /// Days just inserted by a scan: green flash + "New" badge
  /// until the batch settles a few seconds later.
  final Set<String> _justInserted = {};
  final Map<String, GlobalKey> _dayKeys = {};

  bool _fabMenuOpen = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final school = widget.school?.trim();
    _schoolController = TextEditingController(
      text: school == null || school.isEmpty
          ? 'University of Northern Philippines'
          : school,
    );
    _days = List.of(widget.days);
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _listController = ScrollController();
  }

  @override
  void dispose() {
    _schoolController.dispose();
    _fabController.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    TopPopup.show(context, message: message);
  }

  /// Save: the draft becomes (custom days, overrides) in the
  /// store and the school name under the profile key Student
  /// Information uses. The hub reloads both when this page pops
  /// (StudentTab._open calls _load), so the calendar updates
  /// immediately — dots, legend, day details, Coming up, and the
  /// school name on the card.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final school = _schoolController.text.trim();
    final existingCustom = await SchoolCalendarStore.loadCustomDays();
    final existingOverrides = await SchoolCalendarStore.loadOverrides();
    final saved = persistDraft(
      draft: _days,
      school: school,
      existingCustom: existingCustom,
      existingOverrides: existingOverrides,
    );
    await SchoolCalendarStore.saveCustomDays(saved.custom);
    await SchoolCalendarStore.saveOverrides(saved.overrides);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profileSchoolKey, school);
    if (!mounted) return;
    _snack('School calendar updated');
    Navigator.pop(context);
  }

  // ---------------------------------------------------------- floating +

  void _toggleFabMenu() {
    setState(() => _fabMenuOpen = !_fabMenuOpen);
    if (_fabMenuOpen) {
      _fabController.forward();
    } else {
      _fabController.reverse();
    }
  }

  void _closeFabMenu() {
    if (_fabMenuOpen) _toggleFabMenu();
  }

  /// Add Day: the name / date / type sheet. Editing a row opens
  /// the same sheet pre-filled; saving replaces that row.
  Future<void> _addOrEditDay([MarkedDayEntry? existing]) async {
    _closeFabMenu();
    final saved = await showModalBottomSheet<MarkedDayEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DaySheet(
        existing: existing,
        days: _days,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _days.add(saved);
      } else {
        final index = _days.indexWhere((d) => d.id == existing.id);
        if (index >= 0) _days[index] = saved;
      }
      _days.sort((a, b) => a.date.compareTo(b.date));
    });
  }

  void _removeDay(MarkedDayEntry row) {
    setState(() => _days.removeWhere((d) => d.id == row.id));
    _snack('Removed “${row.name}”');
  }

  /// Files: pick a school memo, calendar screenshot, or
  /// announcement, scan it for school days, then insert them one
  /// by one with a pop-chime per landing.
  Future<void> _scanFromFiles() async {
    _closeFabMenu();
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (picked == null || picked.path == null || !mounted) return;
    final found = await showModalBottomSheet<List<ScannedSchoolDay>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _SchoolScanSheet(file: File(picked.path!)),
      ),
    );
    if (found == null || found.isEmpty || !mounted) return;
    await _insertScanned(found);
  }

  /// Inserts confirmed scan drafts one by one (~0.6 s apart):
  /// each springs into the list with a green flash and a "New"
  /// badge, a soft pop-chime plays the moment it lands, and the
  /// list scrolls to it. No sound on menu open, scan, or finish.
  /// Days already on the list are skipped — the summary toast
  /// says how many.
  Future<void> _insertScanned(List<ScannedSchoolDay> found) async {
    final fresh = <ScannedSchoolDay>[];
    var skipped = 0;
    for (final d in found) {
      if (findDay(_days, d.date) != null) {
        skipped++;
        continue;
      }
      fresh.add(d);
    }
    if (fresh.isEmpty) {
      _snack(skipped == 0
          ? 'No school days found in this file.'
          : 'All $skipped day${skipped == 1 ? '' : 's'} from the scan '
              'are already on the list — nothing new to add.');
      return;
    }
    var i = 0;
    for (final d in fresh) {
      if (!mounted) return;
      i++;
      final entry = MarkedDayEntry(
        id: 'c${DateTime.now().microsecondsSinceEpoch}_$i',
        date: d.date,
        end: d.date,
        name: d.name,
        type: d.type,
        source: MarkedDaySource.custom,
      );
      setState(() {
        _days.add(entry);
        _days.sort((a, b) => a.date.compareTo(b.date));
        _justInserted.add(entry.id);
      });
      SplashSound.pop();
      _snack('Inserting $i of ${fresh.length}…');
      await _scrollToDay(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    if (!mounted) return;
    _snack(
      '${fresh.length} day${fresh.length == 1 ? '' : 's'} added from '
      'the scan${skipped == 0 ? '' : ' — $skipped already on the list, skipped'}.',
    );
    await Future<void>.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _justInserted.clear());
  }

  Future<void> _scrollToDay(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    final context = _dayKeys[id]?.currentContext;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        alignment: 0.15,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit School Calendar'),
        actions: [
          TextButton.icon(
            key: const ValueKey('edit-calendar-save'),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check, size: 20),
            label: const Text('Save'),
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            controller: _listController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Text('School',
                  style: MinecraftText.title()),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('edit-calendar-school'),
                controller: _schoolController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.school_outlined),
                  border: OutlineInputBorder(),
                  hintText: 'School name',
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              Text(
                'This is the school shown on your calendar. Nationwide '
                'holidays for 2026 are already on the calendar — you can '
                'rename or remove any of them below, and add days your '
                'school announces.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Text('Marked days',
                  style: MinecraftText.title()),
              const SizedBox(height: 8),
              if (_days.isEmpty)
                const MinecraftCard(
                  child: ListTile(
                    title: Text('No marked days yet.'),
                    subtitle: Text(
                        'Tap + below to add a day or scan a school memo.'),
                  ),
                )
              else
                for (final row in _days) _dayRow(context, row),
            ],
          ),
          // Floating + spring menu overlay (closes on tap outside).
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _fabController,
              builder: (_, _) {
                if (!_fabMenuOpen && _fabController.value == 0) {
                  return const SizedBox.shrink();
                }
                return Stack(
                  children: [
                    if (_fabMenuOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _toggleFabMenu,
                          behavior: HitTestBehavior.translucent,
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      bottom: 88,
                      child: _buildFabMenu(context, reduceMotion),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: _buildFab(context, reduceMotion),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(BuildContext context, MarkedDayEntry row) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = _justInserted.contains(row.id);
    final key = _dayKeys.putIfAbsent(row.id, () => GlobalKey());
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isNew
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: isNew
            ? Border.all(color: scheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: ListTile(
        leading: Icon(Icons.circle,
            size: 10, color: markedDayTypeColor(row.type)),
        title: Row(
          children: [
            Expanded(
              child: Text(row.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (isNew)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('New',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        subtitle: Text(
          '${formatMarkedDayRange(row)} · ${row.type.label}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('edit-day-${row.id}'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit day',
              onPressed: () => _addOrEditDay(row),
            ),
            IconButton(
              key: ValueKey('remove-day-${row.id}'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove day',
              onPressed: () => _removeDay(row),
            ),
          ],
        ),
      ),
    );
  }

  /// Round green floating + (this screen only, bottom-left).
  /// Tapping squash-bounces it, rotates it to ×, and springs the
  /// menu up; tapping again closes it.
  Widget _buildFab(BuildContext context, bool reduceMotion) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_fabMenuOpen),
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: reduceMotion ? Curves.linear : Curves.elasticOut,
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: AnimatedRotation(
        turns: _fabMenuOpen ? 0.125 : 0,
        duration: const Duration(milliseconds: 250),
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 6,
          child: InkWell(
            key: const ValueKey('calendar-edit-fab'),
            customBorder: const CircleBorder(),
            onTap: _toggleFabMenu,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }

  /// The spring menu above the +: Add Day first, Files second,
  /// popping in staggered with an overshoot settle.
  Widget _buildFabMenu(BuildContext context, bool reduceMotion) {
    final scheme = Theme.of(context).colorScheme;
    final menuScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _fabController,
        curve: reduceMotion ? Curves.linear : Curves.elasticOut,
      ),
    );
    Widget item({
      required int index,
      required Key key,
      required IconData icon,
      required String label,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      final interval = Interval(
        0.15 + index * 0.2,
        0.55 + index * 0.2,
        curve: Curves.easeOut,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _fabController, curve: interval),
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _fabController,
            curve: interval,
          )),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ScaleTransition(
              scale: menuScale,
              child: Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
                elevation: 4,
                child: InkWell(
                  key: key,
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(subtitle,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        item(
          index: 0,
          key: const ValueKey('calendar-fab-add-day'),
          icon: Icons.calendar_month_outlined,
          label: 'Add Day',
          subtitle: 'Name, date, and type — Holiday, No classes, or Event',
          onTap: () => _addOrEditDay(),
        ),
        item(
          index: 1,
          key: const ValueKey('calendar-fab-files'),
          icon: Icons.file_upload_outlined,
          label: 'Files',
          subtitle: 'Scan a memo, screenshot, or announcement',
          onTap: _scanFromFiles,
        ),
      ],
    );
  }
}

/// Add / Edit day sheet: name, date, and type (Holiday / No
/// classes / Event). Guards, in the preview's own words:
/// "Give the day a name first.", "Pick a date first.", and
/// "“X” is already marked on that date." — the clash check is
/// range-aware, so a date inside a multi-day event is caught too.
/// Editing a row keeps its id (so a rename stays a name override
/// and a move stays a move); an edited row becomes a single day
/// (the sheet picks one date).
class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.existing, required this.days});

  /// The row being edited, or null for a new day.
  final MarkedDayEntry? existing;

  /// The draft list, for the duplicate guard (the row being
  /// edited is excluded).
  final List<MarkedDayEntry> days;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late final TextEditingController _nameController;
  late DateTime? _date;
  late MarkedDayType _type;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?.name ?? '');
    _date = widget.existing?.date;
    _type = widget.existing?.type ?? MarkedDayType.holiday;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _saveDay() {
    final name = _nameController.text.trim();
    final date = _date;
    if (name.isEmpty) {
      setState(() => _error = 'Give the day a name first.');
      return;
    }
    if (date == null) {
      setState(() => _error = 'Pick a date first.');
      return;
    }
    final clash = findDay(
      widget.days.where((d) => d.id != widget.existing?.id).toList(),
      date,
    );
    if (clash != null) {
      setState(
          () => _error = '“${clash.name}” is already marked on that date.');
      return;
    }
    final day = DateTime(date.year, date.month, date.day);
    Navigator.pop(
      context,
      MarkedDayEntry(
        id: widget.existing?.id ??
            'c${DateTime.now().microsecondsSinceEpoch}',
        date: day,
        end: day,
        name: name,
        type: _type,
        source: widget.existing?.source ?? MarkedDaySource.custom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = _date;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'Add a day' : 'Edit day',
            style: MinecraftText.heading(fontSize: 18),
          ),
          const SizedBox(height: 16),
          const Text('Name', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('day-sheet-name'),
            controller: _nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. Foundation Day',
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          const Text('Date', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            key: const ValueKey('day-sheet-date'),
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_outlined,
                      color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Text(
                    date == null
                        ? 'Pick a date'
                        : formatMarkedDayDate(date),
                    style: TextStyle(
                      color: date == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<MarkedDayType>(
            key: const ValueKey('day-sheet-type'),
            segments: const [
              ButtonSegment(
                  value: MarkedDayType.holiday, label: Text('Holiday')),
              ButtonSegment(
                  value: MarkedDayType.noClasses, label: Text('No classes')),
              ButtonSegment(
                  value: MarkedDayType.event, label: Text('Event')),
            ],
            selected: {_type},
            onSelectionChanged: (selection) =>
                setState(() => _type = selection.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const ValueKey('day-sheet-error'),
              style: TextStyle(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: minecraftBlockButtonStyle(),
                key: const ValueKey('day-sheet-save'),
                onPressed: _saveDay,
                child: const Text('Save day'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Files scan sheet: shows the picked memo / screenshot /
/// announcement with a sweeping green scan line while the text
/// is read, then three check-offs — Reading the file, Finding
/// school days & holidays, Found N days — and returns the days
/// found (the page inserts them one by one). Nothing is invented:
/// a line only becomes a day when it carries a recognizable date
/// (see [parseSchoolDaysText]). An unreadable file, or one with
/// no dates in it, reports honestly and stays open.
class _SchoolScanSheet extends StatefulWidget {
  const _SchoolScanSheet({required this.file});

  final File file;

  @override
  State<_SchoolScanSheet> createState() => _SchoolScanSheetState();
}

class _SchoolScanSheetState extends State<_SchoolScanSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;
  bool _scanning = true;
  int _revealed = 0;
  List<ScannedSchoolDay> _found = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _run();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final service = NoteExtractService();
    final result = await service.extract(widget.file);
    if (!mounted) return;
    if (result.outcome != NoteExtractOutcome.ok ||
        result.text.trim().isEmpty) {
      setState(() {
        _scanning = false;
        _error = result.outcome == NoteExtractOutcome.empty
            ? 'No text found in this file — try a clearer photo of the memo.'
            : 'Could not read this file.';
      });
      return;
    }
    final found = parseSchoolDaysText(result.text);
    setState(() => _found = found);
    // Reveal the three check-offs one by one. The parse is
    // already done — this stagger is only so the student can see
    // each step land, exactly like the invoice scan.
    for (var step = 1; step <= 3; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      setState(() => _revealed = step);
    }
    setState(() => _scanning = false);
    if (found.isEmpty) {
      setState(() => _error =
          'No school days found in this file — try a memo with dates in it.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, found);
  }

  Widget _checkRow(int step, String label, bool revealed) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (!revealed)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.check_circle, color: scheme.primary, size: 20),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = NoteExtractService.extensionOf(widget.file.path);
    final isImage = NoteExtractService.imageExtensions.contains(ext);
    final foundCount = _found.length;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Add from a file',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            widget.file.path.split('/').last,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // File preview with the sweeping green scan line.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isImage)
                    Image.file(widget.file, fit: BoxFit.cover)
                  else
                    Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.description_outlined,
                        size: 64,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (_scanning)
                    AnimatedBuilder(
                      animation: _scanController,
                      builder: (_, _) {
                        final top = _scanController.value * 176;
                        return Positioned(
                          top: top,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary
                                      .withValues(alpha: 0.6),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _checkRow(1, 'Reading the file', _revealed >= 1),
          _checkRow(
              2, 'Finding school days & holidays', _revealed >= 2),
          _checkRow(
            3,
            _revealed >= 3
                ? (foundCount == 1
                    ? 'Found 1 day'
                    : 'Found $foundCount days')
                : 'Checking the dates',
            _revealed >= 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_error == null ? 'Cancel' : 'Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
