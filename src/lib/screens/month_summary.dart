import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'common.dart';

/// This month: income (expected vs received), spent, and saving
/// (expected vs actual), per person and for the family.
class MonthSummary extends StatefulWidget {
  const MonthSummary({super.key, required this.repo, required this.members});
  final Repo repo;
  final List<String> members;
  @override
  State<MonthSummary> createState() => _MonthSummaryState();
}

class _MonthSummaryState extends State<MonthSummary> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _mk;
  late Stream<Budget> _budget;
  late Stream<List<Txn>> _txns;
  late Stream<List<IncomeEntry>> _income;
  bool _showIncome = false;

  void _streams() {
    final mk = monthKey(_month);
    if (mk == _mk) return;
    _mk = mk;
    _budget = widget.repo.budgetStream(mk);
    _txns = widget.repo.monthTxns(mk);
    _income = widget.repo.incomeStream(mk);
  }

  @override
  Widget build(BuildContext context) {
    _streams();
    return StreamBuilder<Budget>(
      stream: _budget,
      builder: (context, b) => StreamBuilder<List<Txn>>(
        stream: _txns,
        builder: (context, t) => StreamBuilder<List<IncomeEntry>>(
          stream: _income,
          builder: (context, i) =>
              _body(context, b.data ?? const Budget({}, {}), t.data ?? const [], i.data ?? const []),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Budget budget, List<Txn> txns, List<IncomeEntry> income) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final names = {...widget.members, ...budget.income.keys, ...income.map((e) => e.member)}.toList()..sort();

    double spentOf(String? n) => txns
        .where((t) => t.category != kIgnored && !catById(t.category).goal && (n == null || t.member == n))
        .fold(0.0, (s, t) => s + t.amount);
    double receivedOf(String? n) =>
        income.where((e) => e.counted && (n == null || e.member == n)).fold(0.0, (s, e) => s + e.amount);
    double expIncomeOf(String? n) =>
        n == null ? budget.income.values.fold(0.0, (s, v) => s + v) : (budget.income[n] ?? 0);
    final catBudget = kCats.where((c) => !c.goal).fold(0.0, (s, c) => s + (budget.categories[c.id] ?? 0));
    final personalTotal = budget.members.values.fold(0.0, (s, v) => s + v);
    double expSpendOf(String? n) => n == null ? (catBudget > 0 ? catBudget : personalTotal) : (budget.members[n] ?? 0);

    Widget row(String label, String? n) {
      final expInc = expIncomeOf(n), got = receivedOf(n), spent = spentOf(n), expSpend = expSpendOf(n);
      final expSave = expInc - expSpend;
      final actualSave = got - spent;
      final ahead = actualSave >= expSave;
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _line(context, 'Income', got, expInc > 0 ? 'of ${money(expInc)} expected' : 'set expected in Budget'),
            _line(context, 'Spent', spent, expSpend > 0 ? 'of ${money(expSpend)} budget' : null),
            const Divider(height: 14),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Saved (actual)', style: tt.bodySmall),
                  Text(money(actualSave),
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, color: actualSave < 0 ? cs.error : cs.primary)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Expected saving', style: tt.bodySmall),
                  Text(expInc > 0 ? money(expSave) : '—',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            if (expInc > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: expSave <= 0 ? (actualSave > 0 ? 1 : 0) : (actualSave / expSave).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: ahead ? cs.primary : cs.tertiary,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ahead
                    ? 'On track: ${money(actualSave - expSave)} ahead of plan'
                    : '${money(expSave - actualSave)} behind plan'
                        '${got < expInc ? ' (still ${money(expInc - got)} income to come)' : ''}',
                style: tt.bodySmall?.copyWith(color: ahead ? cs.primary : cs.tertiary),
              ),
            ],
          ]),
        ),
      );
    }

    final isCurrent = monthKey(_month) == monthKey(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.insights, size: 20),
        const SizedBox(width: 8),
        Text('Income & saving', style: tt.titleMedium),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
        ),
        Text(DateFormat('MMM yyyy').format(_month), style: tt.labelLarge),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ]),
      const SizedBox(height: 4),
      row('Family', null),
      if (names.length > 1)
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 8) / 2;
          return Wrap(spacing: 8, children: [for (final n in names) SizedBox(width: w, child: row(n, n))]);
        }),
      // Money in list
      TextButton.icon(
        icon: Icon(_showIncome ? Icons.expand_less : Icons.expand_more),
        label: Text('Money in this month (${income.length})'),
        onPressed: () => setState(() => _showIncome = !_showIncome),
      ),
      if (_showIncome) ...[
        if (income.isEmpty)
          Text('Credits from bank SMS appear here. You can also add income by hand with + Add.',
              style: tt.bodySmall),
        for (final e in income)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(value: e.counted, onChanged: (v) => widget.repo.setIncomeCounted(e, v ?? true)),
            title: Text(e.from,
                style: TextStyle(decoration: e.counted ? null : TextDecoration.lineThrough),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text([
              e.member,
              DateFormat('d MMM').format(e.date),
              if (!e.counted) 'not counted as income',
              if (e.note != null) e.note!,
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (e.source == 'manual')
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => widget.repo.deleteIncome(e),
                ),
            ]),
          ),
        Text('Untick anything that is not income (refunds, money moved between your own accounts).',
            style: tt.bodySmall),
      ],
    ]);
  }

  Widget _line(BuildContext context, String label, double v, String? sub) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 56, child: Text(label, style: tt.bodySmall)),
        Text(money(v), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (sub != null) ...[
          const SizedBox(width: 6),
          Flexible(child: Text(sub, style: tt.bodySmall, overflow: TextOverflow.ellipsis)),
        ],
      ]),
    );
  }
}

/// Month-end leftovers: bank + cash + other savings + gold, recorded just
/// before the next month's income arrives.
class Leftovers extends StatefulWidget {
  const Leftovers({super.key, required this.repo});
  final Repo repo;
  @override
  State<Leftovers> createState() => _LeftoversState();
}

class _LeftoversState extends State<Leftovers> {
  late final _stream = widget.repo.closingsStream();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final lastMonth = monthKey(DateTime(now.year, now.month - 1));
    final thisMonth = monthKey(now);
    return StreamBuilder<List<Closing>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <Closing>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event_available, size: 20),
            const SizedBox(width: 8),
            Text('Left over at month end', style: tt.titleMedium),
          ]),
          Text(
            'Saved automatically when the first income of a new month comes in, '
            'so it shows what was left before the new money.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 8),
          if (list.isEmpty) Text('Nothing saved yet.', style: tt.bodySmall),
          for (var i = 0; i < list.length; i++) _closingCard(context, list[i], i + 1 < list.length ? list[i + 1] : null),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.edit_note),
              label: const Text('Type in a month-end'),
              onPressed: () => _editManual(context, null, list),
            ),
            OutlinedButton.icon(
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_alt),
              label: Text(list.any((c) => c.month == lastMonth)
                  ? 'Re-save ${_label(lastMonth)} with today\'s figures'
                  : 'Save ${_label(lastMonth)} month-end now'),
              onPressed: _saving ? null : () => _save(context, lastMonth),
            ),
            if (now.day >= 25)
              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: Text('Save ${_label(thisMonth)} month-end now'),
                onPressed: _saving ? null : () => _save(context, thisMonth),
              ),
          ]),
        ]);
      },
    );
  }

  Future<void> _save(BuildContext context, String mk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Save ${_label(mk)} month-end?'),
        content: const Text(
            'This records today\'s bank balances, cash, other savings and gold as what was left at the end of the month. '
            'Do it before the next salary/stipend arrives.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    await widget.repo.ensureClosing(mk, overwrite: true, auto: false);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _editManual(BuildContext context, Closing? existing, List<Closing> all) async {
    final fam = (await widget.repo.family.get()).data();
    final names = Map<String, dynamic>.from(fam?['members'] as Map? ?? {}).values.cast<String>().toSet().toList()
      ..sort();
    if (existing != null) {
      for (final n in existing.members.keys) {
        if (!names.contains(n)) names.add(n);
      }
    }
    final now = DateTime.now();
    // Default month: last month, or the month being edited.
    var month = existing?.month ?? monthKey(DateTime(now.year, now.month - 1));
    final ctrls = <String, Map<String, TextEditingController>>{};
    String f(double? v) => v == null || v == 0 ? '' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    void fill(Closing? c) {
      for (final n in names) {
        final m = c?.members[n];
        ctrls[n] = {
          'bank': TextEditingController(text: f(m?['bank'])),
          'cash': TextEditingController(text: f(m?['cash'])),
          'other': TextEditingController(text: f(m?['other'])),
          'pavan': TextEditingController(text: f(m == null ? null : (m['goldGrams'] ?? 0) / 8)),
        };
      }
    }

    fill(existing);
    if (!context.mounted) return;
    final months = [for (var i = 1; i <= 24; i++) monthKey(DateTime(now.year, now.month - i + 1))];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final tt = Theme.of(ctx).textTheme;
        Widget field(String n, String key, String label, {String prefix = '₹ '}) => Expanded(
              child: TextField(
                controller: ctrls[n]![key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: label, prefixText: prefix, isDense: true, border: const OutlineInputBorder()),
              ),
            );
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(existing == null ? 'Type in a month-end' : 'Edit month-end', style: tt.titleLarge),
              const SizedBox(height: 4),
              Text('What was left at the end of the month, before the next income came in.', style: tt.bodySmall),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final m in months)
                    DropdownMenuItem(value: m, child: Text('${_label(m)} ${m.substring(0, 4)}')),
                ],
                onChanged: existing != null
                    ? null
                    : (v) => setS(() {
                          month = v!;
                          // Pre-fill if that month already has figures.
                          fill(all.where((c) => c.month == month).firstOrNull);
                        }),
              ),
              const SizedBox(height: 16),
              for (final n in names) ...[
                Text(n, style: tt.titleSmall),
                const SizedBox(height: 8),
                Row(children: [field(n, 'bank', 'Bank'), const SizedBox(width: 8), field(n, 'cash', 'Cash')]),
                const SizedBox(height: 8),
                Row(children: [
                  field(n, 'other', 'Other savings'),
                  const SizedBox(width: 8),
                  field(n, 'pavan', 'Gold (pavan)', prefix: ''),
                ]),
                const SizedBox(height: 16),
              ],
              Row(children: [
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      await widget.repo.deleteClosing(existing.month);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    double v(String n, String k) =>
                        double.tryParse(ctrls[n]![k]!.text.replaceAll(',', '').trim()) ?? 0;
                    await widget.repo.saveClosingManual(month, {
                      for (final n in names)
                        n: {
                          'bank': v(n, 'bank'),
                          'cash': v(n, 'cash'),
                          'other': v(n, 'other'),
                          'goldGrams': v(n, 'pavan') * 8,
                        }
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  String _label(String mk) {
    final p = mk.split('-');
    return DateFormat('MMMM').format(DateTime(int.parse(p[0]), int.parse(p[1])));
  }

  Widget _closingCard(BuildContext context, Closing c, Closing? prev) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final change = prev == null ? null : c.grand - prev.grand;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text('${_label(c.month)} ${c.month.substring(0, 4)}', style: tt.titleSmall),
        subtitle: Text(
          '${money(c.grand)} left'
          '${change == null ? '' : ' · ${change >= 0 ? '+' : '−'}${money(change.abs())} vs ${_label(prev!.month)}'}',
          style: TextStyle(color: change == null ? null : (change >= 0 ? cs.primary : cs.error)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final e in c.members.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.key, style: tt.labelLarge),
                Text(
                  'Bank ${money(e.value['bank'] ?? 0)} · Cash ${money(e.value['cash'] ?? 0)} · '
                  'Other ${money(e.value['other'] ?? 0)} · Gold ${((e.value['goldGrams'] ?? 0) / 8).toStringAsFixed(2)} pavan '
                  '(${money(e.value['gold'] ?? 0)})',
                  style: tt.bodySmall,
                ),
              ]),
            ),
          Row(children: [
            Expanded(
              child: Text(
                '${c.auto ? 'Saved automatically' : 'Saved by hand'} on ${DateFormat('d MMM, h:mm a').format(c.at)}',
                style: tt.labelSmall,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit'),
              onPressed: () => _editManual(context, c, const []),
            ),
          ]),
        ],
      ),
    );
  }
}

/// "+ Add → Income received" sheet.
Future<void> showAddIncome(BuildContext context, Repo repo, List<String> members) {
  final amount = TextEditingController();
  final from = TextEditingController();
  var member = members.contains(repo.myName) ? repo.myName : (members.isNotEmpty ? members.first : repo.myName);
  var date = DateTime.now();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Income received', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Only needed when it did not come as a bank SMS (cash, cheque…).',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: from,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'From', hintText: 'e.g. Salary, Stipend, Loan payback', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final n in members)
              ChoiceChip(label: Text(n), selected: member == n, onSelected: (_) => setS(() => member = n)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
          TextButton.icon(
            icon: const Icon(Icons.event),
            label: Text(DateFormat('d MMM yyyy').format(date)),
            onPressed: () async {
              final d = await showDatePicker(
                  context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setS(() => date = DateTime(d.year, d.month, d.day, 12));
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final a = double.tryParse(amount.text.replaceAll(',', ''));
                if (a == null || a <= 0) return;
                await repo.addIncome(
                    amount: a,
                    from: from.text.trim().isEmpty ? 'Income' : from.text.trim(),
                    member: member,
                    date: date);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ),
        ]),
      );
    }),
  );
}
