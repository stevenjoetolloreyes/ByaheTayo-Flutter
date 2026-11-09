// Bible Verse — devotional section (local only).
//
// TRANSLATION HONESTY: the bundled text is a CURATED selection in
// the King James Version (public domain), clearly labeled as such.
// This is NOT the full Bible: bundling a whole copyrighted
// translation offline would need a license this app does not have.
// Book/chapter navigation, topic filters, and search all work within
// this bundled set. The only translation offered is KJV — no fake
// "translation selection" with a single dead option.
// Daily reading reminders surface in-app (Verse of the Day on the
// dashboard and here); this app has no push-notification plugin.
import 'dart:async';
import '../top_popup.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_layout.dart';
import '../ios_components.dart';
import 'bible_widget_service.dart';
import 'share_card.dart';
import 'student_data.dart';

const _oldTestamentBooks = {
  'Psalm',
  'Proverbs',
  'Isaiah',
  'Jeremiah',
  'Lamentations',
};

String _testament(String book) =>
    _oldTestamentBooks.contains(book) ? 'Old Testament' : 'New Testament';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key, this.initialTab = 'daily'});

  final String initialTab;

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  Set<String> _favs = {};
  List<JournalEntry> _journal = [];
  Set<int> _planDone = {};
  String _tab = 'daily';
  String _query = '';  String _testamentFilter = 'All';
  String _bookFilter = 'All';
  String _topicFilter = 'All';
  bool _favsOnly = false;
  final _dailyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _load();
    // Push the full verse list to the home screen widget (best
    // effort, fire-and-forget) so the widget can show today's
    // verse even on days the app is never opened.
    unawaited(BibleWidgetService.syncVerses());
  }

  Future<void> _load() async {
    final favs =
        await StudentStorage.loadStrings(StudentStorage.bibleFavsKey);
    final journal =
        await StudentStorage.loadList(StudentStorage.bibleJournalKey);
    final plan =
        await StudentStorage.loadStrings(StudentStorage.biblePlanKey);
    if (!mounted) return;
    setState(() {
      _favs = favs.toSet();
      _journal = journal.map(JournalEntry.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _planDone = plan.map(int.parse).toSet();
    });
  }

  Future<void> _saveFavs() =>
      StudentStorage.saveStrings(StudentStorage.bibleFavsKey, _favs.toList());
  Future<void> _saveJournal() => StudentStorage.saveList(
      StudentStorage.bibleJournalKey,
      _journal.map((j) => j.toJson()).toList());
  Future<void> _savePlan() => StudentStorage.saveStrings(
      StudentStorage.biblePlanKey,
      _planDone.map((d) => d.toString()).toList());

  void _snack(String m) {
    if (mounted) {
      TopPopup.show(context, message: m);
    }
  }

  Future<void> _toggleFav(String id) async {
    setState(() {
      if (_favs.contains(id)) {
        _favs.remove(id);
      } else {
        _favs.add(id);
      }
    });
    await _saveFavs();
  }

  Future<void> _openVerse(BundledVerse v) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${v.ref} (KJV)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v.text, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: AppLayout.cardGap),
            Text('Topics: ${v.topics.join(', ')}',
                style: AppText.caption),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${v.ref} — ${v.text}'));
              Navigator.pop(context);
              _snack('Verse copied.');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              SharePlus.instance.share(
                  ShareParams(text: '${v.ref} (KJV)\n${v.text}'));
              Navigator.pop(context);
            },
            child: const Text('Share'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openJournalForm() async {
    final result = await showModalBottomSheet<JournalEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _JournalForm(),
    );
    if (result == null) return;
    setState(() => _journal.insert(0, result));
    await _saveJournal();
    _snack('Journal entry saved.');
  }

  @override
  Widget build(BuildContext context) {
    final daily = verseOfDay(DateTime.now());
    final books = <String>[];
    for (final v in bundledVerses) {
      if (!books.contains(v.book)) books.add(v.book);
    }
    final visibleBooks = _testamentFilter == 'All'
        ? books
        : books.where((b) => _testament(b) == _testamentFilter).toList();
    final filtered = bundledVerses.where((v) {
      if (_favsOnly && !_favs.contains(v.id)) return false;
      if (_testamentFilter != 'All' &&
          _testament(v.book) != _testamentFilter) return false;
      if (_bookFilter != 'All' && v.book != _bookFilter) return false;
      if (_topicFilter != 'All' && !v.topics.contains(_topicFilter)) {
        return false;
      }
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!v.text.toLowerCase().contains(q) &&
            !v.ref.toLowerCase().contains(q) &&
            !v.book.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Bible Verse')),
      floatingActionButton: _tab == 'journal'
          ? FloatingActionButton.extended(
              onPressed: _openJournalForm,
              icon: const Icon(Icons.add),
              label: const Text('Add entry'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: IosSegmentedControl<String>(
              segments: const [
                IosSegment(value: 'daily', label: 'Daily'),
                IosSegment(value: 'verses', label: 'Verses'),
                IosSegment(value: 'journal', label: 'Journal'),
                IosSegment(value: 'plan', label: 'Plan'),
              ],
              groupValue: _tab,
              onValueChanged: (value) => setState(() => _tab = value),
            ),
          ),
          Expanded(
            child: ListView(
              padding: AppLayout.pagePaddingTab,
              children: [
                if (_tab == 'daily') ...[
                  const Text('Verse of the Day',
                      style: AppText.sectionTitle),
                  const SizedBox(height: AppSpacing.s8),
                  RepaintBoundary(
                    key: _dailyKey,
                    child: shareCardContent(
                      body: daily.text,
                      attribution: '${daily.ref} (KJV)',
                      footer: 'EstudyanteGO · Bible Verse',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text:
                                    '${daily.ref} (KJV)\n${daily.text}'));
                            _snack('Verse copied.');
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => shareBoundaryAsImage(
                            boundaryKey: _dailyKey,
                            filename: 'byahetayo-verse.png',
                            fallbackText:
                                '${daily.ref} (KJV)\n${daily.text}',
                          ),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Share image'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      IconButton(
                        icon: Icon(
                          _favs.contains(daily.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _favs.contains(daily.id)
                              ? Colors.red
                              : null,
                        ),
                        onPressed: () => _toggleFav(daily.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.headerGap),
                  const Card(
                    child: ListTile(
                      title: Text('Translation: King James Version '
                          '(public domain)'),
                      subtitle: Text(
                          'This is a curated selection of verses, not the full Bible text. More translations need licensed sources.'),
                    ),
                  ),
                ] else if (_tab == 'verses') ...[
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search keyword or reference (e.g. John 3)…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        selected: _favsOnly,
                        onSelected: (v) => setState(() => _favsOnly = v),
                      ),
                      for (final t in [
                        'All',
                        'Old Testament',
                        'New Testament'
                      ])
                        ChoiceChip(
                          label: Text(t),
                          selected: _testamentFilter == t,
                          onSelected: (_) => setState(() {
                            _testamentFilter = t;
                            _bookFilter = 'All';
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _bookFilter,
                          decoration: const InputDecoration(
                              labelText: 'Book', isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: 'All', child: Text('All books')),
                            for (final b in visibleBooks)
                              DropdownMenuItem(value: b, child: Text(b)),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _bookFilter = v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _topicFilter,
                          decoration: const InputDecoration(
                              labelText: 'Topic', isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: 'All', child: Text('All topics')),
                            for (final t in verseTopics)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _topicFilter = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.cardGap),
                  if (filtered.isEmpty)
                    const Card(
                        child: ListTile(title: Text('No verses found.')))
                  else
                    for (final v in filtered)
                      Card(
                        child: ListTile(
                          title: Text(v.text),
                          subtitle: Text(
                              '${v.ref} (KJV) · ${_testament(v.book)} · ${v.topics.join(', ')}'),
                          trailing: IconButton(
                            icon: Icon(
                              _favs.contains(v.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _favs.contains(v.id)
                                  ? Colors.red
                                  : null,
                              size: 20,
                            ),
                            onPressed: () => _toggleFav(v.id),
                          ),
                          onTap: () => _openVerse(v),
                        ),
                      ),
                ] else if (_tab == 'journal') ...[
                  const Text(
                    'Your own devotional reflections and prayers. '
                    'These are private to this device.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (_journal.isEmpty)
                    const Card(
                        child: ListTile(
                            title: Text('No journal entries yet.')))
                  else
                    for (final j in _journal)
                      Card(
                        child: ListTile(
                          title: Text(j.text),
                          subtitle: Text(
                              '${j.kind == 'prayer' ? 'Prayer' : 'Devotional'} · ${j.ref.isEmpty ? formatDate(j.date) : '${j.ref} · ${formatDate(j.date)}'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (j.kind == 'prayer')
                                Checkbox(
                                  value: j.answered,
                                  onChanged: (v) async {
                                    setState(() {
                                      final idx = _journal.indexWhere(
                                          (x) => x.id == j.id);
                                      if (idx >= 0) {
                                        _journal[idx] = JournalEntry(
                                          id: j.id,
                                          kind: j.kind,
                                          ref: j.ref,
                                          text: j.text,
                                          date: j.date,
                                          answered: v ?? false,
                                        );
                                      }
                                    });
                                    await _saveJournal();
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                onPressed: () async {
                                  setState(() => _journal.removeWhere(
                                      (x) => x.id == j.id));
                                  await _saveJournal();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                ] else ...[
                  LinearProgressIndicator(
                    value: biblePlanDays.isEmpty
                        ? 0
                        : _planDone.length / biblePlanDays.length,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                      'Reading plan: ${_planDone.length}/${biblePlanDays.length} days done'),
                  const SizedBox(height: AppLayout.cardGap),
                  for (var i = 0; i < biblePlanDays.length; i++)
                    Card(
                      child: ExpansionTile(
                        leading: Checkbox(
                          value: _planDone.contains(i),
                          onChanged: (v) async {
                            setState(() {
                              if (v == true) {
                                _planDone.add(i);
                              } else {
                                _planDone.remove(i);
                              }
                            });
                            await _savePlan();
                          },
                        ),
                        title: Text(biblePlanDays[i].$1),
                        children: [
                          for (final id in biblePlanDays[i].$2)
                            Builder(builder: (_) {
                              final v = findVerse(id);
                              if (v == null) {
                                return const SizedBox.shrink();
                              }
                              return ListTile(
                                title: Text(v.text),
                                subtitle: Text('${v.ref} (KJV)'),
                                trailing: IconButton(
                                  icon: Icon(
                                    _favs.contains(v.id)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: _favs.contains(v.id)
                                        ? Colors.red
                                        : null,
                                    size: 20,
                                  ),
                                  onPressed: () => _toggleFav(v.id),
                                ),
                                onTap: () => _openVerse(v),
                              );
                            }),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalForm extends StatefulWidget {
  const _JournalForm();

  @override
  State<_JournalForm> createState() => _JournalFormState();
}

class _JournalFormState extends State<_JournalForm> {
  String _kind = 'devotional';
  final _ref = TextEditingController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    _text.dispose();
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
          const Text('New journal entry',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppLayout.cardGap),
          IosSegmentedControl<String>(
            segments: const [
              IosSegment(value: 'devotional', label: 'Devotional'),
              IosSegment(value: 'prayer', label: 'Prayer'),
            ],
            groupValue: _kind,
            onValueChanged: (value) => setState(() => _kind = value),
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _ref,
            decoration: const InputDecoration(
                labelText: 'Verse reference (optional, e.g. John 3:16)'),
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _text,
            decoration: InputDecoration(
                labelText: _kind == 'prayer'
                    ? 'Your prayer'
                    : 'Your reflection'),
            maxLines: 5,
          ),
          const SizedBox(height: AppLayout.cardGap),
          FilledButton(
            onPressed: () {
              if (_text.text.trim().isEmpty) {
                TopPopup.show(context, message: 'Write something first.');
                return;
              }
              Navigator.pop(
                context,
                JournalEntry(
                  id: newId(),
                  kind: _kind,
                  ref: _ref.text.trim(),
                  text: _text.text.trim(),
                  date: DateTime.now(),
                  answered: false,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
