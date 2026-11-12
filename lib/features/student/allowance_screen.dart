// Allowance Management — personal allowance tracker (local only).
//
// Balance = total income − total expenses. Budgets are monthly
// per-category limits with an in-app over-budget banner (this app has
// no push-notification plugin, so alerts surface here, not as system
// notifications). CSV export shares a real file via share_plus.
//
// Money redesign (Nov 9, 2026, approved preview): the spending chart
// calls out the biggest month (tallest green bar, "Most spent in
// …"), transactions group by day with category icons, the floating
// + lives ONLY on this screen (never on the hub card) and opens a
// spring menu — Add transaction Manual, or Files: a real invoice
// scan (ML Kit OCR / PDF text via NoteExtractService, parsed by
// invoice_scan.dart), reviewed and edited before confirming, then
// inserted one by one with a soft pop-chime per landing.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_layout.dart';
import '../minecraft_theme.dart';
import '../ios_components.dart';
import '../local_notifications.dart';
import '../onboarding/splash_sound.dart';
import '../top_popup.dart';
import 'invoice_scan.dart';
import 'note_extract_service.dart';
import 'allowance_widget_service.dart';
import 'student_data.dart';

const _expenseCategories = [
  'Food',
  'Transport',
  'School',
  'Load',
  'Entertainment',
  'Health',
  'Other',
];

const _incomeCategories = ['Allowance', 'Gift', 'Extra', 'Other'];

/// Category / merchant icon for a transaction row. A merchant
/// keyword in the note wins (a GCash load is a phone even when its
/// category is Load); otherwise the category decides.
IconData allowanceTxnIcon(AllowanceTxn t) {
  final text = '${t.note} ${t.category}'.toLowerCase();
  if (text.contains('gcash') || text.contains('load')) {
    return Icons.phone_android;
  }
  if (text.contains('grab') ||
      text.contains('food') ||
      text.contains('jollibee') ||
      text.contains('burger') ||
      text.contains('mcdonald') ||
      text.contains('restaurant') ||
      text.contains('chicken') ||
      text.contains('pizza')) {
    return Icons.fastfood_outlined;
  }
  if (text.contains('fare') ||
      text.contains('bus') ||
      text.contains('jeep') ||
      text.contains('tricycle')) {
    return Icons.directions_bus_outlined;
  }
  switch (t.category) {
    case 'Food':
      return Icons.fastfood_outlined;
    case 'Transport':
      return Icons.directions_bus_outlined;
    case 'School':
      return Icons.school_outlined;
    case 'Load':
      return Icons.phone_android_outlined;
    case 'Entertainment':
      return Icons.movie_outlined;
    case 'Health':
      return Icons.local_hospital_outlined;
    case 'Allowance':
      return Icons.account_balance_wallet_outlined;
    case 'Gift':
      return Icons.card_giftcard_outlined;
    case 'Extra':
      return Icons.attach_money_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

/// Monthly spending bar chart, shared by the hub card and this
/// screen so the two can never disagree: the biggest month is the
/// tallest green bar, months with no spending are short faint gray
/// bars, and the total carries its date range plus a
/// "Most spent in …" callout.
class MoneySpendingChart extends StatelessWidget {
  const MoneySpendingChart({
    super.key,
    required this.bars,
    required this.totalSpent,
    required this.now,
    this.barHeight = 56,
    this.barWidth = 18,
  });

  final List<({String label, double amount})> bars;
  final double totalSpent;
  final DateTime now;
  final double barHeight;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxBar =
        bars.fold<double>(0, (m, b) => b.amount > m ? b.amount : m);
    final maxLabel = maxBar > 0
        ? bars.firstWhere((b) => b.amount == maxBar).label
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: barHeight + 40,
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      height: 1,
                      color: scheme.outline.withValues(alpha: 0.5),
                    ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in bars)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // One line only: a long value ("₱1,020")
                          // shrinks instead of wrapping into the bar.
                          SizedBox(
                            height: 12,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                peso(b.amount),
                                style: AppText.micro.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: maxBar > 0
                                ? barHeight * (b.amount / maxBar)
                                : 2,
                            width: barWidth,
                            decoration: BoxDecoration(
                              color: b.amount == maxBar && maxBar > 0
                                  ? scheme.primary
                                  : b.amount > 0
                                      ? scheme.primary
                                          .withValues(alpha: 0.5)
                                      : scheme.outline
                                          .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(b.label, style: AppText.micro),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          '${peso(totalSpent)} Total spent',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (totalSpent == 0)
          Text(
            'No spending recorded in the last 6 months.',
            style: AppText.caption
                .copyWith(color: scheme.onSurfaceVariant),
          )
        else ...[
          Text(
            'Total across ${spendingRangeLabel(now, bars.length)}, '
            'from your expense transactions.',
            style: AppText.caption
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          if (maxLabel != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Row(
              children: [
                Icon(Icons.trending_up,
                    size: 14, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Most spent in $maxLabel',
                  style: AppText.caption.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class AllowanceScreen extends StatefulWidget {
  const AllowanceScreen({super.key});

  @override
  State<AllowanceScreen> createState() => _AllowanceScreenState();
}

/// One-shot green flash for a just-inserted scan row (1.0 → 0.0).
/// Kept as one shared instance so rebuilds never restart it
/// mid-fade.
final _flashTween = Tween<double>(begin: 1.0, end: 0.0);

class _AllowanceScreenState extends State<AllowanceScreen>
    with SingleTickerProviderStateMixin {
  List<AllowanceTxn> _txns = [];
  List<SavingsGoal> _goals = [];
  List<BudgetLimit> _budgets = [];
  String _query = '';
  String _kindFilter = 'all';
  String _catFilter = 'all';

  // Floating + spring menu (this screen only — never on the hub card).
  bool _fabMenuOpen = false;
  late final AnimationController _fabController;

  // Transactions just inserted by a scan: green flash + "New" badge
  // until the batch settles a few seconds later.
  final Set<String> _justInserted = {};
  final Map<String, GlobalKey> _txnKeys = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _load();
  }

  @override
  void dispose() {
    _fabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final txns = await StudentStorage.loadList(StudentStorage.txnsKey);
    final goals = await StudentStorage.loadList(StudentStorage.goalsKey);
    final budgets = await StudentStorage.loadList(StudentStorage.budgetsKey);
    if (!mounted) return;
    setState(() {
      _txns = txns.map(AllowanceTxn.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _goals = goals.map(SavingsGoal.fromJson).toList();
      _budgets = budgets.map(BudgetLimit.fromJson).toList();
    });
  }

  Future<void> _saveTxns() async {
    await StudentStorage.saveList(
        StudentStorage.txnsKey, _txns.map((t) => t.toJson()).toList());
    // Home screen widgets (Nov 11): the balance changed —
    // push the stored transactions to the Allowance widget.
    unawaited(AllowanceWidgetService.sync());
    requestLocalNotificationRefresh();
  }
  Future<void> _saveGoals() async {
    await StudentStorage.saveList(
        StudentStorage.goalsKey, _goals.map((g) => g.toJson()).toList());
    // Home screen widgets (Nov 11): a savings goal changed —
    // push the stored goals to the Money widget.
    unawaited(AllowanceWidgetService.sync());
  }
  Future<void> _saveBudgets() async {
    await StudentStorage.saveList(
        StudentStorage.budgetsKey, _budgets.map((b) => b.toJson()).toList());
    // Home screen widgets (Nov 11): a budget limit changed —
    // push the stored budgets to the Money widget.
    unawaited(AllowanceWidgetService.sync());
    requestLocalNotificationRefresh();
  }

  void _snack(String m) {
    if (mounted) {
      TopPopup.show(context, message: m);
    }
  }

  Future<void> _exportCsv() async {
    final rows = <List<String>>[
      ['date', 'kind', 'category', 'amount', 'note'],
      for (final t in _txns)
        [
          t.date.toIso8601String().split('T').first,
          t.kind,
          t.category,
          t.amount.toStringAsFixed(2),
          t.note,
        ],
    ];
    final file = File('${Directory.systemTemp.path}/allowance.csv');
    await file.writeAsString(toCsv(rows));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _openTxnForm({AllowanceTxn? existing}) async {
    final result = await showModalBottomSheet<AllowanceTxn>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TxnForm(existing: existing),
    );
    if (result == null) return;
    setState(() {
      _txns.removeWhere((t) => t.id == result.id);
      _txns.insert(0, result);
      _txns.sort((a, b) => b.date.compareTo(a.date));
    });
    await _saveTxns();
    _snack(existing == null ? 'Transaction added.' : 'Transaction updated.');
  }

  Future<void> _deleteTxn(AllowanceTxn t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('${t.category} · ${peso(t.amount)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _txns.removeWhere((x) => x.id == t.id));
    await _saveTxns();
  }

  Future<void> _openGoalForm() async {
    final name = TextEditingController();
    final target = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New savings goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Goal name')),
            TextField(
              controller: target,
              decoration: const InputDecoration(labelText: 'Target amount'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final amount = double.tryParse(target.text) ?? 0;
    if (amount <= 0) {
      _snack('Enter a target amount greater than zero.');
      return;
    }
    setState(() => _goals.add(SavingsGoal(
        id: newId(), name: name.text.trim(), target: amount, saved: 0)));
    await _saveGoals();
  }

  Future<void> _addToGoal(SavingsGoal g) async {
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add savings to ${g.name}'),
        content: TextField(
          controller: amount,
          decoration: const InputDecoration(labelText: 'Amount set aside'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final value = double.tryParse(amount.text) ?? 0;
    if (value <= 0) return;
    setState(() {
      final i = _goals.indexWhere((x) => x.id == g.id);
      if (i >= 0) {
        _goals[i] = SavingsGoal(
            id: g.id,
            name: g.name,
            target: g.target,
            saved: g.saved + value);
      }
    });
    await _saveGoals();
  }

  Future<void> _openBudgetForm() async {
    String category = _expenseCategories.first;
    final limit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Monthly budget limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: category,
              items: [
                for (final c in _expenseCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) {
                if (v != null) category = v;
              },
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            TextField(
              controller: limit,
              decoration: const InputDecoration(labelText: 'Monthly limit'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final value = double.tryParse(limit.text) ?? 0;
    if (value <= 0) return;
    setState(() {
      _budgets.removeWhere((b) => b.category == category);
      _budgets.add(
          BudgetLimit(id: newId(), category: category, limit: value));
    });
    await _saveBudgets();
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

  /// Files: pick a receipt / statement / screenshot, scan it for
  /// transactions, let the student review and edit the drafts,
  /// then insert them one by one with a pop-chime per landing.
  Future<void> _scanInvoice() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (picked == null || picked.path == null || !mounted) return;
    final drafts = await showModalBottomSheet<List<ScannedTxn>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _InvoiceScanSheet(file: File(picked.path!)),
      ),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    await _insertScanned(drafts);
  }

  /// Inserts confirmed scan drafts one by one (~0.5 s apart): each
  /// springs into the list with a green flash and a "New" badge, a
  /// soft pop-chime plays the moment it lands, and the list scrolls
  /// to it. No sound on menu open, scan, or finish.
  Future<void> _insertScanned(List<ScannedTxn> drafts) async {
    var i = 0;
    for (final d in drafts) {
      if (!mounted) return;
      i++;
      final txn = AllowanceTxn(
        id: newId(),
        kind: d.kind,
        amount: d.amount,
        category: d.category,
        note: d.title,
        date: d.date,
      );
      setState(() {
        _txns.add(txn);
        _txns.sort((a, b) => b.date.compareTo(a.date));
        _justInserted.add(txn.id);
      });
      SplashSound.pop();
      _snack('Inserting $i of ${drafts.length}…');
      await _scrollToTxn(txn.id);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await _saveTxns();
    if (!mounted) return;
    _snack(
        '${drafts.length} transaction${drafts.length == 1 ? '' : 's'} added '
        'from the scan — balance, chart, and hub card updated.');
    await Future<void>.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _justInserted.clear());
  }

  Future<void> _scrollToTxn(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final context = _txnKeys[id]?.currentContext;
    if (context != null && mounted) {
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
    final now = DateTime.now();
    final balance = allowanceBalance(_txns);
    final month = monthTotals(_txns, now.year, now.month);
    final filtered = _txns.where((t) {
      if (_kindFilter != 'all' && t.kind != _kindFilter) return false;
      if (_catFilter != 'all' && t.category != _catFilter) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!t.category.toLowerCase().contains(q) &&
            !t.note.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();
    final bars = lastMonthsExpense(_txns, now, 6);
    final totalSpent = bars.fold<double>(0, (s, b) => s + b.amount);
    final groups = groupTxnsByDay(filtered);
    final overBudgets = <BudgetLimit, double>{};
    for (final b in _budgets) {
      final spent = _txns
          .where((t) =>
              t.kind == 'expense' &&
              t.category == b.category &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold<double>(0, (s, t) => s + t.amount);
      if (spent > b.limit) overBudgets[b] = spent;
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export CSV',
            onPressed: _txns.isEmpty ? null : _exportCsv,
          ),
        ],
      ),
      floatingActionButton: _buildFab(context, reduceMotion),
      body: Stack(
        children: [
          ListView(
            controller: _scrollController,
            padding: AppLayout.pagePaddingTab,
            children: [
              MinecraftCard(
                padding: AppLayout.cardPadding,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available balance',
                          style: AppText.caption),
                      Text(peso(balance),
                          style: MinecraftText.heading(
                            color: MinecraftColors.emerald,
                            fontSize: 28,
                          )),
                      const SizedBox(height: AppSpacing.s8),
                      Row(
                        children: [
                          Expanded(
                              child:
                                  Text('This month in: ${peso(month.income)}')),
                          Expanded(
                              child: Text(
                                  'This month out: ${peso(month.expense)}')),
                        ],
                      ),
                    ],
                  ),
              ),
              if (overBudgets.isNotEmpty) ...[
                const SizedBox(height: AppLayout.cardGap),
                MinecraftCard(
                  color: scheme.errorContainer,
                  padding: AppLayout.cardPadding,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Budget alert',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        for (final e in overBudgets.entries)
                          Text(
                              '${e.key.category} over budget: spent ${peso(e.value)} of ${peso(e.key.limit)}.'),
                      ],
                    ),
                ),
              ],
              const SizedBox(height: 20),
              const MinecraftSectionHeader(
                icon: Icons.bar_chart_rounded,
                title: 'Spending · last 6 months',
              ),
              const SizedBox(height: AppSpacing.s8),
              MinecraftCard(
                padding: AppLayout.cardPadding,
                child: MoneySpendingChart(
                    bars: bars,
                    totalSpent: totalSpent,
                    now: now,
                    barHeight: 80,
                    barWidth: 22,
                  ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: MinecraftSectionHeader(
                      icon: Icons.savings_rounded,
                      title: 'Savings goals',
                    ),
                  ),
                  FilledButton(
                    style: minecraftBlockButtonStyle(),
                    onPressed: _openGoalForm,
                    child: const Text('New goal'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              if (_goals.isEmpty)
                const MinecraftCard(
                  padding: EdgeInsets.zero,
                    child: ListTile(title: Text('No savings goals yet.')))
              else
                for (final g in _goals)
                  MinecraftCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(g.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: g.target > 0
                                ? (g.saved / g.target).clamp(0, 1).toDouble()
                                : 0,
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text('${peso(g.saved)} of ${peso(g.target)}'),
                        ],
                      ),
                      trailing: TextButton(
                          onPressed: () => _addToGoal(g),
                          child: const Text('Add')),
                    ),
                  ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: MinecraftSectionHeader(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Monthly budgets',
                    ),
                  ),
                  FilledButton(
                    style: minecraftBlockButtonStyle(),
                    onPressed: _openBudgetForm,
                    child: const Text('Set limit'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              if (_budgets.isEmpty)
                const MinecraftCard(
                  padding: EdgeInsets.zero,
                    child: ListTile(title: Text('No budget limits set.')))
              else
                for (final b in _budgets)
                  Builder(builder: (_) {
                    final spent = _txns
                        .where((t) =>
                            t.kind == 'expense' &&
                            t.category == b.category &&
                            t.date.year == now.year &&
                            t.date.month == now.month)
                        .fold<double>(0, (s, t) => s + t.amount);
                    return MinecraftCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(b.category),
                        subtitle: Text(
                            'Spent ${peso(spent)} of ${peso(b.limit)} this month'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            setState(() =>
                                _budgets.removeWhere((x) => x.id == b.id));
                            await _saveBudgets();
                          },
                        ),
                      ),
                    );
                  }),
              const SizedBox(height: 20),
              const MinecraftSectionHeader(
                icon: Icons.receipt_long_rounded,
                title: 'Transactions',
              ),
              const SizedBox(height: AppSpacing.s8),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search transactions…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _kindFilter == 'all',
                    onSelected: (_) => setState(() => _kindFilter = 'all'),
                  ),
                  ChoiceChip(
                    label: const Text('Income'),
                    selected: _kindFilter == 'income',
                    onSelected: (_) =>
                        setState(() => _kindFilter = 'income'),
                  ),
                  ChoiceChip(
                    label: const Text('Expense'),
                    selected: _kindFilter == 'expense',
                    onSelected: (_) =>
                        setState(() => _kindFilter = 'expense'),
                  ),
                  DropdownButton<String>(
                    value: _catFilter,
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('All categories')),
                      for (final c in <String>{
                        ..._expenseCategories,
                        ..._incomeCategories,
                      })
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _catFilter = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              if (filtered.isEmpty)
                const MinecraftCard(
                  padding: EdgeInsets.zero,
                    child: ListTile(title: Text('No transactions found.')))
              else
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      dayHeaderLabel(group.day),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final t in group.txns) _txnRow(context, t),
                ],
              const SizedBox(height: 72),
            ],
          ),
          // Floating + spring menu overlay (closes on tap outside).
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _fabController,
              builder: (_, __) {
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
                      right: 16,
                      bottom: 88,
                      child: _buildFabMenu(context, reduceMotion),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Round green floating + (this screen only). Tapping rotates it
  /// to × and springs the menu up; tapping again closes it.
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
            key: const ValueKey('money-fab'),
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

  /// The spring menu above the +: Manual first, Files second,
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
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ScaleTransition(
      scale: menuScale,
      alignment: Alignment.bottomRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          item(
            index: 0,
            key: const ValueKey('money-fab-manual'),
            icon: Icons.edit_outlined,
            label: 'Add transaction Manual',
            onTap: () {
              _closeFabMenu();
              _openTxnForm();
            },
          ),
          item(
            index: 1,
            key: const ValueKey('money-fab-files'),
            icon: Icons.receipt_long_outlined,
            label: 'Files',
            onTap: () {
              _closeFabMenu();
              _scanInvoice();
            },
          ),
        ],
      ),
    );
  }

  /// One transaction row: category icon, merchant + date, red
  /// amount for expenses. Just-inserted scan rows flash green and
  /// carry a "New" badge until the batch settles.
  Widget _txnRow(BuildContext context, AllowanceTxn t) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = _justInserted.contains(t.id);
    final key = isNew ? (_txnKeys[t.id] ??= GlobalKey()) : null;
    final row = MinecraftCard(
      key: key,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(
            allowanceTxnIcon(t),
            color: scheme.primary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                t.note.isEmpty ? t.category : t.note,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isNew)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'New',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          t.note.isEmpty
              ? formatDate(t.date)
              : '${t.category} · ${formatDate(t.date)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${t.kind == 'income' ? '+' : '−'}${peso(t.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.kind == 'income'
                    ? scheme.primary
                    : scheme.error,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _openTxnForm(existing: t),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteTxn(t),
            ),
          ],
        ),
      ),
    );
    if (!isNew) return row;
    // Static tween: a fresh Tween each build would restart the
    // flash on every setState (e.g. when the next scan row lands).
    return TweenAnimationBuilder<double>(
      tween: _flashTween,
      duration: const Duration(milliseconds: 2500),
      builder: (_, flash, child) => Container(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.22 * flash),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
      child: row,
    );
  }
}

/// Invoice scan sheet: picks up the file the student chose, reads
/// its text (ML Kit OCR for photos, pdfrx text layer for PDFs),
/// parses merchant / date / items / total, and lets the student
/// review and edit every draft before confirming. The green scan
/// line sweeps the file while the four fields check off one by
/// one; a file with no parseable transactions says so plainly
/// instead of inventing any.
class _InvoiceScanSheet extends StatefulWidget {
  const _InvoiceScanSheet({required this.file});

  final File file;

  @override
  State<_InvoiceScanSheet> createState() => _InvoiceScanSheetState();
}

class _InvoiceScanSheetState extends State<_InvoiceScanSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;
  bool _scanning = true;
  String? _error;
  InvoiceParseResult? _parsed;
  int _revealed = 0;
  List<ScannedTxn> _drafts = [];

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
            ? 'No text found in this file — try a clearer photo of the receipt.'
            : 'Could not read this file.';
      });
      return;
    }
    final parsed = parseInvoiceText(result.text);
    setState(() => _parsed = parsed);
    // Reveal the four check-offs one by one. The parse is already
    // done — this stagger is only so the student can see each
    // field land, exactly like the preview.
    for (var step = 1; step <= 4; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      setState(() => _revealed = step);
    }
    setState(() {
      _scanning = false;
      _drafts = List.of(parsed.items);
    });
  }

  Widget _checkRow(String label, String? value, bool revealed) {
    final scheme = Theme.of(context).colorScheme;
    final found = value != null && value.isNotEmpty;
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
            Icon(
              found ? Icons.check_circle : Icons.remove_circle_outline,
              color: found ? scheme.primary : scheme.onSurfaceVariant,
              size: 20,
            ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              revealed ? (found ? value ?? '' : 'Not found') : 'Checking…',
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = _parsed;
    final ext = NoteExtractService.extensionOf(widget.file.path);
    final isImage = NoteExtractService.imageExtensions.contains(ext);
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
                  'Scan invoice',
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
            style: AppText.caption
                .copyWith(color: scheme.onSurfaceVariant),
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
                      builder: (_, __) {
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
          _checkRow('Merchant', parsed?.merchant, _revealed >= 1),
          _checkRow(
            'Date',
            parsed?.date == null ? null : formatDate(parsed!.date!),
            _revealed >= 2,
          ),
          _checkRow(
            'Items',
            parsed == null
                ? null
                : parsed.items.isEmpty
                    ? null
                    : '${parsed.items.length} found',
            _revealed >= 3,
          ),
          _checkRow(
            'Total',
            parsed?.total == null ? null : peso(parsed!.total!),
            _revealed >= 4,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _scanning
                ? const Center(child: Text('Reading the invoice…'))
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : parsed != null && parsed.items.isEmpty
                        ? const Center(
                            child: Text(
                              'No transactions found in this file — '
                              'try a clearer photo of the receipt.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _drafts.length,
                            itemBuilder: (_, i) => _DraftEditor(
                              draft: _drafts[i],
                              onChanged: (updated) => setState(
                                  () => _drafts[i] = updated),
                            ),
                          ),
          ),
          if (!_scanning && _error == null && _drafts.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _drafts),
                child: Text(
                    'Add ${_drafts.length} transaction${_drafts.length == 1 ? '' : 's'}'),
              ),
            ),
          ] else if (!_scanning) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One editable scanned draft: title, amount, date, category, kind.
/// Owns its controllers; every change reports the updated draft up.
class _DraftEditor extends StatefulWidget {
  const _DraftEditor({required this.draft, required this.onChanged});

  final ScannedTxn draft;
  final ValueChanged<ScannedTxn> onChanged;

  @override
  State<_DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<_DraftEditor> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late String _category;
  late String _kind;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title);
    _amount =
        TextEditingController(text: widget.draft.amount.toStringAsFixed(2));
    _category = widget.draft.category;
    _kind = widget.draft.kind;
    _date = widget.draft.date;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(ScannedTxn(
      title: _title.text.trim(),
      amount: double.tryParse(_amount.text) ?? widget.draft.amount,
      date: _date,
      category: _category,
      kind: _kind,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cats = _kind == 'income' ? _incomeCategories : _expenseCategories;
    if (!cats.contains(_category)) _category = cats.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IosSegmentedControl<String>(
              segments: const [
                IosSegment(value: 'expense', label: 'Expense'),
                IosSegment(value: 'income', label: 'Income'),
              ],
              groupValue: _kind,
              onValueChanged: (value) => setState(() {
                _kind = value;
                _emit();
              }),
            ),
            const SizedBox(height: AppSpacing.s8),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    decoration:
                        const InputDecoration(labelText: 'Amount (₱)'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    decoration:
                        const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in cats)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _category = v);
                        _emit();
                      }
                    },
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Date: ${formatDate(_date)}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                  _emit();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TxnForm extends StatefulWidget {
  const _TxnForm({this.existing});

  final AllowanceTxn? existing;

  @override
  State<_TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends State<_TxnForm> {
  late String _kind;
  late String _category;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? 'expense';
    _category = e?.category ?? _expenseCategories.first;
    if (e != null) {
      _amount.text = e.amount.toStringAsFixed(2);
      _note.text = e.note;
      _date = e.date;
    } else {
      _date = DateTime.now();
    }
    _fixCategory();
  }

  void _fixCategory() {
    final cats = _kind == 'income' ? _incomeCategories : _expenseCategories;
    if (!cats.contains(_category)) _category = cats.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _kind == 'income' ? _incomeCategories : _expenseCategories;
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
            widget.existing == null ? 'Add transaction' : 'Edit transaction',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppLayout.cardGap),
          IosSegmentedControl<String>(
            segments: const [
              IosSegment(value: 'expense', label: 'Expense'),
              IosSegment(value: 'income', label: 'Income'),
            ],
            groupValue: _kind,
            onValueChanged: (value) => setState(() {
              _kind = value;
              _fixCategory();
            }),
          ),
          const SizedBox(height: AppLayout.cardGap),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount (₱)'),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in cats) DropdownMenuItem(value: c, child: Text(c))
            ],
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          TextField(
            controller: _note,
            decoration:
                const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: AppSpacing.s8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date: ${formatDate(_date)}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: AppLayout.cardGap),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(_amount.text) ?? 0;
              if (amount <= 0) {
                TopPopup.show(context, message: 'Enter an amount greater than zero.');
                return;
              }
              Navigator.pop(
                context,
                AllowanceTxn(
                  id: widget.existing?.id ?? newId(),
                  kind: _kind,
                  amount: amount,
                  category: _category,
                  note: _note.text.trim(),
                  date: _date,
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
