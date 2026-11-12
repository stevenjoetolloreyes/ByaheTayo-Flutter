// Daily Quotes — motivational quote library (local only).
//
// Quote of the Day rotates deterministically by day-of-year over the
// bundled set (no network). Favorites, custom collections, search,
// category filter, and a real recently-viewed history are all stored
// on-device. The featured card shares as a real PNG image (rendered
// from the card widget); list quotes share as text. Daily system
// notifications are NOT included — this app has no push-notification
// plugin, so the Daily quote surfaces on the dashboard and here.
import 'dart:async';

import 'package:flutter/material.dart';
import '../top_popup.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_layout.dart';
import '../minecraft_theme.dart';
import 'share_card.dart';
import 'daily_quotes_widget_service.dart';
import 'student_data.dart';

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  Set<String> _favs = {};
  List<QuoteCollection> _collections = [];
  List<String> _history = [];
  String _query = '';
  String _category = 'All';
  bool _favsOnly = false;
  final _dailyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    // Home screen widgets (Nov 11): the quote of the day
    // rotates daily — push today's quote to the widget.
    unawaited(DailyQuotesWidgetService.syncQuotes());
  }

  Future<void> _load() async {
    final favs =
        await StudentStorage.loadStrings(StudentStorage.quoteFavsKey);
    final collections =
        await StudentStorage.loadList(StudentStorage.quoteCollectionsKey);
    final history =
        await StudentStorage.loadStrings(StudentStorage.quoteHistoryKey);
    if (!mounted) return;
    setState(() {
      _favs = favs.toSet();
      _collections = collections.map(QuoteCollection.fromJson).toList();
      _history = history;
    });
  }

  Future<void> _saveFavs() =>
      StudentStorage.saveStrings(StudentStorage.quoteFavsKey, _favs.toList());
  Future<void> _saveCollections() => StudentStorage.saveList(
      StudentStorage.quoteCollectionsKey,
      _collections.map((c) => c.toJson()).toList());
  Future<void> _saveHistory() =>
      StudentStorage.saveStrings(StudentStorage.quoteHistoryKey, _history);

  void _snack(String m) {
    if (mounted) {
      TopPopup.show(context, message: m);
    }
  }

  void _recordView(String id) {
    setState(() {
      _history.remove(id);
      _history.insert(0, id);
      if (_history.length > 20) _history = _history.sublist(0, 20);
    });
    _saveHistory();
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

  Future<void> _addToCollection(BundledQuote q) async {
    final name = TextEditingController();
    String? picked =
        _collections.isEmpty ? null : _collections.first.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add to collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_collections.isNotEmpty)
              DropdownButtonFormField<String>(
                value: picked,
                decoration:
                    const InputDecoration(labelText: 'Collection'),
                items: [
                  for (final c in _collections)
                    DropdownMenuItem(value: c.name, child: Text(c.name)),
                ],
                onChanged: (v) => picked = v,
              ),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'Or create a new collection'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: minecraftBlockButtonStyle(),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final target = name.text.trim().isNotEmpty ? name.text.trim() : picked;
    if (target == null || target.isEmpty) return;
    setState(() {
      final idx = _collections.indexWhere((c) => c.name == target);
      if (idx >= 0) {
        if (!_collections[idx].ids.contains(q.id)) {
          _collections[idx].ids.add(q.id);
        }
      } else {
        _collections.add(QuoteCollection(name: target, ids: [q.id]));
      }
    });
    await _saveCollections();
    _snack('Added to $target.');
  }

  Future<void> _openDetail(BundledQuote q) async {
    _recordView(q.id);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(q.category),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${q.text}"',
                style: MinecraftText.title(fontSize: 17)),
            const SizedBox(height: AppLayout.cardGap),
            Text('— ${q.author}',
                style: MinecraftText.bodySemiBold()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: '"${q.text}" — ${q.author}'));
              Navigator.pop(context);
              _snack('Quote copied.');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              SharePlus.instance.share(ShareParams(
                  text: '"${q.text}" — ${q.author}'));
              Navigator.pop(context);
            },
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _addToCollection(q);
            },
            child: const Text('Collect'),
          ),
          FilledButton(
            style: minecraftBlockButtonStyle(),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = quoteOfDay(DateTime.now());
    final filtered = bundledQuotes.where((q) {
      if (_favsOnly && !_favs.contains(q.id)) return false;
      if (_category != 'All' && q.category != _category) return false;
      if (_query.isNotEmpty) {
        final query = _query.toLowerCase();
        if (!q.text.toLowerCase().contains(query) &&
            !q.author.toLowerCase().contains(query)) return false;
      }
      return true;
    }).toList();
    final historyQuotes = _history
        .map(_quoteById)
        .whereType<BundledQuote>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Quotes')),
      body: ListView(
        padding: AppLayout.pagePaddingTab,
        children: [
          const MinecraftSectionHeader(
            icon: Icons.format_quote_rounded,
            title: 'Quote of the Day',
          ),
          const SizedBox(height: AppSpacing.s8),
          RepaintBoundary(
            key: _dailyKey,
            child: shareCardContent(
              body: '"${daily.text}"',
              attribution: '— ${daily.author}',
              footer: 'EstudyanteGO · Daily Quotes',
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: minecraftOutlinedButtonStyle(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: '"${daily.text}" — ${daily.author}'));
                    _snack('Quote copied.');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: OutlinedButton.icon(
                  style: minecraftOutlinedButtonStyle(),
                  onPressed: () => shareBoundaryAsImage(
                    boundaryKey: _dailyKey,
                    filename: 'byahetayo-quote.png',
                    fallbackText: '"${daily.text}" — ${daily.author}',
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
                  color: _favs.contains(daily.id) ? MinecraftColors.heartRed : null,
                ),
                onPressed: () => _toggleFav(daily.id),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search quotes or authors…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Favorites'),
                  selected: _favsOnly,
                  onSelected: (v) => setState(() => _favsOnly = v),
                ),
                const SizedBox(width: 6),
                for (final c in ['All', ...quoteCategories])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          if (filtered.isEmpty)
            const MinecraftCard(padding: EdgeInsets.zero, child: ListTile(title: Text('No quotes found.')))
          else
            for (final q in filtered)
              MinecraftCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  title: Text('"${q.text}"'),
                  subtitle: Text('— ${q.author} · ${q.category}'),
                  trailing: IconButton(
                    icon: Icon(
                      _favs.contains(q.id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: _favs.contains(q.id)
                          ? MinecraftColors.heartRed
                          : null,
                      size: 20,
                    ),
                    onPressed: () => _toggleFav(q.id),
                  ),
                  onTap: () => _openDetail(q),
                ),
              ),
          if (_collections.isNotEmpty) ...[
            const SizedBox(height: 20),
            const MinecraftSectionHeader(
              icon: Icons.collections_bookmark_rounded,
              title: 'My collections',
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final c in _collections)
              MinecraftCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: Text('${c.name} (${c.ids.length})'),
                  children: [
                    for (final id in c.ids)
                      Builder(builder: (_) {
                        final q = _quoteById(id);
                        if (q == null) return const SizedBox.shrink();
                        return ListTile(
                          title: Text('"${q.text}"'),
                          subtitle: Text('— ${q.author}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 20),
                            onPressed: () async {
                              setState(() => c.ids.remove(id));
                              await _saveCollections();
                            },
                          ),
                          onTap: () => _openDetail(q),
                        );
                      }),
                  ],
                ),
              ),
          ],
          if (historyQuotes.isNotEmpty) ...[
            const SizedBox(height: 20),
            const MinecraftSectionHeader(
              icon: Icons.history_rounded,
              title: 'Recently viewed',
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final q in historyQuotes)
              MinecraftCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  title: Text('"${q.text}"'),
                  subtitle: Text('— ${q.author}'),
                  onTap: () => _openDetail(q),
                ),
              ),
          ],
          const SizedBox(height: AppLayout.headerGap),
        ],
      ),
    );
  }
}

BundledQuote? _quoteById(String id) {
  for (final q in bundledQuotes) {
    if (q.id == id) return q;
  }
  return null;
}
