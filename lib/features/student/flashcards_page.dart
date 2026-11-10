// Flashcards Page — one of the two dedicated Review pages.
//
// The old "Review Notes & Quizzes" screen (NotesScreen) is gone.
// This page owns flashcards only: the deck list, "Study all
// cards" flip mode (progress + shuffle + remembered/needs-review
// marks), delete per card, and "+ Add card".
//
// Data is the user's own saved cards (StudentStorage.flashcardsKey).
// While the user has none, the built-in "Computer Basics" sample
// deck shows instead, clearly labelled "Sample" — it is never
// written to storage, and it disappears as soon as the user adds
// their first real card. Sample cards cannot be deleted (there is
// nothing saved to delete).
import 'package:flutter/material.dart';

import '../estudyantego_ai.dart';
import '../minecraft_theme.dart';
import '../top_popup.dart';
import '../app_layout.dart';
import 'student_data.dart';

class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage({super.key});

  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  List<Flashcard> _cards = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await StudentStorage.loadList(StudentStorage.flashcardsKey);
    if (!mounted) return;
    setState(() {
      _cards = cards.map(Flashcard.fromJson).toList();
      _loaded = true;
    });
  }

  Future<void> _saveCards() => StudentStorage.saveList(
    StudentStorage.flashcardsKey,
    _cards.map((c) => c.toJson()).toList(),
  );

  /// Cards to show: the user's real cards, or the sample deck
  /// while they have none.
  List<Flashcard> get _visibleCards =>
      _cards.isEmpty ? sampleComputerBasicsDeck.flashcards : _cards;

  bool get _showingSample => _cards.isEmpty;

  Future<void> _openCardForm() async {
    final result = await showModalBottomSheet<Flashcard>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CardForm(),
    );
    if (result == null) return;
    setState(() => _cards.add(result));
    await _saveCards();
    if (mounted) {
      TopPopup.show(context, message: 'Flashcard added.');
    }
  }

  Future<void> _deleteCard(Flashcard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete flashcard?'),
        content: Text(card.front),
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
    setState(() => _cards.removeWhere((x) => x.id == card.id));
    await _saveCards();
  }

  Future<void> _studyAll() async {
    final cards = _visibleCards;
    if (cards.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _StudyMode(
          cards: cards,
          readOnly: _showingSample,
          onDeckChanged: _showingSample
              ? null
              : (deck) async {
                  setState(() => _cards = deck);
                  await _saveCards();
                },
        ),
      ),
    );
    // Marks may have changed while studying — reload so the list
    // never shows stale study statuses.
    await _load();
  }

  /// Cards grouped into decks by subject, in first-appearance
  /// order (Minecraft restyle, Feature 3): the preview's
  /// 'Flashcard Chests' are decks saved per subject, and the real
  /// cards already carry a subject — so the decks are the live
  /// groups, never invented, never seeded. The list order inside
  /// a deck is unchanged; only the grouping headers are new.
  List<({String subject, List<Flashcard> cards})> get _decks {
    final order = <String>[];
    final bySubject = <String, List<Flashcard>>{};
    for (final card in _visibleCards) {
      final subject = card.subject.isEmpty ? 'No subject' : card.subject;
      if (!bySubject.containsKey(subject)) {
        bySubject[subject] = [];
        order.add(subject);
      }
      bySubject[subject]!.add(card);
    }
    return [for (final s in order) (subject: s, cards: bySubject[s]!)];
  }

  @override
  Widget build(BuildContext context) {
    final cards = _visibleCards;
    final decks = _decks;
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcards')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCardForm,
        icon: const Icon(Icons.add),
        label: const Text('Add card'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppLayout.pagePaddingTab,
              children: [
                if (_showingSample)
                  MinecraftCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const MinecraftIconBadge(
                        icon: Icons.info_outline,
                        backgroundColor: MinecraftColors.skyBlue,
                      ),
                      title: Text(
                        'Sample deck',
                        style: MinecraftText.title(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Computer Basics — try the flip mode below. '
                        'Add your first card and this sample goes away.',
                        style: MinecraftText.body(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                if (_showingSample) const SizedBox(height: AppSpacing.s8),
                SizedBox(
                  width: double.infinity,
                  child: MinecraftBlockButton(
                    label: 'Study all cards',
                    icon: Icons.play_arrow,
                    onPressed: cards.isEmpty ? null : _studyAll,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                if (cards.isEmpty)
                  MinecraftCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        'No flashcards yet.',
                        style: MinecraftText.title(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Add a card with the definition on the front and the term on the back.',
                        style: MinecraftText.body(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < decks.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.s12),
                    _DeckChest(deck: decks[i], index: i),
                    const SizedBox(height: AppSpacing.s8),
                    for (final card in decks[i].cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MinecraftCard(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(
                              card.front,
                              style: MinecraftText.title(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              '${card.subject.isEmpty ? 'No subject' : card.subject} · Answer: ${card.back}',
                              style: MinecraftText.body(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            trailing: _showingSample
                                ? null
                                : IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                    onPressed: () => _deleteCard(card),
                                  ),
                          ),
                        ),
                      ),
                  ],
                const SizedBox(height: 72),
              ],
            ),
    );
  }
}

/// One flashcard chest header (Minecraft restyle, Feature 3):
/// the preview's deck card — a box / box-open badge by mastery,
/// the subject as the deck title, the REAL card count and
/// mastered count, and the REAL mastery % chip. The badge opens
/// (gold) at 50% mastery or more and stays a closed box below
/// that. The deck's cards list right below the chest.
class _DeckChest extends StatelessWidget {
  const _DeckChest({required this.deck, required this.index});

  final ({String subject, List<Flashcard> cards}) deck;
  final int index;

  @override
  Widget build(BuildContext context) {
    final total = deck.cards.length;
    final mastered = deck.cards
        .where((c) => c.studyStatus == 'remembered')
        .length;
    final pct = total == 0 ? 0 : (mastered * 100 / total).round();
    final open = total > 0 && pct >= 50;
    return MinecraftQuestCard(
      key: Key('flashcard-chest-$index'),
      badgeIcon: open ? Icons.inbox : Icons.inventory_2,
      badgeColor: open ? MinecraftColors.gold : MinecraftColors.purple,
      badgeIconColor: open ? MinecraftColors.ink : Colors.white,
      title: deck.subject,
      details: '$total card${total == 1 ? '' : 's'} · $mastered mastered',
      chip: MinecraftStatusChip('$pct%'),
    );
  }
}

class _CardForm extends StatefulWidget {
  const _CardForm();

  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  final _front = TextEditingController();
  final _back = TextEditingController();
  final _subject = TextEditingController();

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _subject.dispose();
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
            'Add flashcard',
            style: MinecraftText.heading(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: AppLayout.cardGap),
          TextField(
            controller: _front,
            decoration: const InputDecoration(labelText: 'Front (definition)'),
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _back,
            decoration: const InputDecoration(labelText: 'Back (term)'),
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject (optional)'),
          ),
          const SizedBox(height: AppLayout.cardGap),
          SizedBox(
            width: double.infinity,
            child: MinecraftBlockButton(
              label: 'Save',
              icon: Icons.save_outlined,
              onPressed: () {
                if (_front.text.trim().isEmpty || _back.text.trim().isEmpty) {
                  TopPopup.show(
                    context,
                    message: 'Fill in both front and back.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  Flashcard(
                    id: newId(),
                    front: _front.text.trim(),
                    back: _back.text.trim(),
                    subject: _subject.text.trim(),
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

/// Flip-mode study: one card at a time, tap to flip, progress bar
/// + remembered/needs-review counts, Previous / Shuffle / Next.
/// Marks persist through [onDeckChanged]; when [readOnly] is true
/// (the sample deck) marks are session-only.
class _StudyMode extends StatefulWidget {
  const _StudyMode({
    required this.cards,
    this.onDeckChanged,
    this.readOnly = false,
  });

  final List<Flashcard> cards;

  /// Called with the updated deck whenever a card is marked, so
  /// the parent can persist the mark. Null = session-only marks.
  final Future<void> Function(List<Flashcard> deck)? onDeckChanged;

  /// Sample deck: marks are not persisted.
  final bool readOnly;

  @override
  State<_StudyMode> createState() => _StudyModeState();
}

class _StudyModeState extends State<_StudyMode> {
  late List<Flashcard> _deck;
  int _index = 0;
  bool _flipped = false;
  final Map<String, String> _marks = {};

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.cards);
    for (final card in _deck) {
      if (card.studyStatus.isNotEmpty) _marks[card.id] = card.studyStatus;
    }
  }

  int get _remembered => _marks.values.where((s) => s == 'remembered').length;
  int get _needsReview => _marks.values.where((s) => s == 'needsReview').length;
  int get _remaining => _deck.length - _remembered - _needsReview;

  void _mark(String status) {
    final card = _deck[_index];
    final updated = Flashcard(
      id: card.id,
      front: card.front,
      back: card.back,
      subject: card.subject,
      studyStatus: status,
    );
    setState(() {
      _deck[_index] = updated;
      _marks[card.id] = status;
    });
    widget.onDeckChanged?.call(List.of(_deck));
  }

  @override
  Widget build(BuildContext context) {
    final card = _deck[_index];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('Card ${_index + 1} of ${_deck.length}')),
      body: Padding(
        padding: AppLayout.pagePaddingTab,
        child: Column(
          children: [
            Text(
              'Remembered $_remembered · Needs review $_needsReview · '
              'Remaining $_remaining',
              style: MinecraftText.caption(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            // Blocky progress track around the same
            // LinearProgressIndicator (kept as-is: the flip-mode
            // tests find it by type).
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark
                      ? MinecraftColors.darkBorder
                      : MinecraftColors.border,
                  width: MinecraftShapes.cardBorderWidth,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: _deck.isEmpty
                      ? 0
                      : (_remembered + _needsReview) / _deck.length,
                  backgroundColor: MinecraftColors.cream,
                  color: MinecraftColors.grassGreen,
                  minHeight: 10,
                ),
              ),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _flipped = !_flipped),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.95,
                        end: 1.0,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: MinecraftCard(
                    key: ValueKey(_flipped),
                    padding: EdgeInsets.zero,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _flipped ? 'Term' : 'Definition',
                              style: MinecraftText.button(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppLayout.cardGap),
                            Text(
                              _flipped ? card.back : card.front,
                              textAlign: TextAlign.center,
                              style: MinecraftText.heading(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: AppLayout.headerGap),
                            Text(
                              _flipped
                                  ? 'Tap the card to flip back'
                                  : 'Tap the card to reveal the term',
                              style: MinecraftText.caption(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppLayout.cardGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _mark('needsReview'),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Needs review'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _mark('remembered'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Remembered'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayout.cardGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() {
                            _index--;
                            _flipped = false;
                          }),
                    child: const Text('Previous'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _deck.shuffle();
                      _index = 0;
                      _flipped = false;
                    }),
                    child: const Text('Shuffle'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FilledButton(
                    onPressed: _index == _deck.length - 1
                        ? null
                        : () => setState(() {
                            _index++;
                            _flipped = false;
                          }),
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
