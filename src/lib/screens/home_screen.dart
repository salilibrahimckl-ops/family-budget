import 'package:flutter/material.dart';

import '../categories.dart';
import '../config.dart';
import '../repo.dart';
import 'common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repo,
    required this.month,
    required this.onMonth,
    required this.onRefresh,
    required this.onOpenTxns,
  });
  final Repo repo;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final Future<void> Function() onRefresh;
  final void Function({String? member}) onOpenTxns;

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
  });
  final Repo repo;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final Future<void> Function() onRefresh;
  final void Function({String? member}) onOpenTxns;
  final Budget budget;
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final spentBy = <String, double>{};
    for (final t in txns) {
      spentBy[t.category] = (spentBy[t.category] ?? 0) + t.amount;
    }
    final spendCats = kCats.where((c) => !c.goal);
    final goalCats = kCats.where((c) => c.goal);
    final spendBudget = spendCats.fold<double>(0, (s, c) => s + (budget.categories[c.id] ?? 0));
    final spendSpent = txns
        .where((t) => !catById(t.category).goal)
        .fold<double>(0, (s, t) => s + t.amount);

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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(child: MonthSwitcher(month: month, onChanged: onMonth)),
          const SizedBox(height: 8),
          _SummaryCard(budget: spendBudget, spent: spendSpent),
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
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.budget, required this.spent});
  final double budget, spent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final left = budget - spent;
    final frac = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final over = left < 0;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(over ? 'Over budget by' : 'Left to spend this month',
              style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
          const SizedBox(height: 4),
          Text(money(left.abs()),
              style: tt.displaySmall?.copyWith(
                  color: over ? cs.error : cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              backgroundColor: cs.surface.withValues(alpha: 0.5),
              color: over ? cs.error : cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text('${money(spent)} spent of ${money(budget)}',
              style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer)),
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
