// MOCK DATA: Latin placeholders (MOCK-...), not Quranic text.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/core/quran/quran_repository.dart';

String h(String s) => sha256.convert(utf8.encode(s)).toString();

(String, String, String) fixture({String? tamperText, String? tamperBasmala}) {
  const a1 = 'MOCK-A MOCK-B ۖ MOCK-C'; // includes a standalone pause mark
  const a2 = 'MOCK-D';
  const bas = 'MOCK-BASMALA';
  final rows = [
    {'id': 1, 's': 1, 'a': 1, 't': tamperText ?? a1, 'h': h(a1), 'j': 1, 'p': 1},
    {'id': 2, 's': 1, 'a': 2, 't': a2, 'h': h(a2), 'j': 1, 'p': 1},
  ];
  final surahs = [
    {'i': 1, 'n': 'M', 't': 'Mock', 'e': 'Mock', 'm': 'makkah', 'c': 2, 'b': tamperBasmala ?? bas, 'bh': h(bas)},
  ];
  final combined = '1:1:${h(a1)}\n1:2:${h(a2)}\nB:1:${h(bas)}\n';
  final manifest = {'ayah_count': 2, 'content_sha256': h(combined)};
  return (jsonEncode(manifest), jsonEncode(rows), jsonEncode(surahs));
}

void main() {
  test('verified text loads unchanged, with words and pause marks separated', () {
    final (m, t, s) = fixture();
    final repo = QuranRepository.verify(m, t, s, requireComplete: false);
    final a = repo.byKey(1, 1)!;
    expect(a.text, 'MOCK-A MOCK-B ۖ MOCK-C');
    expect(a.wordCount, 3); // the pause mark is not a word
    expect(a.word(3), 'MOCK-C');
    expect(a.wordId(3), 1003);
    expect(a.tokens.join(' '), a.text);
    expect(repo.surahInfo(1).bismillah, 'MOCK-BASMALA');
    expect(repo.previousInSurah(repo.byId(2))!.id, 1);
  });

  test('a single changed character is rejected', () {
    final (m, t, s) = fixture(tamperText: 'MOCK-A MOCK-b ۖ MOCK-C');
    expect(() => QuranRepository.verify(m, t, s, requireComplete: false), throwsFormatException);
  });

  test('a changed Basmala is rejected', () {
    final (m, t, s) = fixture(tamperBasmala: 'MOCK-BASMALa');
    expect(() => QuranRepository.verify(m, t, s, requireComplete: false), throwsFormatException);
  });

  test('a partial Quran is rejected in production mode', () {
    final (m, t, s) = fixture();
    expect(() => QuranRepository.verify(m, t, s), throwsFormatException);
  });
}
