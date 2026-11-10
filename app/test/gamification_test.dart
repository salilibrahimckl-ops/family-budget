import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/features/gamification/gamification.dart';

void main() {
  DateTime d(int day) => DateTime(2026, 3, day);

  test('streak counts consecutive learned days', () {
    expect(currentStreak({d(1), d(2), d(3)}, {}, DateTime(2026, 3, 3, 20)), 3);
  });

  test('streak survives until today ends', () {
    expect(currentStreak({d(1), d(2)}, {}, DateTime(2026, 3, 3, 9)), 2);
  });

  test('a missed day breaks the streak unless a freeze covers it', () {
    expect(currentStreak({d(1), d(3)}, {}, DateTime(2026, 3, 3, 20)), 1);
    expect(currentStreak({d(1), d(3)}, {d(2)}, DateTime(2026, 3, 3, 20)), 2);
  });

  test('freezes are earned weekly and capped at two', () {
    expect(freezesAvailable(6, 0), 0);
    expect(freezesAvailable(7, 0), 1);
    expect(freezesAvailable(30, 0), 2);
    expect(freezesAvailable(14, 1), 1);
  });

  test('auto-freeze covers only a gap right before a streak', () {
    expect(daysToFreeze({d(1)}, {}, d(3), 1), [d(2)]);
    expect(daysToFreeze({d(1)}, {}, d(5), 1), isEmpty); // 3-day gap, only 1 token: not worth it
    expect(daysToFreeze({d(2)}, {}, d(3), 1), isEmpty); // nothing missed
  });

  test('revision XP is not given twice a day or for Ayahs not due', () {
    expect(revisionXp(wasDue: true, alreadyRewardedToday: false, wasStrong: false), XpRules.revisionPass);
    expect(revisionXp(wasDue: true, alreadyRewardedToday: true, wasStrong: false), 0);
    expect(revisionXp(wasDue: false, alreadyRewardedToday: false, wasStrong: false), 0);
  });

  test('challenge XP needs at least half correct', () {
    expect(XpRules.challenge(0.4), 0);
    expect(XpRules.challenge(1), 10);
  });

  test('levels follow memorised Ayahs, not XP', () {
    expect(levelFor(0).index, 1);
    expect(levelFor(7).index, 2);
    expect(levelFor(6236).index, 10);
  });

  test('badges unlock from real progress only', () {
    BadgeStatus b(BadgeKind k, List<BadgeStatus> l) => l.firstWhere((x) => x.kind == k);
    final none = evaluateBadges(const BadgeInputs(
        memorised: 0, fatihaDone: false, surahsCompleted: 0, juzAmmaAyahsMemorised: 0, bestStreak: 0, revisions: 0, perfectRecalls: 0));
    expect(none.where((x) => x.unlocked), isEmpty);
    final some = evaluateBadges(const BadgeInputs(
        memorised: 12, fatihaDone: true, surahsCompleted: 2, juzAmmaAyahsMemorised: 6, bestStreak: 7, revisions: 3, perfectRecalls: 0));
    expect(b(BadgeKind.ayahs10, some).unlocked, isTrue);
    expect(b(BadgeKind.ayahs50, some).unlocked, isFalse);
    expect(b(BadgeKind.streak7, some).unlocked, isTrue);
    expect(b(BadgeKind.juzAmma, some).fraction, closeTo(6 / 564, 1e-9));
  });

  test('best streak counts the longest run, freezes keep it but do not add', () {
    expect(bestStreak({d(1), d(2), d(3), d(10), d(11)}, {}), 3);
    expect(bestStreak({d(1), d(3)}, {d(2)}), 2);
    expect(bestStreak({}, {}), 0);
  });

  test('daily progress ring', () {
    expect(dailyProgress(newTarget: 2, newDone: 1, reviseTarget: 2, revisedDone: 2), 0.75);
    expect(dailyProgress(newTarget: 0, newDone: 0, reviseTarget: 0, revisedDone: 0), 1);
  });
}
