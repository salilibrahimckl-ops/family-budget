import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'common.dart';

/// One line of the explanation.
class GapItem {
  final String text;
  final double amount; // + raises the bank above the budget, − lowers it
  final DateTime? date;
  const GapItem(this.text, this.amount, [this.date]);
}

class GapReport {
  final BankAccount account;
  final double bank, left, gap;
  final List<GapItem> elsewhere; // spent, but not from the spending account
  final List<GapItem> moneyIn; // came into the account, not part of the budget
  final List<GapItem> movedOut; // left the account, not budget spending
  final double unexplained;
  final double correction; // corrections already made this month
  GapReport(this.account, this.bank, this.left, this.gap, this.elsewhere, this.moneyIn, this.movedOut,
      this.unexplained, this.correction);
}

GapReport? buildGap({
  required String member,
  required double limit,
  required BankAccount acct,
  required List<Txn> monthTxns, // including ignored
  required List<IncomeEntry> monthIncome,
}) {
  if (acct.balance == null) return null;
  bool fromAcct(Txn t) => t.paidFrom == acct.id || (t.account != null && acct.matches(t.account!));
  final mine = monthTxns.where((t) => t.member == member).toList();
  final spends = mine.where((t) => t.category != kIgnored && !catById(t.category).goal).toList();
  final spent = spends.fold<double>(0, (s, t) => s + t.amount);
  final left = limit - spent;
  final bank = acct.balance!;
  final gap = bank - left;

  String where(Txn t) {
    if (t.paidFrom == 'cash') return 'cash';
    if (t.account != null) return 'A/c ••${t.account}';
    if (t.source == 'manual') return 'added by hand, no account picked';
    if (t.source == 'quick') return 'GPay entry';
    if (t.source == 'card') return 'card';
    return 'another account';
  }

  String name(String p) => p.length > 22 ? '${p.substring(0, 22)}…' : p;
  final elsewhere = [
    for (final t in spends)
      if (t.source != 'adjust' && !fromAcct(t))
        GapItem(
            t.amount < 0 ? 'Refund ${name(t.payee)} (${where(t)})' : '${name(t.payee)} (${where(t)})', t.amount, t.date)
  ];
  final moneyIn = [
    for (final e in monthIncome)
      if (e.member == member && !e.refund && e.account != null && acct.matches(e.account!))
        GapItem('${name(e.from)}${e.isInterest ? ' (interest)' : ''}', e.amount, e.date)
  ];
  final movedOut = [
    for (final t in mine)
      if ((t.category == kIgnored || catById(t.category).goal) && fromAcct(t))
        GapItem('${name(t.payee)} (${t.category == kIgnored ? 'not a spend' : catById(t.category).label})', -t.amount,
            t.date)
  ];
  double sum(List<GapItem> l) => l.fold(0.0, (s, i) => s + i.amount);
  final explained = sum(elsewhere) + sum(moneyIn) + sum(movedOut);
  final correction = mine.where((t) => t.source == 'adjust').fold<double>(0, (s, t) => s + t.amount);
  return GapReport(acct, bank, left, gap, elsewhere, moneyIn, movedOut, gap - explained, correction);
}

/// Under each person on Overview: checks "left to spend" against the real
/// balance of their spending account, explains any difference, and can keep
/// the two matched automatically.
class SpendCheck extends StatefulWidget {
  const SpendCheck({super.key, required this.repo, required this.member, required this.limit, required this.month});
  final Repo repo;
  final String member;
  final double? limit;
  final DateTime month;
  @override
  State<SpendCheck> createState() => _SpendCheckState();
}

class _SpendCheckState extends State<SpendCheck> {
  final _subs = <StreamSubscription>[];
  Map<String, dynamic>? _fam;
  List<BankAccount> _accounts = const [];
  List<Txn> _txns = const [];
  List<IncomeEntry> _income = const [];
  String? _mk;
  static final _autoDone = <String>{}; // one automatic correction per value per session

  void _listen() {
    final mk = monthKey(widget.month);
    if (mk == _mk) return;
    _mk = mk;
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..add(widget.repo.familyStream().listen((d) => _set(() => _fam = d.data()), onError: (_) {}))
      ..add(widget.repo.accountsStream().listen((l) => _set(() => _accounts = l), onError: (_) {}))
      ..add(widget.repo.monthTxns(mk).listen((l) => _set(() => _txns = l), onError: (_) {}))
      ..add(widget.repo.incomeStream(mk).listen((l) => _set(() => _income = l), onError: (_) {}));
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(SpendCheck old) {
    super.didUpdateWidget(old);
    _listen();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  BankAccount? get _acct {
    final id = (_fam?['spendAccounts'] as Map?)?[widget.member] as String?;
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool get _auto => (_fam?['autoMatch'] as Map?)?[widget.member] == true;

  bool get _isCurrent {
    final now = DateTime.now();
    return now.year == widget.month.year && now.month == widget.month.month;
  }

  @override
  Widget build(BuildContext context) {
    final limit = widget.limit ?? 0;
    if (!_isCurrent || limit <= 0 || _fam == null) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final acct = _acct;
    final mineAccts = _accounts.where((a) => a.member == widget.member).toList();

    if (acct == null) {
      if (mineAccts.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: TextButton.icon(
          icon: const Icon(Icons.link, size: 18),
          label: Text('Check ${widget.member.split(' ').first}\'s balance against the bank'),
          onPressed: () => _pickAccount(context, mineAccts),
        ),
      );
    }

    final r = buildGap(member: widget.member, limit: limit, acct: acct, monthTxns: _txns, monthIncome: _income);
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text('Set the balance of ${acct.title} to compare it with the budget.', style: tt.bodySmall),
      );
    }

    // Automatic matching: only on the person's own phone, only against a
    // balance printed by the bank, only for small drift (a big gap at the start
    // of a month is a decision, not a correction), and only if it is still
    // there after a short wait (the balance SMS lands just before its payment).
    final drift = r.gap.abs() >= 1 && r.gap.abs() <= (limit * 0.1 < 2000 ? 2000 : limit * 0.1);
    if (_auto && drift && r.account.exact && widget.member == widget.repo.myName) {
      final key = '${widget.member}|${r.bank}|${r.left.toStringAsFixed(2)}';
      if (_autoDone.add(key)) {
        Timer(const Duration(seconds: 20), () {
          if (!mounted) return;
          final a = _acct;
          if (a == null) return;
          final again = buildGap(member: widget.member, limit: limit, acct: a, monthTxns: _txns, monthIncome: _income);
          if (again != null && (again.gap - r.gap).abs() < 1 && again.account.exact) {
            widget.repo.addCorrection(widget.member, -again.gap, DateTime.now());
          }
        });
      }
    }

    final ok = r.gap.abs() < 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ok ? cs.secondaryContainer.withValues(alpha: 0.5) : cs.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _details(context, r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(children: [
              Icon(ok ? Icons.verified_outlined : Icons.compare_arrows, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok
                      ? '${r.account.title} ${money(r.bank)} matches the budget left.'
                      : '${r.account.title} ${money(r.bank)} vs budget left ${money(r.left)}: '
                          '${money(r.gap.abs())} difference. Tap to see why.',
                  style: tt.bodySmall,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAccount(BuildContext context, List<BankAccount> accts) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Which account holds ${widget.member.split(' ').first}\'s spending money for the month?',
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final a in accts)
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text(a.title),
              subtitle: Text(a.balance == null ? 'Balance not set' : money(a.balance!)),
              onTap: () async {
                await widget.repo.setSpendAccount(widget.member, a.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _details(BuildContext context, GapReport r) async {
    final first = widget.member.split(' ').first;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final tt = Theme.of(ctx).textTheme;
        final cs = Theme.of(ctx).colorScheme;
        final auto = _auto;
        Widget row(String a, double v, {bool bold = false, String? sub}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a, style: bold ? tt.titleSmall : tt.bodyMedium),
                    if (sub != null) Text(sub, style: tt.bodySmall),
                  ]),
                ),
                Text('${v > 0 ? '+' : v < 0 ? '−' : ''}${money(v.abs())}',
                    style: bold ? tt.titleSmall : tt.bodyMedium),
              ]),
            );
        Widget group(String title, String help, List<GapItem> items) {
          if (items.isEmpty) return const SizedBox.shrink();
          final total = items.fold<double>(0, (s, i) => s + i.amount);
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              row(title, total, bold: true, sub: help),
              for (final i in (items.toList()..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()))).take(8))
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: row(
                      '${i.text}${i.date != null ? ' · ${DateFormat('d MMM').format(i.date!)}' : ''}', i.amount),
                ),
              if (items.length > 8)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('and ${items.length - 8} more', style: tt.bodySmall),
                ),
            ]),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Why the numbers differ', style: tt.titleLarge),
              const SizedBox(height: 12),
              row('${r.account.title} (${r.account.exact ? 'as per bank' : 'estimated'})', r.bank, bold: true),
              row('$first\'s budget left', r.left, bold: true),
              const Divider(),
              row('Difference', r.gap, bold: true),
              group('Spent from somewhere else', 'Counted in the budget, but did not leave ${r.account.title}.',
                  r.elsewhere),
              group('Money that came in', 'Raised the bank balance, but is not budget money.', r.moneyIn),
              group('Moved out, not spending', 'Left the account as savings, chitti set-aside or "not a spend".',
                  r.movedOut),
              if (r.unexplained.abs() >= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: row('Not seen by the app', r.unexplained,
                      bold: true,
                      sub: 'Payments or money in without an SMS (UPI Lite, bank app, charges), '
                          'or a start-of-month balance that was not exactly the budget.'),
                ),
              if (r.correction.abs() >= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('Corrections already made this month: ${money(r.correction)}', style: tt.bodySmall),
                ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: auto,
                onChanged: (v) async {
                  await widget.repo.setAutoMatch(widget.member, v);
                  set(() {});
                },
                title: Text('Keep the budget matched to ${r.account.title}'),
                subtitle: const Text('Whenever the bank sends the real balance, small differences (up to 10% of the limit) '
                    'are corrected on this person\'s own phone. Each correction shows in Payments, so nothing is hidden.'),
              ),
              if (r.gap.abs() >= 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text('Match budget to ${r.account.title} now'),
                    onPressed: () async {
                      await widget.repo.addCorrection(widget.member, -r.gap, DateTime.now());
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickAccount(context, _accounts.where((a) => a.member == widget.member).toList());
                  },
                  child: const Text('Change account'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await widget.repo.setSpendAccount(widget.member, null);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text('Stop checking', style: TextStyle(color: cs.error)),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
  }
}
