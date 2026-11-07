import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repo.dart';
import 'common.dart';
import 'money_screen.dart' show GoldRate, GoldCoin, pavan;

/// Zakat (per person, as it is an individual obligation) and bank-interest
/// purification. A calculator for guidance — rulings differ between scholars.
class ZakatScreen extends StatefulWidget {
  const ZakatScreen({super.key, required this.repo});
  final Repo repo;
  @override
  State<ZakatScreen> createState() => _ZakatScreenState();
}

const _nisabGoldGrams = 85.0; // 20 mithqal
const _nisabSilverGrams = 595.0; // 200 dirham
const _rate = 0.025; // 2.5%
const _lunarYearDays = 354;

class _ZakatScreenState extends State<ZakatScreen> {
  late final _fam = widget.repo.familyStream();
  late final _accounts = widget.repo.accountsStream();
  late final _money = widget.repo.moneyStream();
  late final _interest = widget.repo.interestStream();
  late final _paid = widget.repo.zakatPaidStream();
  GoldRate? _rates;

  @override
  void initState() {
    super.initState();
    GoldRate.fetch().then((r) => mounted ? setState(() => _rates = r) : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zakat & interest')),
      body: StreamBuilder(
        stream: _fam,
        builder: (context, fam) => StreamBuilder<List<BankAccount>>(
          stream: _accounts,
          builder: (context, acc) => StreamBuilder<List<MoneyItem>>(
            stream: _money,
            builder: (context, mon) => StreamBuilder<List<IncomeEntry>>(
              stream: _interest,
              builder: (context, intr) => StreamBuilder<List<MoneyItem>>(
                stream: _paid,
                builder: (context, paid) {
                  if (!fam.hasData) return const Center(child: CircularProgressIndicator());
                  return _body(
                    context,
                    fam.data!.data() ?? {},
                    acc.data ?? const [],
                    mon.data ?? const [],
                    intr.data ?? const [],
                    paid.data ?? const [],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> famData, List<BankAccount> accts, List<MoneyItem> items,
      List<IncomeEntry> interest, List<MoneyItem> paid) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final z = Map<String, dynamic>.from(famData['zakat'] as Map? ?? {});
    final madhab = z['madhab'] as String?; // 'shafii' | 'hanafi'
    final basis = z['basis'] as String?; // 'silver' | 'gold'
    final per = Map<String, dynamic>.from(z['members'] as Map? ?? {});
    final names = Map<String, dynamic>.from(famData['members'] as Map? ?? {}).values.cast<String>().toSet().toList()
      ..sort();

    final manual = widget.repo.goldRatesFrom(famData);
    final r22 = _rates?.rate22 ?? manual[22] ?? (famData['autoGold22'] as num?)?.toDouble() ?? 0;
    final r24 = _rates?.rate24 ?? manual[24] ?? (r22 > 0 ? r22 / 0.916 : 0);
    final silver = _rates?.silver ?? (z['silverRate'] as num?)?.toDouble() ?? 0;
    final nisab = basis == 'gold' ? _nisabGoldGrams * r24 : _nisabSilverGrams * silver;

    final setupDone = madhab != null && basis != null;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Card(
        color: cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'A calculator for guidance only. Rulings differ between madhabs and scholars — '
            'please confirm with a scholar you trust.',
            style: tt.bodySmall,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _settingsCard(context, z, madhab, basis, silver, r24, nisab, names, per),
      const SizedBox(height: 16),
      if (setupDone)
        for (final n in names) ...[
          _personCard(context, n, madhab!, basis!, nisab, per[n] as Map?, accts, items, interest, paid, r22, r24),
          const SizedBox(height: 12),
        ],
      const SizedBox(height: 8),
      _interestSection(context, interest, names),
    ]);
  }

  // ---------------- settings ----------------

  Widget _settingsCard(BuildContext context, Map<String, dynamic> z, String? madhab, String? basis, double silver,
      double r24, double nisab, List<String> names, Map<String, dynamic> per) {
    final tt = Theme.of(context).textTheme;
    Future<void> save(Map<String, dynamic> changes) => widget.repo.saveZakatSettings({...z, ...changes});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Settings', style: tt.titleMedium),
          const SizedBox(height: 10),
          Text('Madhab (affects gold jewellery you wear)', style: tt.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'shafii', label: Text("Shafi'i")),
              ButtonSegment(value: 'hanafi', label: Text('Hanafi')),
            ],
            selected: {if (madhab != null) madhab},
            onSelectionChanged: (v) => v.isEmpty ? null : save({'madhab': v.first}),
          ),
          Text(
            madhab == 'shafii'
                ? 'Gold jewellery worn regularly is not counted; gold kept as savings (coins, bars, unused) is.'
                : madhab == 'hanafi'
                    ? 'All gold, including jewellery that is worn, is counted.'
                    : 'Choose to start.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('Nisab (minimum wealth) based on', style: tt.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'silver', label: Text('Silver 595 g')),
              ButtonSegment(value: 'gold', label: Text('Gold 85 g')),
            ],
            selected: {if (basis != null) basis},
            onSelectionChanged: (v) => v.isEmpty ? null : save({'basis': v.first}),
          ),
          Text(
            basis == null
                ? 'Silver gives a lower threshold (more people pay, more for the poor); gold a higher one.'
                : 'Nisab today: ${nisab > 0 ? money(nisab) : 'rate not available'}'
                    '${basis == 'silver' ? (silver > 0 ? ' (silver ${money(silver)}/g)' : '') : (r24 > 0 ? ' (24K ${money(r24)}/g)' : '')}',
            style: tt.bodySmall,
          ),
          if (basis == 'silver' && silver <= 0)
            TextButton(
              onPressed: () async {
                final c = TextEditingController();
                final v = await showDialog<double>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Silver rate per gram'),
                    content: TextField(
                      controller: c,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(prefixText: '₹ ', border: OutlineInputBorder()),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('Save')),
                    ],
                  ),
                );
                if (v != null) save({'silverRate': v});
              },
              child: const Text('Enter silver rate'),
            ),
          const Divider(height: 24),
          Text('Each person', style: tt.labelLarge),
          const SizedBox(height: 4),
          for (final n in names) _personSettings(context, n, Map<String, dynamic>.from(per[n] as Map? ?? {}), z, per),
        ]),
      ),
    );
  }

  Widget _personSettings(
      BuildContext context, String n, Map<String, dynamic> p, Map<String, dynamic> z, Map<String, dynamic> per) {
    final tt = Theme.of(context).textTheme;
    final start = DateTime.tryParse(p['start'] as String? ?? '');
    final debts = (p['debts'] as num?)?.toDouble() ?? 0;
    Future<void> savePerson(Map<String, dynamic> changes) => widget.repo.saveZakatSettings({
          ...z,
          'members': {
            ...per,
            n: {...p, ...changes}
          }
        });
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(n),
      subtitle: Text(
        '${start == null ? 'Zakat year start not set' : 'Zakat year started ${DateFormat('d MMM yyyy').format(start)}'}'
        '${debts > 0 ? ' · debts due ${money(debts)}' : ''}',
        style: tt.bodySmall,
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final d = TextEditingController(text: debts > 0 ? debts.toStringAsFixed(0) : '');
        DateTime? date = start;
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Zakat year start — the date your wealth first reached nisab, or your usual zakat date '
                    '(e.g. 1st Ramadan). Zakat is due every lunar year (354 days) after it.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(date == null ? 'Choose date' : DateFormat('d MMM yyyy').format(date!)),
                  onPressed: () async {
                    final x = await showDatePicker(
                        context: ctx,
                        initialDate: date ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (x != null) setS(() => date = x);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: d,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Debts you owe that are due now (optional)',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      await savePerson({
                        if (date != null) 'start': DateFormat('yyyy-MM-dd').format(date!),
                        'debts': double.tryParse(d.text.replaceAll(',', '')) ?? 0,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ---------------- per person ----------------

  Widget _personCard(
      BuildContext context,
      String n,
      String madhab,
      String basis,
      double nisab,
      Map? pRaw,
      List<BankAccount> accts,
      List<MoneyItem> items,
      List<IncomeEntry> interest,
      List<MoneyItem> paidAll,
      double r22,
      double r24) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = Map<String, dynamic>.from(pRaw ?? {});
    final mine = items.where((m) => m.member == n).toList();

    final bank = accts.where((a) => a.member == n && a.balance != null).fold(0.0, (s, a) => s + a.balance!);
    final cash = mine.where((m) => m.kind == 'cash' && !m.zakatExclude).fold(0.0, (s, m) => s + m.amount);
    final other = mine.where((m) => m.kind == 'asset' && !m.zakatExclude).fold(0.0, (s, m) => s + m.amount);
    final owed = mine
        .where((m) => m.kind == 'receivable' && !m.received && !m.zakatExclude)
        .fold(0.0, (s, m) => s + m.amount);
    final golds = mine.where((m) => m.isGold).toList();
    bool counts(MoneyItem g) => !g.zakatExclude && !(madhab == 'shafii' && g.worn);
    final goldGrams = golds.where(counts).fold(0.0, (s, g) => s + g.grams);
    final goldValue = golds.where(counts).fold(0.0, (s, g) => s + g.grams * (g.purity == 24 ? r24 : r22));
    final riba = interest.where((e) => e.member == n && !e.givenAway).fold(0.0, (s, e) => s + e.amount);
    final debts = (p['debts'] as num?)?.toDouble() ?? 0;
    final wealth = bank + cash + other + owed + goldValue - riba - debts;
    final reaches = nisab > 0 && wealth >= nisab;
    final due = reaches ? wealth * _rate : 0.0;

    // Zakat year
    final start = DateTime.tryParse(p['start'] as String? ?? '');
    DateTime? yearStart = start, nextDue;
    if (start != null) {
      nextDue = start.add(const Duration(days: _lunarYearDays));
      while (nextDue!.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
        yearStart = nextDue;
        nextDue = nextDue.add(const Duration(days: _lunarYearDays));
      }
    }
    final paidThisYear = paidAll
        .where((m) => m.member == n && (yearStart == null || !(m.due ?? DateTime(0)).isBefore(yearStart)))
        .fold(0.0, (s, m) => s + m.amount);
    final daysLeft = nextDue?.difference(DateTime.now()).inDays;
    final monthsLeft = daysLeft == null ? 12 : (daysLeft / 29.5).ceil().clamp(1, 12);
    final remaining = (due - paidThisYear).clamp(0.0, double.infinity);

    Widget line(String label, double v, {String? sub, bool minus = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            Expanded(child: Text(label + (sub != null ? ' ($sub)' : ''), style: tt.bodySmall)),
            Text('${minus ? '− ' : ''}${money(v)}', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(n, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (nextDue != null)
              Text(daysLeft! >= 0 ? 'Due in $daysLeft days' : 'Due ${-daysLeft} days ago',
                  style: tt.labelMedium?.copyWith(color: daysLeft < 15 ? cs.error : cs.primary)),
          ]),
          if (nextDue != null)
            Text('Zakat year: ${DateFormat('d MMM yyyy').format(yearStart!)} → ${DateFormat('d MMM yyyy').format(nextDue)}',
                style: tt.labelSmall),
          const SizedBox(height: 10),
          line('Bank balances', bank),
          line('Cash in hand', cash),
          line('Other savings', other),
          line('Money owed to you', owed),
          Row(children: [
            const GoldCoin(size: 14),
            const SizedBox(width: 4),
            Expanded(child: line('Gold', goldValue, sub: '${pavan(goldGrams)}${madhab == 'shafii' ? ', worn jewellery not counted' : ''}')),
          ]),
          if (riba > 0) line('Interest not yet given away', riba, minus: true),
          if (debts > 0) line('Debts due now', debts, minus: true),
          const Divider(height: 16),
          line('Zakatable wealth', wealth),
          line('Nisab (${basis == 'gold' ? 'gold' : 'silver'})', nisab),
          const SizedBox(height: 8),
          if (nisab <= 0)
            Text('Rate not available yet — enter it in Settings above.', style: tt.bodySmall?.copyWith(color: cs.error))
          else if (!reaches)
            Text('Below nisab — no zakat due on current figures.', style: tt.bodyMedium?.copyWith(color: cs.primary))
          else ...[
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Yearly zakat (2.5%)', style: tt.bodySmall),
                  Text(money(due), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Set aside monthly', style: tt.bodySmall),
                  Text(money(remaining / monthsLeft),
                      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text('for $monthsLeft month${monthsLeft == 1 ? '' : 's'}', style: tt.labelSmall),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: due <= 0 ? 0 : (paidThisYear / due).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 4),
            Text('Paid this zakat year ${money(paidThisYear)} · remaining ${money(remaining)}', style: tt.bodySmall),
          ],
          if (start == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Set the zakat year start in Settings to see the due date.',
                  style: tt.bodySmall?.copyWith(color: cs.tertiary)),
            ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.volunteer_activism, size: 18),
              label: const Text('Record zakat paid'),
              onPressed: () => _recordPaid(context, n),
            ),
            TextButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('What to count'),
              onPressed: () => _whatToCount(context, n, mine, madhab),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _recordPaid(BuildContext context, String n) async {
    final c = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Zakat paid — $n', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'To (optional)', border: OutlineInputBorder()),
            ),
            TextButton.icon(
              icon: const Icon(Icons.event),
              label: Text(DateFormat('d MMM yyyy').format(date)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setS(() => date = d);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  final a = double.tryParse(c.text.replaceAll(',', ''));
                  if (a == null || a <= 0) return;
                  await widget.repo.addZakatPaid(
                      amount: a, member: n, date: date, note: note.text.trim().isEmpty ? null : note.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _whatToCount(BuildContext context, String n, List<MoneyItem> mine, String madhab) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StreamBuilder<List<MoneyItem>>(
        stream: widget.repo.moneyStream(),
        builder: (ctx, snap) {
          final list = (snap.data ?? mine)
              .where((m) => m.member == n && ['gold', 'cash', 'asset', 'receivable'].contains(m.kind))
              .where((m) => m.kind != 'receivable' || !m.received)
              .toList();
          final tt = Theme.of(ctx).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: ListView(shrinkWrap: true, children: [
              Text('What to count for $n', style: tt.titleLarge),
              const SizedBox(height: 4),
              Text('Untick anything that should not be counted (e.g. a debt you may never get back, '
                  'a pension fund you cannot access).', style: tt.bodySmall),
              const SizedBox(height: 8),
              if (list.isEmpty) const Text('Nothing added in the Money tab yet.'),
              for (final m in list)
                Column(children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: !m.zakatExclude,
                    onChanged: (v) => widget.repo.setMoneyFlags(m, zakatExclude: !(v ?? true)),
                    title: Text(m.isGold
                        ? '${m.title.isEmpty ? 'Gold' : m.title} · ${pavan(m.grams)}'
                        : '${m.title} · ${money(m.amount)}'),
                    subtitle: Text({'gold': 'Gold', 'cash': 'Cash', 'asset': 'Other savings', 'receivable': 'Owed to you'}[m.kind]!),
                  ),
                  if (m.isGold)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 32),
                      dense: true,
                      value: m.worn,
                      onChanged: (v) => widget.repo.setMoneyFlags(m, worn: v),
                      title: const Text('Jewellery worn regularly'),
                      subtitle: Text(madhab == 'shafii' ? "Not counted (Shafi'i)" : 'Still counted (Hanafi)'),
                    ),
                ]),
            ]),
          );
        },
      ),
    );
  }

  // ---------------- interest ----------------

  Widget _interestSection(BuildContext context, List<IncomeEntry> interest, List<String> names) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pending = interest.where((e) => !e.givenAway).toList();
    final total = pending.fold(0.0, (s, e) => s + e.amount);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.block, color: cs.error),
            const SizedBox(width: 8),
            Expanded(child: Text('Bank interest to give away', style: tt.titleMedium)),
            Text(money(total), style: tt.titleMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Interest credited by banks is picked up from SMS automatically. It is not counted as income or '
            'zakatable wealth. Tick it once you have given it away (without intention of reward).',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 8),
          if (interest.isEmpty) Text('No bank interest found yet.', style: tt.bodySmall),
          for (final e in interest)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: e.givenAway,
              onChanged: (v) => widget.repo.setGivenAway(e, v ?? false),
              title: Text('${money(e.amount)} · ${e.member}',
                  style: TextStyle(decoration: e.givenAway ? TextDecoration.lineThrough : null)),
              subtitle: Text('${DateFormat('d MMM yyyy').format(e.date)}${e.givenAway ? ' · given away' : ''}'),
              secondary: IconButton(
                tooltip: 'Not interest',
                icon: const Icon(Icons.undo),
                onPressed: () => widget.repo.markInterest(e, false),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add interest by hand'),
              onPressed: () => _addInterest(context, names),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _addInterest(BuildContext context, List<String> names) async {
    final c = TextEditingController();
    var who = names.contains(widget.repo.myName) ? widget.repo.myName : names.first;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bank interest received', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final n in names)
                ChoiceChip(label: Text(n), selected: who == n, onSelected: (_) => setS(() => who = n)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  final a = double.tryParse(c.text.replaceAll(',', ''));
                  if (a == null || a <= 0) return;
                  await widget.repo.addInterest(amount: a, member: who, date: DateTime.now());
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
