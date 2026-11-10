import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/features/onboarding/learning_plan.dart';

OnboardingAnswers answers({
  ReadingAbility reading = ReadingAbility.fluent,
  TajweedKnowledge tajweed = TajweedKnowledge.basic,
  MemorisedAmount memorised = MemorisedAmount.few,
  Set<LearningGoal> goals = const {LearningGoal.selectedSurahs},
  int minutes = 30,
  Pace pace = Pace.steady,
}) =>
    OnboardingAnswers(
      reading: reading, tajweed: tajweed, memorised: memorised, goals: goals,
      dailyMinutes: minutes, pace: pace, uiLanguage: 'en',
    );

void main() {
  test('steady pace with 30 minutes gives 3 new Ayahs', () {
    final p = buildPlan(answers());
    expect(p.newAyahsPerDay, 3);
    expect(p.cappedByTime, isFalse);
    expect(p.level, LearnerLevel.beginner);
  });

  test('10 minutes caps intensive pace and says so', () {
    final p = buildPlan(answers(minutes: 10, pace: Pace.intensive));
    expect(p.newAyahsPerDay, lessThan(5));
    expect(p.cappedByTime, isTrue);
  });

  test('learner who cannot read starts with reading, no memorisation yet', () {
    final p = buildPlan(answers(reading: ReadingAbility.none, memorised: MemorisedAmount.none));
    expect(p.startsWithReading, isTrue);
    expect(p.newAyahsPerDay, 0);
  });

  test('strengthen-Hifz goal is revision only', () {
    final p = buildPlan(answers(goals: {LearningGoal.strengthenHifz}, memorised: MemorisedAmount.severalJuz));
    expect(p.newAyahsPerDay, 0);
    expect(p.revisionShare, greaterThanOrEqualTo(0.9));
  });

  test('Hafiz is classified as Hafiz with heavy revision', () {
    final p = buildPlan(answers(memorised: MemorisedAmount.hafiz, goals: {LearningGoal.strengthenHifz}));
    expect(p.level, LearnerLevel.hafiz);
  });

  test('more existing Hifz never lowers the revision share', () {
    double share(MemorisedAmount m) => buildPlan(answers(memorised: m, goals: {LearningGoal.completeQuran})).revisionShare;
    final shares = MemorisedAmount.values.map(share).toList();
    for (var i = 1; i < shares.length; i++) {
      expect(shares[i], greaterThanOrEqualTo(shares[i - 1]));
    }
  });

  test('only 10/20/30/45/60 minute plans are accepted', () {
    expect(() => buildPlan(answers(minutes: 25)), throwsArgumentError);
  });

  test('several goals blend: new memorisation plus strengthening keeps new Ayahs', () {
    final p = buildPlan(answers(goals: {LearningGoal.selectedSurahs, LearningGoal.strengthenHifz}));
    expect(p.newAyahsPerDay, greaterThan(0));
    expect(p.revisionShare, greaterThanOrEqualTo(0.6));
  });

  test('older saved answers with a single goal still load', () {
    final j = answers().toJson()..remove('goals');
    j['goal'] = 'tajweed';
    expect(OnboardingAnswers.fromJson(j).goals, {LearningGoal.tajweed});
  });

  test('answers round-trip through JSON', () {
    final a = answers(goals: {LearningGoal.tajweed, LearningGoal.selectedSurahs}, pace: Pace.gentle);
    final b = OnboardingAnswers.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });
}
