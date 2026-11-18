import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'common.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.repo, required this.month, this.onMonth});
  final Repo repo;
  final DateTime month;
  final ValueChanged<DateTime>? onMonth;
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _cat = <String, TextEditingController>{};
  final _mem = <String, TextEditingController>{};
  final _inc = <String, TextEditingController>{};
  Budget? _saved; // what is stored for this month
  Map<String, double> _spent = {};
  StreamSubscription? _txnSub, _budgetSub;
  String? _loadedFor;
  bool _saving = false;
  bool _dirty = false;

  void _load() {
    final mk = monthKey(widget.month);
    if (_loadedFor == mk) return;
    _loadedFor = mk;
    _dirty = false;
    _txnSub?.cancel();
    _budgetSub?.cancel();
    _txnSub = widget.repo.monthTxns(mk).listen((l) {
      final m = <String, double>{};
      for (final t in l) {
        if (t.category == kIgnored) continue;
        m[t.category] = (m[t.category] ?? 0) + t.amount;
      }
      if (mounted) setState(() => _spent = m);
    }, onError: (_) {});
    // Live: picks up changes made on the other phone, unless you are editing.
    _budgetSub = widget.repo.budgetStream(mk).listen((b) async {
      if (_dirty) {
        _saved = b;
        return;
      }
      final fam = await widget.repo.family.get();
      final names = Map<String, dynamic>.from(fam.data()?['members'] as Map? ?? {}).values.cast<String>().toSet()
        ..addAll(b.members.keys)
        ..addAll(b.income.keys);
      if (!mounted) return;
      setState(() => _fill(b, names));
    }, onError: (_) {});
  }

  void _fill(Budget b, Set<String> names) {
    _saved = b;
    for (final c in kCats) {
      (_cat[c.id] ??= TextEditingController()).text = _fmt(b.categories[c.id]);
    }
    for (final n in names) {
      (_mem[n] ??= TextEditingController()).text = _fmt(b.members[n]);
      (_inc[n] ??= TextEditingController()).text = _fmt(b.income[n]);
    }
  }

  @override
  void dispose() {
    _txnSub?.cancel();
    _budgetSub?.cancel();
    super.dispose();
  }

  String _fmt(double? v) => v == null || v == 0 ? '' : v.toStringAsFixed(0);
  double _val(TextEditingController? c) => double.tryParse((c?.text ?? '').replaceAll(',', '').trim()) ?? 0;

  Budget _current() => Budget(
        {for (final c in kCats) c.id: _val(_cat[c.id])},
        {for (final e in _mem.entries) if (_val(e.value) > 0) e.key: _val(e.value)},
        {for (final e in _inc.entries) if (_val(e.value) > 0) e.key: _val(e.value)},
      );

  bool get _isPast {
    final now = DateTime.now();
    return widget.month.isBefore(DateTime(now.year, now.month));
  }

  Future<void> _save() async {
    final name = DateFormat('MMMM').format(widget.month);
    bool? asDefault = false;
    if (!_isPast) {
      asDefault = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.event_available),
              title: Text('Only $name'),
              subtitle: const Text('A one-off reshuffle. Next month goes back to your usual budget.'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: Text('$name and the coming months'),
              subtitle: const Text('Make this your usual budget. Past months keep their own figures.'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (asDefault == null) return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.saveBudget(monthKey(widget.month), _current(), asDefault: asDefault);
      _dirty = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(asDefault ? 'Saved for $name and the coming months.' : 'Saved for $name only.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changed() => setState(() => _dirty = true);

  void _undo() {
    final b = _saved;
    if (b == null) return;
    setState(() {
      _fill(b, {..._mem.keys, ..._inc.keys});
      _dirty = false;
    });
  }

  Future<void> _move() async {
    final spend = kCats.where((c) => !c.goal).toList();
    if (spend.length < 2) return;
    String from = spend.first.id, to = spend[1].id;
    final amount = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final tt = Theme.of(ctx).textTheme;
        double left(String id) => _val(_cat[id]) - (_spent[id] ?? 0);
        Widget picker(String label, String value, ValueChanged<String> on) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: tt.labelLarge),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final c in kCats)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 16, color: c.color),
                      label: Text('${c.label} · ${money(left(c.id))}'),
                      selected: value == c.id,
                      onSelected: (_) => set(() => on(c.id)),
                    ),
                ]),
              ],
            );
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Move money between budgets', style: tt.titleLarge),
              const SizedBox(height: 4),
              Text('The total stays the same. Amounts shown are what is left this month.', style: tt.bodySmall),
              const SizedBox(height: 16),
              picker('Take from', from, (v) => from = v),
              const SizedBox(height: 12),
              picker('Give to', to, (v) => to = v),
              const SizedBox(height: 16),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Move'),
                  onPressed: () {
                    final v = double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
                    if (v <= 0 || from == to) return;
                    setState(() {
                      _cat[from]!.text = _fmt((_val(_cat[from]) - v).clamp(0, double.infinity).toDouble());
                      _cat[to]!.text = _fmt(_val(_cat[to]) + v);
                      _dirty = true;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _amountField(TextEditingController? c, {String hint = ''}) => SizedBox(
        width: 120,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(prefixText: '₹ ', hintText: hint, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    _load();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (_saved == null) return const Center(child: CircularProgressIndicator());
    for (final c in kCats) {
      _cat.putIfAbsent(c.id, () => TextEditingController());
    }
    final spendCats = kCats.where((c) => !c.goal).toList();
    final goalCats = kCats.where((c) => c.goal).toList();
    final total = spendCats.fold<double>(0, (s, c) => s + _val(_cat[c.id]));
    final savedTotal = spendCats.fold<double>(0, (s, c) => s + (_saved!.categories[c.id] ?? 0));
    final spentTotal = spendCats.fold<double>(0, (s, c) => s + (_spent[c.id] ?? 0));
    final diff = total - savedTotal;

    Widget catRow(Cat c) {
      final spent = _spent[c.id] ?? 0;
      final limit = _val(_cat[c.id]);
      final over = !c.goal && limit > 0 && spent > limit;
      final sub = c.goal
          ? (spent > 0 ? 'Paid in ${money(spent)}' : 'Monthly target')
          : limit > 0
              ? 'Spent ${money(spent)} · ${over ? '${money(spent - limit)} over' : '${money(limit - spent)} left'}'
              : (spent > 0 ? 'Spent ${money(spent)} · no budget' : 'No budget');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          CatAvatar(c, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.label, style: tt.bodyLarge),
              Text(sub,
                  style: tt.bodySmall?.copyWith(color: over ? cs.error : null, fontWeight: over ? FontWeight.w600 : null)),
            ]),
          ),
          _amountField(_cat[c.id]),
        ]),
      );
    }

    return Column(children: [
      // ---- sticky header: month, total, save ----
      Material(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (widget.onMonth != null)
                MonthSwitcher(month: widget.month, onChanged: widget.onMonth!)
              else
                Text(DateFormat('MMMM yyyy').format(widget.month), style: tt.titleLarge),
              const Spacer(),
              if (_dirty) TextButton(onPressed: _undo, child: const Text('Undo')),
              FilledButton(
                onPressed: _saving || !_dirty ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ]),
            Text(
              'Spending budget ${money(total)}'
              '${diff.abs() >= 1 ? ' (${diff > 0 ? '+' : '−'}${money(diff.abs())} vs saved)' : ''}'
              ' · spent ${money(spentTotal)} · left ${money(total - spentTotal)}',
              style: tt.bodySmall?.copyWith(color: diff.abs() >= 1 ? cs.primary : null),
            ),
          ]),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(children: [
              Expanded(child: Text('Spending', style: tt.titleMedium)),
              TextButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Move money'),
                onPressed: _move,
              ),
            ]),
            const SizedBox(height: 4),
            for (final c in spendCats) catRow(c),
            if (goalCats.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Set aside (monthly targets)', style: tt.titleMedium),
              const SizedBox(height: 8),
              for (final c in goalCats) catRow(c),
            ],
            const SizedBox(height: 16),
            Text('Expected monthly income', style: tt.titleMedium),
            const SizedBox(height: 4),
            Text('Salary, stipend, etc. Used to show expected vs actual saving each month.', style: tt.bodySmall),
            const SizedBox(height: 12),
            for (final e in _inc.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  CircleAvatar(radius: 18, child: Text(e.key.isEmpty ? '?' : e.key[0].toUpperCase())),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.key)),
                  _amountField(e.value, hint: 'Not set'),
                ]),
              ),
            const SizedBox(height: 16),
            Text('Personal limits (optional)', style: tt.titleMedium),
            const SizedBox(height: 4),
            Text('How much each person may spend from the pool this month. Shown as their balance.',
                style: tt.bodySmall),
            const SizedBox(height: 12),
            for (final e in _mem.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  CircleAvatar(radius: 18, child: Text(e.key.isEmpty ? '?' : e.key[0].toUpperCase())),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.key)),
                  _amountField(e.value, hint: 'No limit'),
                ]),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// Overview: tap a category to change its budget without leaving the screen.
Future<void> showCategoryBudgetSheet(
    BuildContext context, Repo repo, DateTime month, Cat cat, double current, double spent) async {
  final c = TextEditingController(text: current > 0 ? current.toStringAsFixed(0) : '');
  final name = DateFormat('MMMM').format(month);
  final now = DateTime.now();
  final past = month.isBefore(DateTime(now.year, now.month));
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final tt = Theme.of(ctx).textTheme;
      Future<void> save(bool asDefault) async {
        final v = double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;
        await repo.setCategoryBudget(monthKey(month), cat.id, v, asDefault: asDefault);
        if (ctx.mounted) Navigator.pop(ctx);
      }

      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CatAvatar(cat, size: 36),
              const SizedBox(width: 12),
              Text('${cat.label} budget', style: tt.titleLarge),
            ]),
            const SizedBox(height: 4),
            Text('Spent ${money(spent)} so far in $name.', style: tt.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Budget for $name', prefixText: '₹ ', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: () => save(false), child: Text('Only $name')),
              ),
              if (!past) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: () => save(true), child: const Text('From now on')),
                ),
              ],
            ]),
          ]),
        ),
      );
    },
  );
}
