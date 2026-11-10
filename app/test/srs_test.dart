import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/features/memorisation/engine/daily_queue.dart';
import 'package:hifz_academy/features/memorisation/engine/srs.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 8);

  MemoRecord mastered() => applyReview(const MemoRecord(ayahId: 1), Grade.good, t0, mastered: true);

  group('applyReview', () {
    test('mastery schedules the first revision for tomorrow', () {
      final r = mastered();
      expect(r.isMemorised, isTrue);
      expect(r.intervalDays, 1);
      expect(r.dueAt, t0.add(const Duration(days: 1)));
      expect(r.status, MemoStatus.recentlyMemorised);
    });

    test('never strong after a single correct answer', () {
      expect(mastered().status, isNot(MemoStatus.strong));
    });

    test('intervals grow with good reviews and reach strong only with history', () {
      var r = mastered();
      var now = t0;
      final statuses = <MemoStatus>[];
      for (var i = 0; i < 6; i++) {
        now = r.dueAt!;
        r = applyReview(r, Grade.good, now);
        statuses.add(r.status);
      }
      expect(r.intervalDays, greaterThan(21));
      expect(r.status, MemoStatus.strong);
      expect(r.successes, greaterThanOrEqualTo(4));
      expect(statuses.first, isNot(MemoStatus.strong));
    });

    test('a lapse resets the streak, lowers ease and marks needs revision', () {
      var r = mastered();
      r = applyReview(r, Grade.good, r.dueAt!);
      final ease = r.ease;
      r = applyReview(r, Grade.again, r.dueAt!);
      expect(r.consecutivePasses, 0);
      expect(r.lapses, 1);
      expect(r.ease, lessThan(ease));
      expect(r.status, MemoStatus.needsRevision);
    });

    test('ease never drops below the minimum', () {
      var r = mastered();
      for (var i = 0; i < 20; i++) {
        r = applyReview(r, Grade.again, t0.add(Duration(days: i)));
      }
      expect(r.ease, greaterThanOrEqualTo(const SrsConfig().minEase));
    });

    test('failed mastery test leaves the Ayah in learning', () {
      final r = applyReview(const MemoRecord(ayahId: 1), Grade.again, t0);
      expect(r.isMemorised, isFalse);
      expect(r.status, MemoStatus.learning);
    });

    test('an Ayah left far past its due date needs revision', () {
      final r = mastered();
      expect(deriveStatus(r, t0.add(const Duration(days: 5))), MemoStatus.needsRevision);
    });

    test('record survives a round trip through the database map', () {
      final r = applyReview(mastered(), Grade.hard, t0.add(const Duration(days: 1)), recallMs: 4000);
      final back = MemoRecord.fromMap(r.toMap());
      expect(back.toMap(), r.toMap());
    });
  });

  group('gradeFromAccuracy', () {
    test('below threshold fails, perfect without hints is good', () {
      expect(gradeFromAccuracy(0.8, masteryThreshold: 0.9), Grade.again);
      expect(gradeFromAccuracy(0.95, masteryThreshold: 0.9), Grade.hard);
      expect(gradeFromAccuracy(1, masteryThreshold: 0.9), Grade.good);
      expect(gradeFromAccuracy(1, masteryThreshold: 0.9, hesitated: true), Grade.hard);
    });
  });

  group('buildDailyQueue', () {
    test('weak Ayahs come before stable ones', () {
      final strongish = MemoRecord(
          ayahId: 10, status: MemoStatus.stable, intervalDays: 10, dueAt: t0, successes: 3, consecutivePasses: 3,
          firstMasteredAt: t0.subtract(const Duration(days: 30)));
      final weak = MemoRecord(
          ayahId: 20, intervalDays: 1, dueAt: t0, successes: 2, failures: 1, lapses: 1, consecutivePasses: 0,
          firstMasteredAt: t0.subtract(const Duration(days: 30)));
      final q = buildDailyQueue([strongish, weak], t0, newPerDay: 3, dailyMinutes: 30);
      expect(q.revision.first, 20);
    });

    test('a large backlog stops new memorisation', () {
      final recs = [
        for (var i = 1; i <= 100; i++)
          MemoRecord(ayahId: i, intervalDays: 2, dueAt: t0.subtract(const Duration(days: 1)), successes: 2,
              consecutivePasses: 1, firstMasteredAt: t0.subtract(const Duration(days: 10))),
      ];
      final q = buildDailyQueue(recs, t0, newPerDay: 3, dailyMinutes: 10);
      expect(q.newAllowance, 0);
      expect(q.throttled, isTrue);
      expect(q.revision.length, lessThanOrEqualTo(10 * 60 ~/ secondsPerReview));
    });

    test('no backlog keeps the full new allowance', () {
      final q = buildDailyQueue(const [], t0, newPerDay: 3, dailyMinutes: 30);
      expect(q.newAllowance, 3);
      expect(q.throttled, isFalse);
    });

    test('learning order starts with Al-Fatiha then Juz Amma from An-Nas', () {
      final o = learningSurahOrder();
      expect(o.take(3), [1, 114, 113]);
      expect(o.length, 114);
      expect(o.toSet().length, 114);
      expect(learningSurahOrder(focusSurahs: [18]).first, 18);
    });
  });
}
