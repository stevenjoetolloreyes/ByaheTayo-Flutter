// Allowance Management — personal allowance tracker (local only).
//
// Balance = total income − total expenses. Budgets are monthly
// per-category limits with an in-app over-budget banner (this app has
// no push-notification plugin, so alerts surface here, not as system
// notifications). CSV export shares a real file via share_plus.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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

class AllowanceScreen extends StatefulWidget {
  const AllowanceScreen({super.key});

  @override
  State<AllowanceScreen> createState() => _AllowanceScreenState();
}

class _AllowanceScreenState extends State<AllowanceScreen> {
  List<AllowanceTxn> _txns = [];
  List<SavingsGoal> _goals = [];
  List<BudgetLimit> _budgets = [];
  String _query = '';
  String _kindFilter = 'all';
  String _catFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _saveTxns() => StudentStorage.saveList(
      StudentStorage.txnsKey, _txns.map((t) => t.toJson()).toList());
  Future<void> _saveGoals() => StudentStorage.saveList(
      StudentStorage.goalsKey, _goals.map((g) => g.toJson()).toList());
  Future<void> _saveBudgets() => StudentStorage.saveList(
      StudentStorage.budgetsKey, _budgets.map((b) => b.toJson()).toList());

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
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
    final maxBar = bars.fold<double>(
        0, (m, b) => b.amount > m ? b.amount : m);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTxnForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Available balance',
                      style: TextStyle(fontSize: 13)),
                  Text(peso(balance),
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: Text('This month in: ${peso(month.income)}')),
                      Expanded(
                          child:
                              Text('This month out: ${peso(month.expense)}')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (overBudgets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
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
            ),
          ],
          const SizedBox(height: 20),
          const Text('Spending · last 6 months',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in bars)
                    Expanded(
                      child: Column(
                        children: [
                          Text(peso(b.amount),
                              style: const TextStyle(fontSize: 10)),
                          const SizedBox(height: 4),
                          Container(
                            height: maxBar > 0
                                ? 80 * (b.amount / maxBar)
                                : 2,
                            width: 22,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(b.label,
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Savings goals',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                  onPressed: _openGoalForm, child: const Text('New goal')),
            ],
          ),
          if (_goals.isEmpty)
            const Card(
                child: ListTile(title: Text('No savings goals yet.')))
          else
            for (final g in _goals)
              Card(
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
                      const SizedBox(height: 4),
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
                child: Text('Monthly budgets',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                  onPressed: _openBudgetForm, child: const Text('Set limit')),
            ],
          ),
          if (_budgets.isEmpty)
            const Card(
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
                return Card(
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
          const Text('Transactions',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search transactions…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 8),
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
                onSelected: (_) => setState(() => _kindFilter = 'income'),
              ),
              ChoiceChip(
                label: const Text('Expense'),
                selected: _kindFilter == 'expense',
                onSelected: (_) => setState(() => _kindFilter = 'expense'),
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
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Card(
                child: ListTile(title: Text('No transactions found.')))
          else
            for (final t in filtered)
              Card(
                child: ListTile(
                  leading: Icon(
                    t.kind == 'income'
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: t.kind == 'income'
                        ? Colors.green
                        : scheme.error,
                  ),
                  title: Text(
                      '${t.category}${t.note.isEmpty ? '' : ' · ${t.note}'}'),
                  subtitle: Text(formatDate(t.date)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${t.kind == 'income' ? '+' : '-'}${peso(t.amount)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
              ),
          const SizedBox(height: 72),
        ],
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
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _fixCategory();
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount (₱)'),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration:
                const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(_amount.text) ?? 0;
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enter an amount greater than zero.')));
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
