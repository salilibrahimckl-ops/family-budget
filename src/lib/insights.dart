import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'categories.dart';
import 'repo.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _m(num v) => _inr.format(v);

bool _counts(Txn t) => t.category != kIgnored && !catById(t.category).goal;

// ---------------------------------------------------------------------------
// Early overspend alerts
// ---------------------------------------------------------------------------

class BudgetAlert {
  final String key; // 'family', 'member:Hiba', 'cat:food'
  final int level; // 1 = heads-up, 2 = over budget
  final String title;
  final String body;
  final double share; // used / limit
  const BudgetAlert(this.key, this.level, this.title, this.body, this.share);
}

class Forecast {
  final double spent, projected, budget;
  final int day, days;
  const Forecast(this.spent, this.projected, this.budget, this.day, this.days);
  bool get onTrack => budget <= 0 || projected <= budget;
}

/// Pace-based warnings for the current month. Empty for any other month.
List<BudgetAlert> budgetAlerts(Budget b, List<Txn> txns, DateTime month, {DateTime? now}) {
  now ??= DateTime.now();
  if (now.year != month.year || now.month != month.month) return [];
  final days = DateTime(month.year, month.month + 1, 0).day;
  final day = now.day;
  final left = days - day + 1; // days left, today included

  final byCat = <String, double>{};
  final byMember = <String, double>{};
  var total = 0.0;
  for (final t in txns.where(_counts)) {
    byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    byMember[t.member] = (byMember[t.member] ?? 0) + t.amount;
    total += t.amount;
  }

  final out = <BudgetAlert>[];
  void check(String key, String name, double used, double limit) {
    if (limit <= 0 || used <= 0) return;
    final share = used / limit;
    final perDay = (limit - used) / left;
    if (share >= 1) {
      out.add(BudgetAlert(key, 2, '$name is over budget',
          '${_m(used)} spent of ${_m(limit)}: ${_m(used - limit)} over, with ${days - day} day${days - day == 1 ? '' : 's'} still to go.',
          share));
    } else if (share >= 0.8) {
      out.add(BudgetAlert(key, 1, '$name at ${(share * 100).floor()}%',
          'Only ${_m(limit - used)} left for $left day${left == 1 ? '' : 's'}: about ${_m(perDay)} a day.', share));
    } else if (day >= 5) {
      final projected = used / day * days;
      if (projected > limit * 1.1) {
        out.add(BudgetAlert(key, 1, '$name is running fast',
            'At this pace about ${_m(projected)} by month end (budget ${_m(limit)}). '
            'Keep to ${_m(perDay)} a day to stay within.',
            share));
      }
    }
  }

  final catBudget = kCats.where((c) => !c.goal).fold<double>(0, (s, c) => s + (b.categories[c.id] ?? 0));
  final personal = b.members.values.fold<double>(0, (s, v) => s + v);
  check('family', 'Family spending', total, catBudget > 0 ? catBudget : personal);
  for (final e in b.members.entries) {
    check('member:${e.key}', '${e.key}\'s spending', byMember[e.key] ?? 0, e.value);
  }
  for (final c in kCats.where((c) => !c.goal)) {
    check('cat:${c.id}', c.label, byCat[c.id] ?? 0, b.categories[c.id] ?? 0);
  }
  out.sort((a, b) => b.level != a.level ? b.level - a.level : b.share.compareTo(a.share));
  return out;
}

Forecast? monthForecast(Budget b, List<Txn> txns, DateTime month, {DateTime? now}) {
  now ??= DateTime.now();
  if (now.year != month.year || now.month != month.month) return null;
  final days = DateTime(month.year, month.month + 1, 0).day;
  final spent = txns.where(_counts).fold<double>(0, (s, t) => s + t.amount);
  final catBudget = kCats.where((c) => !c.goal).fold<double>(0, (s, c) => s + (b.categories[c.id] ?? 0));
  final budget = catBudget > 0 ? catBudget : b.members.values.fold<double>(0, (s, v) => s + v);
  // Too early to extrapolate in the first few days.
  final projected = now.day < 5 ? spent : spent / now.day * days;
  return Forecast(spent, projected, budget, now.day, days);
}

// ---------------------------------------------------------------------------
// Monthly money story
// ---------------------------------------------------------------------------

class StoryLine {
  final IconData icon;
  final String text;
  final int mood; // 1 good, 0 neutral, -1 watch out
  const StoryLine(this.icon, this.text, [this.mood = 0]);
}

List<StoryLine> monthStory({
  required DateTime month,
  required List<Txn> cur,
  required List<Txn> prev,
  double income = 0,
  double prevIncome = 0,
  DateTime? now,
}) {
  now ??= DateTime.now();
  final isCurrent = now.year == month.year && now.month == month.month;
  final prevMonth = DateTime(month.year, month.month - 1);
  final prevName = DateFormat('MMMM').format(prevMonth);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final cutDay = isCurrent ? now.day : days;

  final spends = cur.where(_counts).toList();
  final prevAll = prev.where(_counts).toList();
  // Compare like with like: this month so far vs the same days last month.
  final prevSame = isCurrent ? prevAll.where((t) => t.date.day <= cutDay).toList() : prevAll;

  double sum(Iterable<Txn> l) => l.fold<double>(0, (s, t) => s + t.amount);
  final total = sum(spends);
  final prevTotal = sum(prevSame);
  final lines = <StoryLine>[];

  if (spends.isEmpty) {
    return [StoryLine(Icons.hourglass_empty, isCurrent ? 'No spending recorded yet this month.' : 'No spending recorded this month.')];
  }

  // 1. Total vs last month.
  final when = isCurrent ? 'by this day in $prevName' : 'than in $prevName';
  if (prevTotal > 0) {
    final d = total - prevTotal;
    final pct = (d.abs() / prevTotal * 100).round();
    if (pct < 5) {
      lines.add(StoryLine(Icons.balance, '${isCurrent ? 'Spent so far' : 'Spent'}: ${_m(total)}, about the same as $when.'));
    } else {
      lines.add(StoryLine(d > 0 ? Icons.trending_up : Icons.trending_down,
          '${isCurrent ? 'Spent so far' : 'Spent'}: ${_m(total)}, ${_m(d.abs())} ${d > 0 ? 'more' : 'less'} ($pct%) $when.',
          d > 0 ? -1 : 1));
    }
  } else {
    lines.add(StoryLine(Icons.payments_outlined, '${isCurrent ? 'Spent so far' : 'Spent'}: ${_m(total)} in ${spends.length} payments.'));
  }

  // 2. Biggest category change, and who it went to.
  Map<String, double> byCat(Iterable<Txn> l) {
    final m = <String, double>{};
    for (final t in l) {
      m[t.category] = (m[t.category] ?? 0) + t.amount;
    }
    return m;
  }

  final c1 = byCat(spends), c0 = byCat(prevSame);
  if (prevTotal > 0) {
    String? bestCat;
    var bestDiff = 0.0;
    for (final id in {...c1.keys, ...c0.keys}) {
      if (id == kUncategorised) continue;
      final d = (c1[id] ?? 0) - (c0[id] ?? 0);
      if (d.abs() > bestDiff.abs()) {
        bestDiff = d;
        bestCat = id;
      }
    }
    if (bestCat != null && bestDiff.abs() >= 300) {
      final c = catById(bestCat);
      final before = c0[bestCat] ?? 0;
      final pct = before > 0 ? ' (${bestDiff > 0 ? '+' : '−'}${(bestDiff.abs() / before * 100).round()}%)' : '';
      var text = '${c.label} ${bestDiff > 0 ? 'up' : 'down'} ${_m(bestDiff.abs())}$pct vs $prevName';
      if (bestDiff > 0) {
        final top = _topPayee(spends.where((t) => t.category == bestCat));
        if (top != null) text += ', mostly ${top.$1} (${top.$3} payment${top.$3 == 1 ? '' : 's'}, ${_m(top.$2)})';
      }
      lines.add(StoryLine(c.icon, '$text.', bestDiff > 0 ? -1 : 1));
    }
  }

  // 3. Where most money went.
  final top = _topPayee(spends);
  if (top != null && top.$2 >= total * 0.1) {
    lines.add(StoryLine(Icons.storefront_outlined,
        'Most money went to ${top.$1}: ${_m(top.$2)} in ${top.$3} payment${top.$3 == 1 ? '' : 's'}.'));
  }

  // 4. Income kept.
  if (income > 0) {
    final kept = income - total;
    final rate = (kept / income * 100).round();
    var text = kept >= 0
        ? 'You kept $rate% of this month\'s income (${_m(kept)} of ${_m(income)}).'
        : 'Spending is ${_m(-kept)} more than this month\'s income so far.';
    if (prevIncome > 0 && kept >= 0) {
      final prevRate = ((prevIncome - sum(prevAll)) / prevIncome * 100).round();
      if ((rate - prevRate).abs() >= 3) text += ' ${rate > prevRate ? 'Up' : 'Down'} from $prevRate% in $prevName.';
    }
    lines.add(StoryLine(Icons.savings_outlined, text, kept >= 0 && rate >= 20 ? 1 : (kept < 0 ? -1 : 0)));
  }

  // 5. Weekends.
  final weekend = sum(spends.where((t) => t.date.weekday >= DateTime.saturday));
  if (total > 0 && spends.length >= 8) {
    final share = weekend / total;
    if (share >= 0.45) {
      lines.add(StoryLine(Icons.weekend_outlined,
          '${(share * 100).round()}% of spending happened on weekends, which are only 2 days of 7.', -1));
    } else if (share <= 0.15) {
      lines.add(const StoryLine(Icons.weekend_outlined, 'Quiet weekends: little was spent on Saturdays and Sundays.', 1));
    }
  }

  // 6. Biggest single payment.
  final big = spends.reduce((a, b) => a.amount >= b.amount ? a : b);
  if (spends.length > 1) {
    lines.add(StoryLine(Icons.north_east,
        'Biggest single payment: ${_m(big.amount)} to ${_title(big.payee)} on ${DateFormat('d MMM').format(big.date)} (${big.member}).'));
  }

  // 7. Who spent what.
  final byMember = <String, double>{};
  for (final t in spends) {
    byMember[t.member] = (byMember[t.member] ?? 0) + t.amount;
  }
  if (byMember.length > 1) {
    final parts = (byMember.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '${e.key} ${_m(e.value)}')
        .join(' · ');
    lines.add(StoryLine(Icons.people_outline, 'Split: $parts.'));
  }
  return lines;
}

(String, double, int)? _topPayee(Iterable<Txn> l) {
  final amt = <String, double>{};
  final n = <String, int>{};
  final name = <String, String>{};
  for (final t in l) {
    amt[t.payeeKey] = (amt[t.payeeKey] ?? 0) + t.amount;
    n[t.payeeKey] = (n[t.payeeKey] ?? 0) + 1;
    name[t.payeeKey] = t.payee;
  }
  if (amt.isEmpty) return null;
  final k = amt.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return (_title(name[k]!), amt[k]!, n[k]!);
}

String _title(String s) {
  final t = s.trim();
  if (t.isEmpty) return 'Unknown';
  return t
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

/// Rupees a month still needed to reach [target] by [due]; null if no date.
double? monthlyNeeded(double target, double saved, DateTime? due, {DateTime? now}) {
  if (due == null) return null;
  now ??= DateTime.now();
  final left = target - saved;
  if (left <= 0) return 0;
  final months = (due.year - now.year) * 12 + due.month - now.month;
  return left / (months < 1 ? 1 : months);
}
