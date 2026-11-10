/// Compares what the speech recogniser heard with the verified words of an Ayah.
/// Pure Dart, unit-tested.
///
/// This checks WORDS only (missing, wrong, extra, repeated). It does not judge Tajweed
/// or pronunciation. Speech recognisers write ordinary Arabic spelling, so both sides are
/// compared in the Tanzil "simple-clean" spelling with marks removed and letter variants
/// unified. Nothing here produces Quran text: results are positions in the verified Ayah.
library;

import 'dart:math' as math;

/// Removes harakat, Quranic marks and tatweel; unifies alef/hamza/ya/ta-marbuta forms.
String normalizeArabic(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || (r >= 0x06D6 && r <= 0x06ED) || r == 0x0640) continue;
    final c = switch (r) {
      0x0671 || 0x0623 || 0x0625 || 0x0622 || 0x0672 || 0x0673 => 0x0627, // ٱ أ إ آ → ا
      0x0649 => 0x064A, // ى → ي
      0x0629 => 0x0647, // ة → ه
      0x0624 => 0x0648, // ؤ → و
      0x0626 => 0x064A, // ئ → ي
      0x0621 => -1, // standalone hamza dropped
      _ => r,
    };
    if (c >= 0) b.writeCharCode(c);
  }
  return b.toString().trim();
}

List<String> normalizedWords(String s) =>
    s.split(RegExp(r'\s+')).map(normalizeArabic).where((w) => w.isNotEmpty).toList();

int _lev(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Two words count as the same if they are equal, or very close (recognisers often
/// drop or add an alef, e.g. الرحمن / الرحمان), or equal once all alefs are removed.
bool wordsMatch(String expected, String heard) {
  if (expected == heard) return true;
  final ea = expected.replaceAll('ا', ''), ha = heard.replaceAll('ا', '');
  if (ea.isNotEmpty && ea == ha) return true;
  final longer = math.max(expected.length, heard.length);
  if (longer < 3) return false;
  return 1 - _lev(expected, heard) / longer >= (longer >= 6 ? 0.7 : 0.75);
}

enum WordVerdict { correct, missing, wrong }

class RecitationCheck {
  const RecitationCheck({
    required this.verdicts,
    required this.extraWords,
    required this.repeatedWords,
    required this.coverage,
    required this.confident,
    this.heardFor = const [],
  });

  /// For each expected word judged wrong: the word the recogniser heard in its place.
  final List<String?> heardFor;

  /// One verdict per expected word (simple-clean spelling positions).
  final List<WordVerdict> verdicts;

  /// Words heard that are not in the Ayah.
  final int extraWords;

  /// Expected words said more than once in a row.
  final int repeatedWords;

  /// Share of expected words heard correctly (0–1).
  final double coverage;

  /// False when the recogniser heard too little to judge fairly.
  final bool confident;

  double get accuracy => coverage;
  bool get perfect => confident && verdicts.every((v) => v == WordVerdict.correct) && extraWords == 0;
}

/// Aligns heard words with expected words (edit distance on words).
RecitationCheck checkRecitation(List<String> expected, List<String> heard, {double recognizerConfidence = 1}) {
  final n = expected.length, m = heard.length;
  // dp[i][j] = cost of aligning expected[0..i) with heard[0..j)
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final sub = dp[i - 1][j - 1] + (wordsMatch(expected[i - 1], heard[j - 1]) ? 0 : 1);
      dp[i][j] = math.min(sub, math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1));
    }
  }
  final verdicts = List<WordVerdict>.filled(n, WordVerdict.missing);
  final heardFor = List<String?>.filled(n, null);
  var extra = 0, repeated = 0;
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0) {
      final ok = wordsMatch(expected[i - 1], heard[j - 1]);
      if (dp[i][j] == dp[i - 1][j - 1] + (ok ? 0 : 1)) {
        verdicts[i - 1] = ok ? WordVerdict.correct : WordVerdict.wrong;
        if (!ok) heardFor[i - 1] = heard[j - 1];
        i--;
        j--;
        continue;
      }
    }
    if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
      verdicts[i - 1] = WordVerdict.missing;
      i--;
    } else {
      // an extra heard word; a repeat if it matches the expected word just before it
      if (i > 0 && wordsMatch(expected[i - 1], heard[j - 1]) || (i < n && wordsMatch(expected[i], heard[j - 1]))) {
        repeated++;
      } else {
        extra++;
      }
      j--;
    }
  }
  final correct = verdicts.where((v) => v == WordVerdict.correct).length;
  final coverage = n == 0 ? 1.0 : correct / n;
  // Too little heard, or the recogniser itself unsure: don't pretend to judge.
  final heardEnough = m >= math.max(1, (n * 0.4).ceil());
  final confident = heardEnough && (recognizerConfidence < 0 || recognizerConfidence >= 0.3);
  return RecitationCheck(
    verdicts: verdicts,
    extraWords: extra,
    repeatedWords: repeated,
    coverage: coverage,
    confident: confident,
    heardFor: heardFor,
  );
}

/// Maps a position in the simple-clean word list onto the Uthmani word list of the same
/// Ayah (the two spellings occasionally split words differently).
int mapPosition(int simplePos, int simpleCount, int uthmaniCount) {
  if (simpleCount == uthmaniCount) return simplePos;
  return ((simplePos - 0.5) * uthmaniCount / simpleCount).ceil().clamp(1, uthmaniCount);
}
