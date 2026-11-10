/// XP, streaks, levels and missions. Pure Dart.
///
/// XP comes only from learning events the engine confirms. Speed and repetition earn
/// nothing on their own: a second review of the same Ayah on the same day gives no XP.
library;

import 'dart:math' as math;

enum XpReason { newAyah, revisionPass, surahComplete, tajweedLesson, recitationImproved, dailySession, mission, challenge }

extension XpReasonDb on XpReason {
  String get dbName => switch (this) {
        XpReason.newAyah => 'new_ayah',
        XpReason.revisionPass => 'revision_pass',
        XpReason.surahComplete => 'surah_complete',
        XpReason.tajweedLesson => 'tajweed_lesson',
        XpReason.recitationImproved => 'recitation_improved',
        XpReason.dailySession => 'daily_session',
        XpReason.mission => 'mission',
        XpReason.challenge => 'challenge',
      };
}

abstract final class XpRules {
  static const newAyah = 10;
  static const revisionPass = 3;
  static const revisionPassStrong = 1; // keeping strong Ayahs still counts, a little
  static const surahComplete = 50;
  static const tajweedLesson = 15;
  static const dailySession = 5;
  static const missionsAllDone = 20;

  /// Challenge XP scales with accuracy; below 50% earns nothing.
  static int challenge(double accuracy) => accuracy < 0.5 ? 0 : (accuracy * 10).round();
}

/// Revision XP: none if this Ayah already earned revision XP today, or if it was not due.
int revisionXp({required bool wasDue, required bool alreadyRewardedToday, required bool wasStrong}) {
  if (!wasDue || alreadyRewardedToday) return 0;
  return wasStrong ? XpRules.revisionPassStrong : XpRules.revisionPass;
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Consecutive days with learning, counting freeze days as kept. If today has no
/// learning yet, the streak still stands from yesterday (it isn't lost until the day ends).
int currentStreak(Set<DateTime> learnedDays, Set<DateTime> freezeDays, DateTime now) {
  final kept = {...learnedDays.map(dayOf), ...freezeDays.map(dayOf)};
  var d = dayOf(now);
  if (!kept.contains(d)) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (kept.contains(d)) {
    if (learnedDays.map(dayOf).contains(d)) n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// Freeze tokens: one earned per 7 learned days, at most 2 held, minus those used.
int freezesAvailable(int totalLearnedDays, int freezesUsed) =>
    math.max(0, math.min(2, totalLearnedDays ~/ 7 - freezesUsed));

/// Missed days that should be covered by a freeze automatically when the app opens.
/// Only covers a gap directly before the current run, and only up to the tokens available.
List<DateTime> daysToFreeze(Set<DateTime> learnedDays, Set<DateTime> freezeDays, DateTime now, int available) {
  if (available == 0 || learnedDays.isEmpty) return const [];
  final kept = {...learnedDays.map(dayOf), ...freezeDays.map(dayOf)};
  final yesterday = dayOf(now).subtract(const Duration(days: 1));
  final out = <DateTime>[];
  var d = yesterday;
  while (!kept.contains(d) && out.length < available) {
    out.add(d);
    d = DateTime(d.year, d.month, d.day - 1);
  }
  // Only worth freezing if the gap ends at a learned day (a streak to protect).
  return kept.contains(d) ? out : const [];
}

/// Levels reflect memorisation, not XP: thresholds are memorised Ayah counts.
class HifzLevel {
  const HifzLevel(this.index, this.minAyahs);
  final int index; // 1-based
  final int minAyahs;
}

const hifzLevels = [
  HifzLevel(1, 0),
  HifzLevel(2, 7), // Al-Fatiha
  HifzLevel(3, 50),
  HifzLevel(4, 150),
  HifzLevel(5, 564), // about Juz 'Amma
  HifzLevel(6, 1000),
  HifzLevel(7, 2000),
  HifzLevel(8, 3118), // half the Quran
  HifzLevel(9, 5000),
  HifzLevel(10, 6236), // complete Hifz
];

HifzLevel levelFor(int memorisedAyahs) => hifzLevels.lastWhere((l) => memorisedAyahs >= l.minAyahs);

/// Today's missions, sized to the plan. Each has a target and today's progress.
class Mission {
  const Mission(this.kind, this.target, this.done);
  final MissionKind kind;
  final int target;
  final int done;
  bool get complete => done >= target;
}

enum MissionKind { memoriseNew, revise, recallTest }

List<Mission> todaysMissions({
  required int newAllowance,
  required int newDoneToday,
  required int dueCount,
  required int revisedToday,
  required int recallTestsToday,
  required bool hasMemorised,
}) =>
    [
      if (newAllowance + newDoneToday > 0) Mission(MissionKind.memoriseNew, newAllowance + newDoneToday, newDoneToday),
      if (hasMemorised) Mission(MissionKind.revise, math.max(1, math.min(5, dueCount + revisedToday)), revisedToday),
      if (hasMemorised) Mission(MissionKind.recallTest, 1, recallTestsToday),
    ];

/// Badges are earned by real memorisation and consistency, never by opening the app.
enum BadgeKind {
  firstAyah, fatiha, firstSurah, ayahs10, ayahs50, ayahs100, ayahs500, juzAmma, fullHifz,
  streak3, streak7, streak30, revisions25, revisions100, perfect10,
}

class BadgeStatus {
  const BadgeStatus(this.kind, this.progress, this.target);
  final BadgeKind kind;
  final int progress;
  final int target;
  bool get unlocked => progress >= target;
  double get fraction => target == 0 ? 1 : (progress / target).clamp(0, 1).toDouble();
}

class BadgeInputs {
  const BadgeInputs({
    required this.memorised,
    required this.fatihaDone,
    required this.surahsCompleted,
    required this.juzAmmaAyahsMemorised,
    required this.bestStreak,
    required this.revisions,
    required this.perfectRecalls,
  });
  final int memorised;
  final bool fatihaDone;
  final int surahsCompleted;
  final int juzAmmaAyahsMemorised; // out of 564 (Surahs 78–114)
  final int bestStreak;
  final int revisions;
  final int perfectRecalls;
}

List<BadgeStatus> evaluateBadges(BadgeInputs i) => [
      BadgeStatus(BadgeKind.firstAyah, i.memorised, 1),
      BadgeStatus(BadgeKind.fatiha, i.fatihaDone ? 1 : 0, 1),
      BadgeStatus(BadgeKind.firstSurah, i.surahsCompleted, 1),
      BadgeStatus(BadgeKind.ayahs10, i.memorised, 10),
      BadgeStatus(BadgeKind.ayahs50, i.memorised, 50),
      BadgeStatus(BadgeKind.ayahs100, i.memorised, 100),
      BadgeStatus(BadgeKind.ayahs500, i.memorised, 500),
      BadgeStatus(BadgeKind.juzAmma, i.juzAmmaAyahsMemorised, 564),
      BadgeStatus(BadgeKind.fullHifz, i.memorised, 6236),
      BadgeStatus(BadgeKind.streak3, i.bestStreak, 3),
      BadgeStatus(BadgeKind.streak7, i.bestStreak, 7),
      BadgeStatus(BadgeKind.streak30, i.bestStreak, 30),
      BadgeStatus(BadgeKind.revisions25, i.revisions, 25),
      BadgeStatus(BadgeKind.revisions100, i.revisions, 100),
      BadgeStatus(BadgeKind.perfect10, i.perfectRecalls, 10),
    ];

/// Longest run of consecutive kept days (learned or covered by a freeze).
int bestStreak(Set<DateTime> learnedDays, Set<DateTime> freezeDays) {
  final learned = learnedDays.map(dayOf).toSet();
  final kept = {...learned, ...freezeDays.map(dayOf)}.toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in kept) {
    final consecutive = prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d;
    run = consecutive ? run : 0;
    if (learned.contains(d)) run++;
    best = math.max(best, run);
    prev = d;
  }
  return best;
}

/// Share of today's plan that is done, for the daily goal ring (0–1).
double dailyProgress({required int newTarget, required int newDone, required int reviseTarget, required int revisedDone}) {
  final total = newTarget + reviseTarget;
  if (total == 0) return 1;
  return ((math.min(newDone, newTarget) + math.min(revisedDone, reviseTarget)) / total).clamp(0, 1).toDouble();
}
