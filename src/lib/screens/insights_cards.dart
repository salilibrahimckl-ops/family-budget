import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../insights.dart';
import '../repo.dart';
import 'common.dart';

/// Overview: early warnings before a budget runs out, plus a month-end forecast.
class AlertsCard extends StatefulWidget {
  const AlertsCard({super.key, required this.budget, required this.txns, required this.month});
  final Budget budget;
  final List<Txn> txns;
  final DateTime month;
  @override
  State<AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<AlertsCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final alerts = budgetAlerts(widget.budget, widget.txns, widget.month);
    final f = monthForecast(widget.budget, widget.txns, widget.month);
    if (f == null || f.budget <= 0) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final over = alerts.any((a) => a.level == 2);
    final bg = alerts.isEmpty ? cs.secondaryContainer : (over ? cs.errorContainer : cs.tertiaryContainer);
    final fg = alerts.isEmpty ? cs.onSecondaryContainer : (over ? cs.onErrorContainer : cs.onTertiaryContainer);
    final shown = _all ? alerts : alerts.take(2).toList();

    final pct = (f.projected / f.budget * 100).round();
    final forecast = f.day < 5
        ? 'Spent ${money(f.spent)} of ${money(f.budget)} so far. A forecast appears from the 5th.'
        : f.onTrack
            ? 'On track: about ${money(f.projected)} by month end ($pct% of ${money(f.budget)}).'
            : 'Heading for about ${money(f.projected)} by month end: ${money(f.projected - f.budget)} over the ${money(f.budget)} budget.';

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(alerts.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: fg, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(alerts.isEmpty ? 'All budgets on track' : 'Heads-up',
                  style: tt.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(forecast, style: tt.bodyMedium?.copyWith(color: fg)),
          for (final a in shown) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(a.level == 2 ? Icons.error : Icons.speed, size: 18, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: tt.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                  Text(a.body, style: tt.bodySmall?.copyWith(color: fg)),
                ]),
              ),
            ]),
          ],
          if (alerts.length > 2)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Show less' : 'Show all ${alerts.length}', style: TextStyle(color: fg)),
              ),
            )
          else
            const SizedBox(height: 4),
        ]),
      ),
    );
  }
}

/// Overview: a few plain-language lines about the month, compared with last month.
class MoneyStoryCard extends StatefulWidget {
  const MoneyStoryCard({super.key, required this.repo, required this.month, required this.txns});
  final Repo repo;
  final DateTime month;
  final List<Txn> txns;
  @override
  State<MoneyStoryCard> createState() => _MoneyStoryCardState();
}

class _MoneyStoryCardState extends State<MoneyStoryCard> {
  final _subs = <StreamSubscription>[];
  List<Txn> _prev = const [];
  double _income = 0, _prevIncome = 0;
  bool _open = false;
  String? _mk;

  double _sumIncome(List<IncomeEntry> l) =>
      l.where((e) => e.counted && !e.isInterest).fold(0.0, (s, e) => s + e.amount);

  void _listen() {
    final mk = monthKey(widget.month);
    if (mk == _mk) return;
    _mk = mk;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final pk = monthKey(DateTime(widget.month.year, widget.month.month - 1));
    _subs.add(widget.repo.monthTxns(pk).listen((l) => mounted ? setState(() => _prev = l) : null, onError: (_) {}));
    _subs.add(widget.repo.incomeStream(mk).listen((l) => mounted ? setState(() => _income = _sumIncome(l)) : null,
        onError: (_) {}));
    _subs.add(widget.repo.incomeStream(pk).listen((l) => mounted ? setState(() => _prevIncome = _sumIncome(l)) : null,
        onError: (_) {}));
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(MoneyStoryCard old) {
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

  @override
  Widget build(BuildContext context) {
    final lines = monthStory(
        month: widget.month, cur: widget.txns, prev: _prev, income: _income, prevIncome: _prevIncome);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrent = now.year == widget.month.year && now.month == widget.month.month;
    final name = DateFormat('MMMM').format(widget.month);
    final shown = _open ? lines : lines.take(3).toList();
    Color moodColor(int m) => m > 0 ? Colors.green.shade700 : (m < 0 ? cs.error : cs.primary);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: lines.length > 3 ? () => setState(() => _open = !_open) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_stories_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(isCurrent ? '$name so far' : '$name story',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            for (final l in shown)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(l.icon, size: 18, color: moodColor(l.mood)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l.text, style: tt.bodyMedium)),
                ]),
              ),
            if (lines.length > 3)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? 'Show less' : 'Read the full story'),
                ),
              )
            else
              const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}
