import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../repo.dart';
import 'charts.dart';
import 'common.dart';

/// Today's Kerala gold rate, published by the "Gold rate" GitHub job.
class GoldRate {
  final double rate22, rate24;
  final DateTime? at;
  final String source;
  final bool approx;
  const GoldRate(this.rate22, this.rate24, this.at, this.source, this.approx);

  static Future<GoldRate?> fetch() async {
    try {
      final r = await http
          .get(Uri.parse('https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/data/gold.json'
              '?t=${DateTime.now().millisecondsSinceEpoch ~/ 600000}'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return GoldRate((j['rate22'] as num).toDouble(), (j['rate24'] as num).toDouble(),
          DateTime.tryParse(j['at'] as String? ?? ''), j['source'] as String? ?? '', j['approx'] == true);
    } catch (_) {
      return null;
    }
  }
}

/// A small gold coin: gold disc with a raised rim and a ₹ mark.
class GoldCoin extends StatelessWidget {
  const GoldCoin({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.35, -0.35),
            colors: [Color(0xFFFFF1A8), Color(0xFFF2C94C), Color(0xFFC9971C), Color(0xFF9C7310)],
            stops: [0.0, 0.35, 0.75, 1.0],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Center(
          child: Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFF6C8).withValues(alpha: 0.8), width: size * 0.04),
            ),
            child: Center(
              child: Text('₹',
                  style: TextStyle(
                      fontSize: size * 0.4, fontWeight: FontWeight.w800, color: const Color(0xFF7A5A0A), height: 1)),
            ),
          ),
        ),
      );
}

/// A green banknote for cash.
class CashNote extends StatelessWidget {
  const CashNote({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(Icons.payments, color: const Color(0xFF2E7D32), size: size * 0.55),
      );
}

String grams(double g) => '${g.toStringAsFixed(g == g.roundToDouble() ? 0 : 2)} g';
String pavan(double g) => '${(g / 8).toStringAsFixed((g / 8) == (g / 8).roundToDouble() ? 0 : 2)} pavan';

class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key, required this.repo});
  final Repo repo;
  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  late final _accounts = widget.repo.accountsStream();
  late final _money = widget.repo.moneyStream();
  late final _family = widget.repo.familyStream();
  late final _setAside = widget.repo.setAsideStream();
  GoldRate? _auto;
  bool _showReceived = false;

  @override
  void initState() {
    super.initState();
    GoldRate.fetch().then((g) => mounted ? setState(() => _auto = g) : null);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _family,
      builder: (context, famSnap) => StreamBuilder<List<BankAccount>>(
        stream: _accounts,
        builder: (context, accSnap) => StreamBuilder<List<MoneyItem>>(
          stream: _money,
          builder: (context, monSnap) => StreamBuilder<SetAside>(
            stream: _setAside,
            builder: (context, saSnap) {
              final fam = famSnap.data?.data();
              final members = (Map<String, dynamic>.from(fam?['members'] as Map? ?? {}).values.cast<String>().toSet()
                    ..addAll((accSnap.data ?? []).map((a) => a.member))
                    ..addAll((monSnap.data ?? []).map((m) => m.member)))
                  .toList()
                ..sort();
              final manual = widget.repo.goldRatesFrom(fam);
              // Automatic rate first; your own rate only if the automatic one isn't available.
              final rates = <int, double>{
                22: _auto?.rate22 ?? manual[22] ?? 0,
                24: _auto?.rate24 ?? manual[24] ?? 0,
              };
              return _body(context, members, accSnap.data ?? const [], monSnap.data ?? const [],
                  saSnap.data ?? const SetAside({}, {}), rates, manual);
            },
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<String> members, List<BankAccount> accts, List<MoneyItem> items,
      SetAside setAside, Map<int, double> rates, Map<int, double> manual) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final receivables = items.where((m) => m.kind == 'receivable').toList();
    final pending = receivables.where((m) => !m.received).toList();
    final received = receivables.where((m) => m.received).toList();
    final gold = items.where((m) => m.isGold).toList();
    final cash = items.where((m) => m.kind == 'cash').toList();
    final assets = items.where((m) => m.kind == 'asset').toList();

    double bankOf(String n) =>
        accts.where((a) => a.member == n && a.balance != null).fold(0.0, (s, a) => s + a.balance!);
    double goldOf(String n) => gold.where((g) => g.member == n).fold(0.0, (s, g) => s + g.value(rates));
    double gramsOf(String n) => gold.where((g) => g.member == n).fold(0.0, (s, g) => s + g.grams);
    double cashOf(String n) => cash.where((a) => a.member == n).fold(0.0, (s, a) => s + a.amount);
    double assetsOf(String n) => assets.where((a) => a.member == n).fold(0.0, (s, a) => s + a.amount);
    double pendingOf(String n) => pending.where((a) => a.member == n).fold(0.0, (s, a) => s + a.amount);

    final bankTotal = members.fold(0.0, (s, n) => s + bankOf(n));
    final goldTotal = members.fold(0.0, (s, n) => s + goldOf(n));
    final assetTotal = members.fold(0.0, (s, n) => s + assetsOf(n));
    final cashTotal = members.fold(0.0, (s, n) => s + cashOf(n));
    final pendingTotal = pending.fold(0.0, (s, m) => s + m.amount);
    double paidInOf(String n) => setAside.byMember[n] ?? 0;
    final paidIn = setAside.total;
    final haveNow = bankTotal + goldTotal + cashTotal + assetTotal + paidIn;

    // Monthly set-aside history (last 6 months).
    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    String mk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final allTimeSetAside = paidIn;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addMoney',
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: () => _chooseAdd(context, members, rates),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // ---- Total ----
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.savings, size: 18, color: cs.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text('Total savings till now', style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
                ]),
                Text(money(haveNow),
                    style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(
                  'Bank ${money(bankTotal)} · Gold ${money(goldTotal)} · Cash ${money(cashTotal)}'
                  ' · Other savings ${money(assetTotal)}'
                  '${paidIn > 0 ? ' · Chitti & savings paid ${money(paidIn)}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer),
                ),
                if (pendingTotal > 0) ...[
                  const SizedBox(height: 8),
                  Text('+ ${money(pendingTotal)} still to receive  →  ${money(haveNow + pendingTotal)}',
                      style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // ---- Per person ----
          Row(children: [
            for (final n in members) ...[
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(money(bankOf(n) + goldOf(n) + cashOf(n) + assetsOf(n) + paidInOf(n)),
                          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Bank ${money(bankOf(n))}', style: tt.bodySmall),
                      Row(children: [
                        const GoldCoin(size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                            child: Text('${pavan(gramsOf(n))} · ${money(goldOf(n))}',
                                style: tt.bodySmall, overflow: TextOverflow.ellipsis)),
                      ]),
                      if (cashOf(n) > 0)
                        Row(children: [
                          const CashNote(size: 14),
                          const SizedBox(width: 4),
                          Text('Cash ${money(cashOf(n))}', style: tt.bodySmall),
                        ]),
                      if (assetsOf(n) > 0) Text('Savings ${money(assetsOf(n))}', style: tt.bodySmall),
                      if (paidInOf(n) > 0) Text('Chitti & savings paid ${money(paidInOf(n))}', style: tt.bodySmall),
                      if (pendingOf(n) > 0)
                        Text('To receive ${money(pendingOf(n))}',
                            style: tt.bodySmall?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
              if (n != members.last) const SizedBox(width: 12),
            ],
          ]),
          const SizedBox(height: 20),

          // ---- Money to receive ----
          _header(context, Icons.call_received, 'Money to receive', pendingTotal > 0 ? money(pendingTotal) : null),
          if (pending.isEmpty)
            _hint(context, 'Add money you are waiting for: a loan being paid back, Hiba\'s pending stipend, etc.'),
          for (final m in pending) _receivableTile(context, m, members),
          if (received.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _showReceived = !_showReceived),
              child: Text(_showReceived ? 'Hide received' : 'Show received (${received.length})'),
            ),
          if (_showReceived) for (final m in received) _receivableTile(context, m, members),
          const SizedBox(height: 16),

          // ---- Gold ----
          _header(context, Icons.circle, 'Gold',
              gold.isEmpty ? null : '${pavan(gold.fold(0.0, (s, g) => s + g.grams))} · ${money(goldTotal)}',
              leading: const GoldCoin(size: 22)),
          _goldRateCard(context, rates, manual),
          for (final g in gold)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const GoldCoin(),
              title: Text(g.title.isEmpty ? 'Gold' : g.title),
              subtitle: Text('${g.member} · ${grams(g.grams)} (${pavan(g.grams)}) · ${g.purity}K'),
              trailing: Text((rates[g.purity] ?? 0) > 0 ? money(g.value(rates)) : '—',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _editGold(context, members, g),
            ),
          if (gold.isEmpty) _hint(context, 'Add gold for each of you in grams or pavan.'),
          const SizedBox(height: 16),

          // ---- Cash ----
          _header(context, Icons.payments, 'Cash in hand', cashTotal > 0 ? money(cashTotal) : null,
              leading: const CashNote(size: 22)),
          if (cash.isEmpty) _hint(context, 'Cash kept at home or in your wallet.'),
          for (final c in cash)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CashNote(),
              title: Text(c.title),
              subtitle: Text([c.member, if (c.note != null && c.note!.isNotEmpty) c.note!].join(' · ')),
              trailing: Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _editMoney(context, 'cash', members, c),
            ),
          const SizedBox(height: 16),

          // ---- Other savings ----
          _header(context, Icons.savings_outlined, 'Other savings', assetTotal > 0 ? money(assetTotal) : null),
          if (assets.isEmpty)
            _hint(context, 'FD, mutual funds, chitti paid so far… anything outside the bank balances.'),
          for (final a in assets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.savings)),
              title: Text(a.title),
              subtitle: Text([a.member, if (a.note != null && a.note!.isNotEmpty) a.note!].join(' · ')),
              trailing: Text(money(a.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _editMoney(context, 'asset', members, a),
            ),
          const SizedBox(height: 16),

          // ---- Monthly set aside ----
          _header(context, Icons.bar_chart, 'Set aside each month', 'all-time ${money(allTimeSetAside)}'),
          _hint(context, 'Savings + Chitti payments recorded in the app (included in the total above). '
              'Enter only what you paid *before* using the app under Other savings.'),
          const SizedBox(height: 8),
          BudgetBars(items: [
            for (final m in months)
              (DateFormat('MMM').format(m), setAside.byMonth[mk(m)] ?? 0, 0.0, const Color(0xFF1F6F43)),
          ]),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, IconData icon, String title, String? trailing, {Widget? leading}) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        leading ?? Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(title, style: tt.titleMedium),
        const Spacer(),
        if (trailing != null) Text(trailing, style: tt.titleSmall),
      ]),
    );
  }

  Widget _hint(BuildContext context, String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: Theme.of(context).textTheme.bodySmall));

  Widget _receivableTile(BuildContext context, MoneyItem m, List<String> members) {
    final cs = Theme.of(context).colorScheme;
    final overdue = !m.received && m.due != null && m.due!.isBefore(DateTime.now());
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: m.received,
        onChanged: (v) => widget.repo.setReceived(m, v ?? false),
      ),
      title: Text(m.title, style: TextStyle(decoration: m.received ? TextDecoration.lineThrough : null)),
      subtitle: Text([
        m.member,
        if (m.due != null) '${overdue ? 'was due' : 'expected'} ${DateFormat('d MMM yyyy').format(m.due!)}',
        if (m.received && m.receivedAt != null) 'received ${DateFormat('d MMM').format(m.receivedAt!)}',
        if (m.note != null && m.note!.isNotEmpty) m.note!,
      ].join(' · ')),
      trailing: Text(money(m.amount),
          style: TextStyle(fontWeight: FontWeight.w600, color: overdue ? cs.error : null)),
      onTap: () => _editMoney(context, 'receivable', members, m),
    );
  }

  Widget _goldRateCard(BuildContext context, Map<int, double> rates, Map<int, double> manual) {
    final tt = Theme.of(context).textTheme;
    final a = _auto;
    final status = a != null
        ? '${a.approx ? 'Approx. from international price' : 'Kerala rate'} · '
            '${a.at != null ? DateFormat('d MMM, h:mm a').format(a.at!) : ''}'
        : (manual.isNotEmpty ? 'Your rate (automatic rate not available)' : 'Automatic rate not available yet');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '22K ${rates[22]! > 0 ? '${money(rates[22]!)}/g · ${money(rates[22]! * 8)}/pavan' : '—'}',
          style: tt.titleSmall,
        ),
        subtitle: Text('24K ${rates[24]! > 0 ? '${money(rates[24]!)}/g' : '—'}\n$status'),
        isThreeLine: true,
        trailing: TextButton(onPressed: () => _setRate(context, manual), child: const Text('Set rate')),
      ),
    );
  }

  // ---------- add / edit sheets ----------

  void _chooseAdd(BuildContext context, List<String> members, Map<int, double> rates) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.call_received),
            title: const Text('Money to receive'),
            subtitle: const Text('Debt payback, pending stipend…'),
            onTap: () {
              Navigator.pop(ctx);
              _editMoney(context, 'receivable', members, null);
            },
          ),
          ListTile(
            leading: const GoldCoin(size: 28),
            title: const Text('Gold'),
            subtitle: const Text('In grams or pavan'),
            onTap: () {
              Navigator.pop(ctx);
              _editGold(context, members, null);
            },
          ),
          ListTile(
            leading: const CashNote(size: 28),
            title: const Text('Cash in hand'),
            subtitle: const Text('Cash at home or in your wallet'),
            onTap: () {
              Navigator.pop(ctx);
              _editMoney(context, 'cash', members, null);
            },
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Other savings'),
            subtitle: const Text('FD, mutual fund, chitti so far…'),
            onTap: () {
              Navigator.pop(ctx);
              _editMoney(context, 'asset', members, null);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _editMoney(BuildContext context, String kind, List<String> members, MoneyItem? m) async {
    final title = TextEditingController(text: m?.title ?? '');
    final amount = TextEditingController(text: m == null ? '' : m.amount.toStringAsFixed(0));
    final months = TextEditingController(text: '1');
    final note = TextEditingController(text: m?.note ?? '');
    var member = m?.member ?? widget.repo.myName;
    if (!members.contains(member) && members.isNotEmpty) member = members.first;
    DateTime? due = m?.due;
    final receivable = kind == 'receivable';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final perMonth = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
        final n = int.tryParse(months.text) ?? 1;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(receivable ? 'Money to receive' : (kind == 'cash' ? 'Cash in hand' : 'Other savings'),
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'What is it?',
                  hintText: receivable
                      ? 'e.g. Stipend arrears, Loan from Rahul'
                      : (kind == 'cash' ? 'e.g. Cash at home, Wallet' : 'e.g. SBI FD, KSFE chitti paid'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('For', style: Theme.of(ctx).textTheme.labelLarge),
              Wrap(spacing: 8, children: [
                for (final who in members)
                  ChoiceChip(label: Text(who), selected: member == who, onSelected: (_) => setS(() => member = who)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      labelText: receivable && m == null ? 'Amount (per month if repeated)' : 'Amount',
                      prefixText: '₹ ',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (receivable && m == null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: months,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setS(() {}),
                      decoration: const InputDecoration(labelText: '× months', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ]),
              if (receivable && m == null && n > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Total: ${money(perMonth * n)} ($n months × ${money(perMonth)})'),
                ),
              const SizedBox(height: 12),
              if (receivable)
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(due == null ? 'Expected date (optional)' : 'Expected ${DateFormat('d MMM yyyy').format(due!)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: due ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setS(() => due = d);
                  },
                ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(children: [
                if (m != null)
                  TextButton(
                    onPressed: () async {
                      await widget.repo.deleteMoney(m);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final a = double.tryParse(amount.text.replaceAll(',', ''));
                    if (a == null || title.text.trim().isEmpty) return;
                    final total = receivable && m == null ? a * (int.tryParse(months.text) ?? 1) : a;
                    await widget.repo.saveMoney(
                      id: m?.id,
                      kind: kind,
                      title: title.text.trim(),
                      member: member,
                      amount: total,
                      due: due,
                      note: note.text.trim().isEmpty ? null : note.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(m == null ? 'Add' : 'Save'),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _editGold(BuildContext context, List<String> members, MoneyItem? g) async {
    final title = TextEditingController(text: g?.title ?? '');
    var usePavan = g == null; // new entries default to pavan
    final qty = TextEditingController(
        text: g == null ? '' : (usePavan ? (g.grams / 8) : g.grams).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''));
    var purity = g?.purity ?? 22;
    var member = g?.member ?? widget.repo.myName;
    if (!members.contains(member) && members.isNotEmpty) member = members.first;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final q = double.tryParse(qty.text) ?? 0;
        final gm = usePavan ? q * 8 : q;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g == null ? 'Add gold' : 'Edit gold', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Item (optional)', hintText: 'e.g. Necklace, Bangles, Coin', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final n in members)
                ChoiceChip(label: Text(n), selected: member == n, onSelected: (_) => setS(() => member = n)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: qty,
                  autofocus: g == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: usePavan ? 'Pavan' : 'Grams', border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('pavan')), ButtonSegment(value: false, label: Text('g'))],
                selected: {usePavan},
                onSelectionChanged: (v) => setS(() {
                  final cur = double.tryParse(qty.text);
                  if (cur != null) {
                    final nv = v.first ? cur / 8 : cur * 8;
                    qty.text = nv.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
                  }
                  usePavan = v.first;
                }),
              ),
            ]),
            if (gm > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('= ${grams(gm)} = ${pavan(gm)}'),
              ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 22, label: Text('22K')), ButtonSegment(value: 24, label: Text('24K'))],
              selected: {purity},
              onSelectionChanged: (v) => setS(() => purity = v.first),
            ),
            const SizedBox(height: 16),
            Row(children: [
              if (g != null)
                TextButton(
                  onPressed: () async {
                    await widget.repo.deleteMoney(g);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  if (gm <= 0) return;
                  await widget.repo.saveMoney(
                    id: g?.id,
                    kind: 'gold',
                    title: title.text.trim(),
                    member: member,
                    amount: 0,
                    grams: gm,
                    purity: purity,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(g == null ? 'Add' : 'Save'),
              ),
            ]),
          ]),
        );
      }),
    );
  }

  Future<void> _setRate(BuildContext context, Map<int, double> manual) async {
    final r22 = TextEditingController(text: manual[22]?.toStringAsFixed(0) ?? _auto?.rate22.toStringAsFixed(0) ?? '');
    final r24 = TextEditingController(text: manual[24]?.toStringAsFixed(0) ?? _auto?.rate24.toStringAsFixed(0) ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gold rate per gram'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Used only when the automatic Kerala rate is not available.'),
          const SizedBox(height: 12),
          TextField(
            controller: r22,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '22K per gram', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: r24,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '24K per gram', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await widget.repo.setGoldRates(double.tryParse(r22.text), double.tryParse(r24.text));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
