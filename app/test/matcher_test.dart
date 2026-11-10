// Tests use short Arabic phrases from Al-Fatiha in ordinary spelling, as a speech
// recogniser would write them. They exercise the matcher only; no text here is shown in the app.
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/features/recite/matcher.dart';

void main() {
  test('normalisation removes harakat and unifies letter forms', () {
    expect(normalizeArabic('ٱلْحَمْدُ'), 'الحمد');
    expect(normalizeArabic('رَحْمَةٌ'), 'رحمه');
    expect(normalizeArabic('إِيَّاكَ'), 'اياك');
  });

  test('close spellings still match', () {
    expect(wordsMatch('الرحمن', 'الرحمان'), isTrue);
    expect(wordsMatch('العالمين', 'العلمين'), isTrue);
    expect(wordsMatch('الحمد', 'الدين'), isFalse);
  });

  final expected = normalizedWords('الحمد لله رب العالمين');

  test('a perfect recitation', () {
    final r = checkRecitation(expected, normalizedWords('الحمد لله رب العالمين'));
    expect(r.perfect, isTrue);
    expect(r.accuracy, 1);
  });

  test('a missing word is found in the right place', () {
    final r = checkRecitation(expected, normalizedWords('الحمد لله العالمين'));
    expect(r.verdicts, [WordVerdict.correct, WordVerdict.correct, WordVerdict.missing, WordVerdict.correct]);
    expect(r.accuracy, 0.75);
  });

  test('a substituted word is marked wrong, with what was heard', () {
    final r = checkRecitation(expected, normalizedWords('الحمد لله رب الناس'));
    expect(r.verdicts.last, WordVerdict.wrong);
    expect(r.heardFor.last, 'الناس');
  });

  test('a repeated word is counted as a repeat, not a mistake in the Ayah', () {
    final r = checkRecitation(expected, normalizedWords('الحمد لله لله رب العالمين'));
    expect(r.verdicts.every((v) => v == WordVerdict.correct), isTrue);
    expect(r.repeatedWords, 1);
  });

  test('hearing almost nothing is not judged', () {
    final r = checkRecitation(expected, normalizedWords('الحمد'));
    expect(r.confident, isFalse);
  });

  test('position mapping between spellings', () {
    expect(mapPosition(3, 5, 5), 3);
    expect(mapPosition(1, 4, 3), 1);
    expect(mapPosition(4, 4, 3), 3);
  });
}
