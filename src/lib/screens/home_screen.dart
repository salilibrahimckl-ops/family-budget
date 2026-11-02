import 'package:flutter/material.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'balances.dart';
import 'charts.dart';
import 'common.dart';
import '../updater.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repo,
    required this.month,
    required this.onMonth,
    required this.onRefresh,
    required this.onOpenTxns,
    this.updateAvailable = false,
  });
  final Repo repo;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final Future<void> Function() onRefresh;
  final void Function({String? member}) onOpenTxns;
  final bool updateAvailable;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _mk;
  late Stream<Budget> _budget;
  late Stream<List<Txn>> _txns;

  void _ensureStreams() {
    final mk = monthKey(widget.month);
    if (mk == _mk) return;
    _mk = mk;
    _budget = widget.repo.budgetStream(mk);
    _txns = widget.repo.monthTxns(mk);
  }

  @override
  Widget build(BuildContext context) {
    _ensureStreams();
    return StreamBuilder<Budget>(
      stream: _budget,
      builder: (context, bSnap) => StreamBuilder<List<Txn>>(
        stream: _txns,
        builder: (context, tSnap) {
          if (tSnap.hasError || bSnap.hasError) {
            return Center(child: Text('Error: ${tSnap.error ?? bSnap.error}'));
          }
          if (!tSnap.hasData || !bSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _Body(
            repo: widget.repo,
            month: widget.month,
            onMonth: widget.onMonth,
            onRefresh: widget.onRefresh,
            onOpenTxns: widget.onOpenTxns,
            updateAvailable: widget.updateAvailable,
            budget: bSnap.data!,
            txns: tSnap.data!.where((t) => t.category != kIgnored).toList(),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.repo,
    required this.month,
    required this.onMonth,
    required this.onRefresh,
    required this.onOpenTxns,
    required this.budget,
    required this.txns,
    this.updateAvailable = false,
  });
  final bool updateAvailable;
  final Repo repo;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final Future<void> Function() onRefresh;
  final void Function({String? member}) onOpenTxns;
  final Budget budget;
  final List<Txn> txns;

  Map<String, double> _spentByFor(String member) {
    final m = <String, double>{};
    for (final t in txns) {
      if (t.member != member || catById(t.category).goal) continue;
      m[t.category] = (m[t.category] ?? 0) + t.amount;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final spentBy = <String, double>{};
    for (final t in txns) {
      spentBy[t.category] = (spentBy[t.category] ?? 0) + t.amount;
    }
    final spendCats = kCats.where((c) => !c.goal);
    final goalCats = kCats.where((c) => c.goal);
    // Family 100% = category budgets for spending; if none are set, the
    // personal limits added together.
    final catBudget = spendCats.fold<double>(0, (s, c) => s + (budget.categories[c.id] ?? 0));
    final personalTotal = budget.members.values.fold<double>(0, (s, v) => s + v);
    final spendBudget = catBudget > 0 ? catBudget : personalTotal;
    final familyCaption = catBudget > 0
        ? 'Full circle = family spending budget'
        : (personalTotal > 0
            ? 'Full circle = both personal limits together'
            : 'Set a budget in the Budget tab');

    final chittiAsks = txns.where((t) => t.chittiSuggest).toList();
    final untagged = txns.where((t) => t.category == kUncategorised).toList();

    final members = <String, ({double spend, double aside})>{};
    for (final name in budget.members.keys) {
      members[name] = (spend: 0.0, aside: 0.0);
    }
    for (final t in txns) {
      final cur = members[t.member] ?? (spend: 0.0, aside: 0.0);
      members[t.member] = catById(t.category).goal
          ? (spend: cur.spend, aside: cur.aside + t.amount)
          : (spend: cur.spend + t.amount, aside: cur.aside);
    }

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // Daily totals for the bar chart (spending categories only).
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final perDay = List<double>.filled(daysInMonth, 0);
    for (final t in txns) {
      if (!catById(t.category).goal && t.date.month == month.month && t.date.year == month.year) {
        perDay[t.date.day - 1] += t.amount;
      }
    }
    final now = DateTime.now();
    final isCurrent = now.year == month.year && now.month == month.month;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addSpend',
        onPressed: () => showAddSheet(context, repo),
        icon: const Icon(Icons.add),
        label: const Text('Add spending'),
      ),
      body: RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Center(child: MonthSwitcher(month: month, onChanged: onMonth)),
          const SizedBox(height: 8),
          if (updateAvailable) ...[
            Card(
              color: Theme.of(context).colorScheme.primary,
              child: ListTile(
                leading: Icon(Icons.system_update, color: Theme.of(context).colorScheme.onPrimary),
                title: Text('Update available',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text('Tap to install the new version',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                trailing: FilledButton.tonal(
                    onPressed: () => showUpdateDialog(context), child: const Text('Update')),
                onTap: () => showUpdateDialog(context),
              ),
            ),
            const SizedBox(height: 12),
          ],
          BalancesCard(repo: repo),
          const SizedBox(height: 12),
          _BudgetRing(
            title: 'Family',
            caption: familyCaption,
            budget: spendBudget,
            spentBy: {
              for (final e in spentBy.entries)
                if (!catById(e.key).goal) e.key: e.value,
            },
            cats: spendCats.toList(),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, box) {
            final names = {...budget.members.keys, ...txns.map((t) => t.member)}.toList()..sort();
            if (names.isEmpty) return const SizedBox.shrink();
            final w = names.length == 1 ? box.maxWidth : (box.maxWidth - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final n in names)
                SizedBox(
                  width: w,
                  child: _BudgetRing(
                    compact: true,
                    title: n,
                    caption: (budget.members[n] ?? 0) > 0
                        ? 'Full circle = personal limit'
                        : 'No personal limit: full circle = family budget',
                    budget: (budget.members[n] ?? 0) > 0 ? budget.members[n]! : spendBudget,
                    spentBy: _spentByFor(n),
                    cats: spendCats.toList(),
                  ),
                ),
            ]);
          }),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Spent vs budget',
            subtitle: 'Light bar = budget, solid bar = spent',
            child: BudgetBars(items: [
              for (final c in spendCats)
                (c.label, spentBy[c.id] ?? 0, budget.categories[c.id] ?? 0, c.color),
            ]),
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Daily spending',
            subtitle: spendBudget > 0
                ? 'Dashed line = ${money(spendBudget / daysInMonth)} a day keeps you on budget'
                : 'Set a budget to see your daily limit',
            child: DailyBars(
              perDay: perDay,
              dailyBudget: spendBudget > 0 ? spendBudget / daysInMonth : 0,
              today: isCurrent ? now.day : null,
            ),
          ),
          for (final t in chittiAsks) ...[
            const SizedBox(height: 12),
            _ChittiCard(repo: repo, t: t),
          ],
          if (untagged.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: cs.errorContainer,
              child: ListTile(
                leading: Icon(Icons.label_outline, color: cs.onErrorContainer),
                title: Text('${untagged.length} payment${untagged.length == 1 ? '' : 's'} need a category',
                    style: TextStyle(color: cs.onErrorContainer)),
                subtitle: Text('${money(untagged.fold<double>(0, (s, t) => s + t.amount))} · tap to tag',
                    style: TextStyle(color: cs.onErrorContainer)),
                trailing: Icon(Icons.chevron_right, color: cs.onErrorContainer),
                onTap: () => showTxnSheet(context, repo, untagged.first),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Spending', style: tt.titleMedium),
          const SizedBox(height: 8),
          for (final c in spendCats)
            _CatRow(cat: c, budget: budget.categories[c.id] ?? 0, spent: spentBy[c.id] ?? 0),
          const SizedBox(height: 16),
          Text('Set aside', style: tt.titleMedium),
          const SizedBox(height: 8),
          for (final c in goalCats)
            _CatRow(cat: c, budget: budget.categories[c.id] ?? 0, spent: spentBy[c.id] ?? 0),
          const SizedBox(height: 16),
          Text('Each of us', style: tt.titleMedium),
          const SizedBox(height: 8),
          if (members.isEmpty)
            Text('No payments yet this month.', style: tt.bodyMedium)
          else
            for (final e in members.entries)
              _MemberRow(
                name: e.key,
                spend: e.value.spend,
                aside: e.value.aside,
                limit: budget.members[e.key],
                onTap: () => onOpenTxns(member: e.key),
              ),
        ],
      ),
    ),
    );
  }
}

/// Ring chart where the full circle (100%) is the spending budget.
/// Coloured slices = share of the budget used by each category, grey = left.
class _BudgetRing extends StatelessWidget {
  const _BudgetRing({
    required this.title,
    required this.budget,
    required this.spentBy,
    required this.cats,
    this.caption,
    this.compact = false,
  });
  final String title;
  final String? caption;
  final double budget;
  final Map<String, double> spentBy; // spending categories (+ untagged) only
  final List<Cat> cats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final segments = [
      for (final c in cats) Segment(spentBy[c.id] ?? 0, c.color, c.label),
      if ((spentBy[kUncategorised] ?? 0) > 0) Segment(spentBy[kUncategorised]!, cs.error, 'To tag'),
    ];
    final spent = segments.fold<double>(0, (s, e) => s + e.value);
    final left = budget - spent;
    final over = budget > 0 && left < 0;
    final pct = budget > 0 ? (spent / budget * 100) : 0.0;
    // When within budget the ring totals the budget (grey = left);
    // when over, it totals what was spent and the centre turns red.
    final ring = [
      ...segments,
      if (!over && budget > 0) Segment(left, cs.onSurface.withValues(alpha: 0.10), 'Left'),
    ];
    final size = compact ? 132.0 : 210.0;
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 14, compact ? 10 : 16, 14),
        child: Column(children: [
          Text(title,
              style: (compact ? tt.titleSmall : tt.titleMedium)?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (caption != null)
            Text(caption!, style: tt.labelSmall, textAlign: TextAlign.center, maxLines: 2),
          SizedBox(height: compact ? 8 : 12),
          if (over)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.error, width: 2)),
              child: _ring(ring, size - 6, compact, pct, over, left, budget, tt, cs),
            )
          else
            _ring(ring, size, compact, pct, over, left, budget, tt, cs),
          SizedBox(height: compact ? 8 : 14),
          if (!compact)
            Row(children: [
              Expanded(child: _stat(context, 'Spent', money(spent), over ? cs.error : null)),
              Expanded(child: _stat(context, 'Budget (100%)', budget > 0 ? money(budget) : 'not set', null)),
              Expanded(
                  child: _stat(context, over ? 'Over' : 'Left', budget > 0 ? money(left.abs()) : '—',
                      over ? cs.error : cs.primary)),
            ])
          else
            Text(budget > 0 ? '${money(spent)} of ${money(budget)}' : '${money(spent)} spent',
                style: tt.bodySmall, textAlign: TextAlign.center),
          SizedBox(height: compact ? 6 : 12),
          ChartLegend(segments, total: budget > 0 ? budget : null, showMoney: !compact),
        ]),
      ),
    );
  }

  Widget _ring(List<Segment> ring, double size, bool compact, double pct, bool over, double left,
      double budget, TextTheme tt, ColorScheme cs) {
    return DonutChart(
      segments: ring,
      size: size,
      thickness: compact ? 16 : 28,
      center: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(budget > 0 ? '${pct.round()}%' : '—',
            style: (compact ? tt.titleLarge : tt.headlineMedium)
                ?.copyWith(fontWeight: FontWeight.w700, color: over ? cs.error : cs.primary)),
        Text(budget <= 0 ? 'no budget' : (over ? 'over budget' : 'used'),
            style: compact ? tt.labelSmall : tt.bodySmall),
        if (!compact && budget > 0)
          Text(over ? 'over by ${money(left.abs())}' : '${money(left)} left',
              style: tt.bodySmall?.copyWith(color: over ? cs.error : null)),
      ]),
    );
  }

  Widget _stat(BuildContext context, String label, String value, Color? color) {
    final tt = Theme.of(context).textTheme;
    return Column(children: [
      Text(label, style: tt.bodySmall),
      const SizedBox(height: 2),
      Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.subtitle, required this.child});
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: tt.titleMedium),
          Text(subtitle, style: tt.bodySmall),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _CatRow extends StatelessWidget {
  const _CatRow({required this.cat, required this.budget, required this.spent});
  final Cat cat;
  final double budget, spent;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final frac = budget <= 0 ? (spent > 0 ? 1.0 : 0.0) : (spent / budget).clamp(0.0, 1.0);
    final over = !cat.goal && spent > budget && budget > 0;
    final String right;
    if (cat.goal) {
      right = budget > 0 ? '${money(spent)} of ${money(budget)}' : money(spent);
    } else if (budget <= 0) {
      right = '${money(spent)} spent';
    } else {
      right = over ? '${money(spent - budget)} over' : '${money(budget - spent)} left';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CatAvatar(cat),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(cat.label, style: tt.titleSmall),
              const Spacer(),
              Text(right,
                  style: tt.bodyMedium?.copyWith(
                      color: over ? cs.error : null, fontWeight: over ? FontWeight.w600 : null)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: cat.color.withValues(alpha: 0.12),
                color: over ? cs.error : cat.color,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.spend,
    required this.aside,
    required this.limit,
    required this.onTap,
  });
  final String name;
  final double spend, aside;
  final double? limit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasLimit = limit != null && limit! > 0;
    final bal = hasLimit ? limit! - spend : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
        title: Text(name),
        subtitle: Text('Spent ${money(spend)}${aside > 0 ? ' · set aside ${money(aside)}' : ''}'),
        trailing: bal == null
            ? const Icon(Icons.chevron_right)
            : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(bal.abs()),
                    style: TextStyle(fontWeight: FontWeight.w600, color: bal < 0 ? cs.error : cs.primary)),
                Text(bal < 0 ? 'over limit' : 'balance', style: Theme.of(context).textTheme.bodySmall),
              ]),
      ),
    );
  }
}

class _ChittiCard extends StatelessWidget {
  const _ChittiCard({required this.repo, required this.t});
  final Repo repo;
  final Txn t;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chitti = catById('chitti');
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CatAvatar(chitti, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Is this your chitti?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onTertiaryContainer)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            '${money(t.amount)} to ${t.payee} looks like a fixed monthly payment.',
            style: TextStyle(color: cs.onTertiaryContainer),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => repo.answerChitti(t, false), child: const Text('No')),
            FilledButton.tonal(onPressed: () => repo.answerChitti(t, true), child: const Text('Yes, add to Chitti')),
          ]),
        ]),
      ),
    );
  }
}
