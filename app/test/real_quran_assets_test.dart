// Verifies the REAL bundled Quran text (assets/quran) exactly as the app does at startup.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/core/quran/quran_repository.dart';

void main() {
  test('bundled Tanzil text passes full verification', () {
    final repo = QuranRepository.verify(
      File('assets/quran/manifest.json').readAsStringSync(),
      File('assets/quran/quran_text.json').readAsStringSync(),
      File('assets/quran/surahs.json').readAsStringSync(),
    );
    expect(repo.ayahCount, 6236);
    expect(repo.surahs.length, 114);
    expect(repo.surah(2).length, 286);
    expect(repo.byKey(78, 1)!.juz, 30);
    expect(repo.surahInfo(1).bismillah, isNull); // Al-Fatiha: the Basmala is Ayah 1
    expect(repo.surahInfo(9).bismillah, isNull); // At-Tawbah has none
    final words = [for (var i = 1; i <= 6236; i++) repo.byId(i).wordCount].reduce((a, b) => a + b);
    expect(words, repo.manifest['word_count']);
  });
}
