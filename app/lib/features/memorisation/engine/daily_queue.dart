/// Builds today's session from memorisation records. Pure Dart.
library;

import 'dart:math' as math;

import 'srs.dart';

class DailyQueue {
  const DailyQueue({required this.revision, required this.dueCount, required this.newAllowance, required this.throttled});

  /// Ayah ids to revise, most urgent first, trimmed to what fits today's time.
  final List<int> revision;
  final int dueCount;
  final int newAllowance;

  /// True when new memorisation was reduced because revision is backed up.
  final bool throttled;
}

/// Seconds one revision recall takes on average (recite, check, grade).
const secondsPerReview = 45;

int _band(MemoStatus s) => switch (s) {
      MemoStatus.needsRevision => 0,
      MemoStatus.recentlyMemorised => 1,
      MemoStatus.learning => 2,
      _ => 3,
    };

DailyQueue buildDailyQueue(
  Iterable<MemoRecord> records,
  DateTime now, {
  required int newPerDay,
  required int dailyMinutes,
  double revisionShare = 0.5,
  int newDoneToday = 0,
  Map<int, int> forgottenWordCounts = const {},
}) {
  final horizon = now.add(const Duration(hours: 12));
  final due = <(MemoRecord, MemoStatus)>[];
  for (final r in records) {
    if (!r.isMemorised && r.successes + r.failures == 0) continue; // never started
    final s = deriveStatus(r, now);
    final isDue = r.dueAt == null || !r.dueAt!.isAfter(horizon) || s == MemoStatus.needsRevision;
    if (isDue) due.add((r, s));
  }

  double overdueDays(MemoRecord r) =>
      r.dueAt == null ? 0 : math.max(0, now.difference(r.dueAt!).inMinutes / 1440);

  due.sort((a, b) {
    final band = _band(a.$2).compareTo(_band(b.$2));
    if (band != 0) return band;
    final forgot = (forgottenWordCounts[b.$1.ayahId] ?? 0).compareTo(forgottenWordCounts[a.$1.ayahId] ?? 0);
    if (forgot != 0) return forgot;
    final od = overdueDays(b.$1).compareTo(overdueDays(a.$1));
    if (od != 0) return od;
    return a.$1.ease.compareTo(b.$1.ease); // harder Ayahs first
  });

  // Revision always gets at least its share; it can take the whole session if backed up.
  final totalCapacity = (dailyMinutes * 60 / secondsPerReview).floor();
  final revisionCapacity = math.max(1, (totalCapacity * revisionShare).floor());

  var allowance = math.max(0, newPerDay - newDoneToday);
  var throttled = false;
  if (due.length > totalCapacity) {
    allowance = 0;
    throttled = true;
  } else if (due.length > revisionCapacity) {
    allowance = allowance ~/ 2;
    throttled = allowance < newPerDay - newDoneToday;
  }

  return DailyQueue(
    revision: [for (final d in due.take(totalCapacity)) d.$1.ayahId],
    dueCount: due.length,
    newAllowance: allowance,
    throttled: throttled,
  );
}

/// Traditional order for learners starting from scratch: Al-Fatiha, then Juz 'Amma from
/// An-Nas backwards, then Al-Baqarah onward. Surahs the learner chose come first.
List<int> learningSurahOrder({List<int> focusSurahs = const []}) {
  final base = <int>[1, for (var s = 114; s >= 78; s--) s, for (var s = 2; s <= 77; s++) s];
  return [...focusSurahs, ...base.where((s) => !focusSurahs.contains(s))];
}
