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
}
