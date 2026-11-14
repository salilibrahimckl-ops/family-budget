import 'package:flutter_test/flutter_test.dart';
import 'package:family_budget/insights.dart';
import 'package:family_budget/repo.dart';

Txn t(double a, String payee, String cat, String who, DateTime d) =>
    Txn.of(amount: a, payee: payee, category: cat, member: who, date: d);

void main() {
  final month = DateTime(2026, 11);
  final now = DateTime(2026, 11, 14, 12);

  test('alerts: over, near and running fast', () {
    const b = Budget({'food': 5000, 'travel': 3000, 'grocery': 10000}, {'Hiba': 20000});
    final txns = [
      t(5200, 'SWIGGY', 'food', 'Salil', DateTime(2026, 11, 10)),
      t(2500, 'KOCHI METRO', 'travel', 'Hiba', DateTime(2026, 11, 3)),
      t(6000, 'MARKET', 'grocery', 'Hiba', DateTime(2026, 11, 12)),
    ];
    final a = budgetAlerts(b, txns, month, now: now);
    expect(a.first.key, 'cat:food');
    expect(a.first.level, 2);
    expect(a.any((x) => x.key == 'cat:travel' && x.level == 1), isTrue); // 83%
    expect(a.any((x) => x.key == 'cat:grocery' && x.title.contains('running fast')), isTrue); // 60% on day 14
    expect(budgetAlerts(b, txns, DateTime(2026, 10), now: now), isEmpty);
  });

  test('forecast', () {
    const b = Budget({'food': 10000}, {});
    final f = monthForecast(b, [t(2800, 'X', 'food', 'Salil', DateTime(2026, 11, 2))], month, now: now)!;
    expect(f.projected, closeTo(6000, 1));
    expect(f.onTrack, isTrue);
  });

  test('story compares with the same days last month', () {
    final cur = [
      for (var i = 1; i <= 10; i++) t(300, 'SWIGGY', 'food', i.isEven ? 'Salil' : 'Hiba', DateTime(2026, 11, i)),
      t(1000, 'KSRTC', 'travel', 'Salil', DateTime(2026, 11, 5)),
    ];
    final prev = [
      t(1000, 'SWIGGY', 'food', 'Salil', DateTime(2026, 10, 3)),
      t(9000, 'LATE', 'other', 'Salil', DateTime(2026, 10, 28)), // after day 14: not compared
    ];
    final s = monthStory(month: month, cur: cur, prev: prev, income: 50000, now: now);
    final text = s.map((l) => l.text).join('\n');
    expect(text, contains('₹4,000'));
    expect(text, contains('more'));
    expect(text, contains('Food up ₹2,000'));
    expect(text, contains('Swiggy'));
    expect(text, contains('You kept 92%'));
  });

  test('monthly needed for a goal', () {
    expect(monthlyNeeded(120000, 20000, DateTime(2027, 9, 1), now: DateTime(2026, 11, 14)), closeTo(10000, 0.01));
    expect(monthlyNeeded(100, 200, DateTime(2027, 1, 1)), 0);
    expect(monthlyNeeded(100, 0, null), isNull);
  });
}
