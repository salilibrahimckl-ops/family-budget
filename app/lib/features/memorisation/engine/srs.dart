/// Spaced-repetition engine for Quran memorisation. Pure Dart: no Flutter, no I/O.
///
/// Each Ayah is tracked independently. A review is graded again / hard / good / easy;
/// intervals grow with ease and shrink after a lapse. An Ayah is never "strong" after
/// one correct answer: strong requires ≥4 successes, ≥3 consecutive passes and an
/// interval of 21 days or more (mirrored by a database constraint).
library;

import 'dart:math' as math;

enum Grade { again, hard, good, easy }

enum MemoStatus { newAyah, learning, recentlyMemorised, stable, strong, needsRevision }

extension MemoStatusDb on MemoStatus {
  /// Matches the Postgres enum `memo_status`.
  String get dbName => switch (this) {
        MemoStatus.newAyah => 'new',
        MemoStatus.learning => 'learning',
        MemoStatus.recentlyMemorised => 'recently_memorised',
        MemoStatus.stable => 'stable',
        MemoStatus.strong => 'strong',
        MemoStatus.needsRevision => 'needs_revision',
      };
}

class SrsConfig {
  const SrsConfig({
    this.relearnDelay = const Duration(minutes: 10),
    this.minEase = 1.3,
    this.maxEase = 3.5,
    this.startEase = 2.5,
    this.hardFactor = 1.2,
    this.easyBonus = 1.3,
    this.maxIntervalDays = 365,
    this.recentWindow = const Duration(days: 7),
  });

  final Duration relearnDelay;
  final double minEase;
  final double maxEase;
  final double startEase;
  final double hardFactor;
  final double easyBonus;
  final double maxIntervalDays;
  final Duration recentWindow;
}

class MemoRecord {
  const MemoRecord({
    required this.ayahId,
    this.status = MemoStatus.newAyah,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.dueAt,
    this.successes = 0,
    this.failures = 0,
    this.lapses = 0,
    this.consecutivePasses = 0,
    this.avgRecallMs,
    this.firstMasteredAt,
    this.lastReviewedAt,
    this.userDifficulty,
  });

  final int ayahId;
  final MemoStatus status;
  final double ease;
  final double intervalDays;
  final DateTime? dueAt;
  final int successes;
  final int failures;
  final int lapses;
  final int consecutivePasses;
  final int? avgRecallMs;
  final DateTime? firstMasteredAt;
  final DateTime? lastReviewedAt;
  final int? userDifficulty; // 1–5, user-reported

  bool get isMemorised => firstMasteredAt != null;

  /// 0–1. A display estimate of how firmly the Ayah is held.
  double strengthAt(DateTime now) {
    if (!isMemorised) return 0;
    final streak = math.min(consecutivePasses, 5) / 5;
    final span = math.min(intervalDays, 60) / 60;
    var s = 0.5 * streak + 0.5 * span;
    if (dueAt != null && now.isAfter(dueAt!)) {
      final overdueDays = now.difference(dueAt!).inHours / 24;
      s *= math.max(0.3, 1 - overdueDays / math.max(intervalDays, 1) / 2);
    }
    return s.clamp(0, 1).toDouble();
  }

  MemoRecord copyWith({
    MemoStatus? status,
    double? ease,
    double? intervalDays,
    DateTime? dueAt,
    int? successes,
    int? failures,
    int? lapses,
    int? consecutivePasses,
    int? avgRecallMs,
    DateTime? firstMasteredAt,
    DateTime? lastReviewedAt,
    int? userDifficulty,
  }) =>
      MemoRecord(
        ayahId: ayahId,
        status: status ?? this.status,
        ease: ease ?? this.ease,
        intervalDays: intervalDays ?? this.intervalDays,
        dueAt: dueAt ?? this.dueAt,
        successes: successes ?? this.successes,
        failures: failures ?? this.failures,
        lapses: lapses ?? this.lapses,
        consecutivePasses: consecutivePasses ?? this.consecutivePasses,
        avgRecallMs: avgRecallMs ?? this.avgRecallMs,
        firstMasteredAt: firstMasteredAt ?? this.firstMasteredAt,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
        userDifficulty: userDifficulty ?? this.userDifficulty,
      );

  Map<String, Object?> toMap() => {
        'ayah_id': ayahId,
        'status': status.name,
        'ease': ease,
        'interval_days': intervalDays,
        'due_at': dueAt?.toUtc().toIso8601String(),
        'successes': successes,
        'failures': failures,
        'lapses': lapses,
        'consecutive_passes': consecutivePasses,
        'avg_recall_ms': avgRecallMs,
        'first_mastered_at': firstMasteredAt?.toUtc().toIso8601String(),
        'last_reviewed_at': lastReviewedAt?.toUtc().toIso8601String(),
        'user_difficulty': userDifficulty,
      };

  static MemoRecord fromMap(Map<String, Object?> m) {
    DateTime? t(Object? v) => v == null ? null : DateTime.parse(v as String);
    return MemoRecord(
      ayahId: m['ayah_id'] as int,
      status: MemoStatus.values.byName(m['status'] as String),
      ease: (m['ease'] as num).toDouble(),
      intervalDays: (m['interval_days'] as num).toDouble(),
      dueAt: t(m['due_at']),
      successes: m['successes'] as int,
      failures: m['failures'] as int,
      lapses: m['lapses'] as int,
      consecutivePasses: m['consecutive_passes'] as int,
      avgRecallMs: m['avg_recall_ms'] as int?,
      firstMasteredAt: t(m['first_mastered_at']),
      lastReviewedAt: t(m['last_reviewed_at']),
      userDifficulty: m['user_difficulty'] as int?,
    );
  }
}

/// Status from the record's history. Called after every review and when the queue is built,
/// so an Ayah left too long moves to "needs revision" without a review.
MemoStatus deriveStatus(MemoRecord r, DateTime now, [SrsConfig c = const SrsConfig()]) {
  if (!r.isMemorised) return (r.successes + r.failures == 0) ? MemoStatus.newAyah : MemoStatus.learning;
  if (r.consecutivePasses == 0) return MemoStatus.needsRevision; // last review failed
  if (r.dueAt != null) {
    final grace = Duration(hours: (math.max(1.0, r.intervalDays * 0.5) * 24).round());
    if (now.isAfter(r.dueAt!.add(grace))) return MemoStatus.needsRevision;
  }
  if (r.successes >= 4 && r.consecutivePasses >= 3 && r.intervalDays >= 21) return MemoStatus.strong;
  if (now.difference(r.firstMasteredAt!) < c.recentWindow) return MemoStatus.recentlyMemorised;
  if (r.intervalDays >= 7 && r.consecutivePasses >= 2) return MemoStatus.stable;
  return MemoStatus.recentlyMemorised;
}

/// Applies one graded recall to a record.
/// [mastered] is true when this review is the lesson's final mastery test that passed.
MemoRecord applyReview(
  MemoRecord r,
  Grade g,
  DateTime now, {
  int? recallMs,
  bool mastered = false,
  SrsConfig c = const SrsConfig(),
}) {
  final avg = recallMs == null
      ? r.avgRecallMs
      : (r.avgRecallMs == null ? recallMs : ((r.avgRecallMs! * 3 + recallMs) / 4).round());

  if (g == Grade.again) {
    final next = r.copyWith(
      failures: r.failures + 1,
      consecutivePasses: 0,
      lapses: r.isMemorised ? r.lapses + 1 : r.lapses,
      ease: math.max(c.minEase, r.ease - 0.2),
      intervalDays: 0,
      dueAt: now.add(c.relearnDelay),
      lastReviewedAt: now,
      avgRecallMs: avg,
    );
    return next.copyWith(status: deriveStatus(next, now, c));
  }

  // A pass. Before mastery, passes only move the Ayah through "learning".
  final becomesMastered = r.isMemorised || mastered;
  final prev = r.intervalDays;
  double interval;
  var ease = r.ease;
  if (!becomesMastered) {
    interval = 0;
  } else if (prev < 1) {
    interval = switch (g) { Grade.easy => 3, _ => 1 };
  } else {
    interval = switch (g) {
      Grade.hard => math.max(prev * c.hardFactor, prev + 1),
      Grade.good => math.max(prev * ease, prev + 1),
      Grade.easy => math.max(prev * ease * c.easyBonus, prev + 2),
      Grade.again => 0, // handled above
    };
  }
  ease = switch (g) {
    Grade.hard => ease - 0.15,
    Grade.easy => ease + 0.15,
    _ => ease,
  };
  ease = ease.clamp(c.minEase, c.maxEase).toDouble();
  interval = math.min(interval, c.maxIntervalDays);

  final next = r.copyWith(
    successes: r.successes + 1,
    consecutivePasses: r.consecutivePasses + 1,
    ease: ease,
    intervalDays: interval,
    dueAt: becomesMastered ? now.add(Duration(minutes: (interval * 24 * 60).round())) : now.add(c.relearnDelay),
    firstMasteredAt: r.firstMasteredAt ?? (mastered ? now : null),
    lastReviewedAt: now,
    avgRecallMs: avg,
  );
  return next.copyWith(status: deriveStatus(next, now, c));
}

/// Converts a self-checked recall (words missed out of total) into a grade.
Grade gradeFromAccuracy(double accuracy, {required double masteryThreshold, bool hesitated = false}) {
  if (accuracy < masteryThreshold) return Grade.again;
  if (accuracy < 1.0 || hesitated) return Grade.hard;
  return Grade.good;
}
