/// Pure Dart: turns onboarding answers into a starting plan. No Flutter imports,
/// so it is unit-tested directly. The full adaptive engine (Phase 6) refines this
/// plan every day from actual performance.
library;

import 'dart:math' as math;

enum ReadingAbility { none, slow, fluent }

enum TajweedKnowledge { none, basic, good }

enum MemorisedAmount { none, few, juzAmma, severalJuz, hafiz }

enum LearningGoal { fromBeginning, selectedSurahs, completeQuran, strengthenHifz, tajweed }

enum Pace { gentle, steady, intensive }

enum LearnerLevel { beginner, intermediate, hafiz }

class OnboardingAnswers {
  const OnboardingAnswers({
    required this.reading,
    required this.tajweed,
    required this.memorised,
    required this.goal,
    required this.dailyMinutes,
    required this.pace,
    required this.uiLanguage,
  });

  final ReadingAbility reading;
  final TajweedKnowledge tajweed;
  final MemorisedAmount memorised;
  final LearningGoal goal;
  final int dailyMinutes; // 10, 20, 30, 45, 60
  final Pace pace;
  final String uiLanguage;

  Map<String, Object> toJson() => {
        'reading': reading.name,
        'tajweed': tajweed.name,
        'memorised': memorised.name,
        'goal': goal.name,
        'dailyMinutes': dailyMinutes,
        'pace': pace.name,
        'uiLanguage': uiLanguage,
      };

  static OnboardingAnswers fromJson(Map<String, dynamic> j) => OnboardingAnswers(
        reading: ReadingAbility.values.byName(j['reading'] as String),
        tajweed: TajweedKnowledge.values.byName(j['tajweed'] as String),
        memorised: MemorisedAmount.values.byName(j['memorised'] as String),
        goal: LearningGoal.values.byName(j['goal'] as String),
        dailyMinutes: j['dailyMinutes'] as int,
        pace: Pace.values.byName(j['pace'] as String),
        uiLanguage: j['uiLanguage'] as String,
      );
}

class LearningPlan {
  const LearningPlan({
    required this.level,
    required this.newAyahsPerDay,
    required this.dailyMinutes,
    required this.revisionShare,
    required this.startsWithReading,
    required this.cappedByTime,
  });

  final LearnerLevel level;
  final int newAyahsPerDay;
  final int dailyMinutes;
  final double revisionShare; // fraction of session time reserved for revision
  final bool startsWithReading; // learner needs Arabic reading before memorising
  final bool cappedByTime; // pace was reduced to fit the daily time
}

const allowedMinutes = [10, 20, 30, 45, 60];

/// Rough minutes one new Ayah needs through all 7 steps for a short-to-medium Ayah.
/// Deliberately conservative; the Phase 6 engine replaces it with measured times.
const minutesPerNewAyah = 4;

LearningPlan buildPlan(OnboardingAnswers a) {
  if (!allowedMinutes.contains(a.dailyMinutes)) {
    throw ArgumentError.value(a.dailyMinutes, 'dailyMinutes', 'must be one of $allowedMinutes');
  }

  final level = switch (a.memorised) {
    MemorisedAmount.hafiz => LearnerLevel.hafiz,
    MemorisedAmount.severalJuz || MemorisedAmount.juzAmma => LearnerLevel.intermediate,
    _ => a.reading == ReadingAbility.fluent && a.tajweed == TajweedKnowledge.good
        ? LearnerLevel.intermediate
        : LearnerLevel.beginner,
  };

  // More existing Hifz means more of each session goes to keeping it.
  var revisionShare = switch (a.memorised) {
    MemorisedAmount.none => 0.3,
    MemorisedAmount.few => 0.4,
    MemorisedAmount.juzAmma => 0.5,
    MemorisedAmount.severalJuz => 0.6,
    MemorisedAmount.hafiz => 0.85,
  };
  if (a.goal == LearningGoal.strengthenHifz) revisionShare = 0.9;
  if (a.goal == LearningGoal.tajweed) revisionShare = math.min(revisionShare + 0.1, 0.9);

  final startsWithReading = a.reading == ReadingAbility.none;

  var desired = switch (a.pace) { Pace.gentle => 1, Pace.steady => 3, Pace.intensive => 5 };
  if (a.goal == LearningGoal.strengthenHifz || a.goal == LearningGoal.tajweed) desired = 0;
  if (a.memorised == MemorisedAmount.hafiz && a.goal != LearningGoal.completeQuran) desired = 0;
  if (startsWithReading) desired = 0; // reading lessons first, memorisation unlocks later

  final newMinutes = a.dailyMinutes * (1 - revisionShare);
  final fits = (newMinutes / minutesPerNewAyah).floor();
  final perDay = math.max(0, math.min(desired, fits));

  return LearningPlan(
    level: level,
    newAyahsPerDay: perDay,
    dailyMinutes: a.dailyMinutes,
    revisionShare: revisionShare,
    startsWithReading: startsWithReading,
    cappedByTime: perDay < desired,
  );
}
