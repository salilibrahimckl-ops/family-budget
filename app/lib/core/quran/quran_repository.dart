import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show AssetBundle;

/// A verified Ayah. The constructor is private: the only way to obtain one is
/// through [QuranRepository], after its SHA-256 has been checked. Widgets that
/// render Quran text accept only this type, never a plain String.
final class VerifiedAyah {
  VerifiedAyah._(this.id, this.surah, this.ayah, this.text, this.juz, this.page)
      : tokens = List.unmodifiable(text.split(' ')) {
    final idx = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (QuranWords.isWord(tokens[i])) idx.add(i);
    }
    wordTokenIndexes = List.unmodifiable(idx);
  }

  final int id;
  final int surah;
  final int ayah;
  final String text;
  final int? juz;
  final int? page;

  /// Space-separated tokens of [text]; joining them with ' ' gives [text] exactly.
  final List<String> tokens;

  /// Token indexes that are words (contain a letter). Pause marks are not words.
  late final List<int> wordTokenIndexes;

  int get wordCount => wordTokenIndexes.length;

  /// Word at 1-based [position] (same numbering as the database `quran.words`).
  String word(int position) => tokens[wordTokenIndexes[position - 1]];

  /// Stable word id, identical to the server: ayahId * 1000 + position.
  int wordId(int position) => id * 1000 + position;

  String get key => '$surah:$ayah';
}

/// Surah metadata plus the verbatim Basmala text Tanzil supplies (null for 1 and 9).
final class VerifiedSurah {
  const VerifiedSurah._(this.number, this.nameArabic, this.nameTransliterated, this.nameEnglish,
      this.revelation, this.ayahCount, this.bismillah);

  final int number;
  final String nameArabic;
  final String nameTransliterated;
  final String nameEnglish;
  final String revelation; // 'makkah' | 'madinah'
  final int ayahCount;
  final String? bismillah;
}

abstract final class QuranWords {
  static final _letter = RegExp(r'\p{L}', unicode: true);

  /// Same rule as the import tool: a token is a word if it contains a letter.
  static bool isWord(String token) => _letter.hasMatch(token);
}

sealed class QuranLoadResult {
  const QuranLoadResult();
}

final class QuranReady extends QuranLoadResult {
  const QuranReady(this.repository);
  final QuranRepository repository;
}

/// No Quran assets in the build.
final class QuranMissing extends QuranLoadResult {
  const QuranMissing();
}

/// Assets exist but failed verification. The app must not show any Quran text.
final class QuranCorrupt extends QuranLoadResult {
  const QuranCorrupt(this.reason);
  final String reason;
}

class QuranRepository {
  QuranRepository._(this._ayahs, this._surahs, this.manifest)
      : _byKey = {for (final a in _ayahs) a.key: a},
        _firstIdOfSurah = {} {
    for (final a in _ayahs) {
      _firstIdOfSurah.putIfAbsent(a.surah, () => a.id);
    }
  }

  final List<VerifiedAyah> _ayahs;
  final List<VerifiedSurah> _surahs;
  final Map<String, VerifiedAyah> _byKey;
  final Map<int, int> _firstIdOfSurah;
  final Map<String, dynamic> manifest;

  int get ayahCount => _ayahs.length;
  List<VerifiedSurah> get surahs => _surahs;
  VerifiedSurah surahInfo(int number) => _surahs[number - 1];
  VerifiedAyah byId(int id) => _ayahs[id - 1];
  VerifiedAyah? byKey(int surah, int ayah) => _byKey['$surah:$ayah'];

  List<VerifiedAyah> surah(int s) {
    final first = _firstIdOfSurah[s];
    if (first == null) return const [];
    return _ayahs.sublist(first - 1, first - 1 + _surahs[s - 1].ayahCount);
  }

  /// The previous Ayah in the same Surah, if any.
  VerifiedAyah? previousInSurah(VerifiedAyah a) => a.ayah > 1 ? byId(a.id - 1) : null;

  static const manifestPath = 'assets/quran/manifest.json';
  static const textPath = 'assets/quran/quran_text.json';
  static const surahsPath = 'assets/quran/surahs.json';

  /// Loads and verifies the bundled Quran text in a background isolate.
  static Future<QuranLoadResult> load(AssetBundle bundle, {bool requireComplete = true}) async {
    final String m, t, s;
    try {
      m = await bundle.loadString(manifestPath);
      t = await bundle.loadString(textPath, cache: false);
      s = await bundle.loadString(surahsPath);
    } catch (_) {
      return const QuranMissing();
    }
    final error = await compute(_check, (m, t, s, requireComplete));
    if (error != null) return QuranCorrupt(error);
    return QuranReady(_build(m, t, s));
  }

  static String? _check((String, String, String, bool) a) {
    try {
      verify(a.$1, a.$2, a.$3, requireComplete: a.$4);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  /// Verifies every Ayah and Basmala hash and the combined content hash against the manifest.
  /// Throws [FormatException] on any mismatch.
  static QuranRepository verify(String manifestRaw, String textRaw, String surahsRaw, {bool requireComplete = true}) {
    final repo = _build(manifestRaw, textRaw, surahsRaw, check: true);
    if (requireComplete && (repo._ayahs.length != 6236 || repo._surahs.length != 114)) {
      throw FormatException('Expected 114 Surahs / 6236 Ayahs, found ${repo._surahs.length} / ${repo._ayahs.length}');
    }
    return repo;
  }

  static String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

  static QuranRepository _build(String manifestRaw, String textRaw, String surahsRaw, {bool check = false}) {
    final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
    final rows = (jsonDecode(textRaw) as List).cast<Map<String, dynamic>>();
    final srows = (jsonDecode(surahsRaw) as List).cast<Map<String, dynamic>>();
    final combined = StringBuffer();
    final ayahs = <VerifiedAyah>[];

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final text = r['t'] as String;
      if (check) {
        if (r['id'] != i + 1) throw FormatException('Ayah ids are not contiguous at position ${i + 1}');
        final actual = _sha(text);
        if (actual != r['h']) throw FormatException('Hash mismatch at ${r['s']}:${r['a']}');
        combined.write('${r['s']}:${r['a']}:$actual\n');
      }
      ayahs.add(VerifiedAyah._(r['id'] as int, r['s'] as int, r['a'] as int, text, r['j'] as int?, r['p'] as int?));
    }

    final surahs = <VerifiedSurah>[];
    for (final s in srows) {
      final b = s['b'] as String?;
      if (check && b != null) {
        final hb = _sha(b);
        if (hb != s['bh']) throw FormatException('Basmala hash mismatch for Surah ${s['i']}');
        combined.write('B:${s['i']}:$hb\n');
      }
      surahs.add(VerifiedSurah._(s['i'] as int, s['n'] as String, s['t'] as String, s['e'] as String,
          s['m'] as String, s['c'] as int, b));
    }

    if (check) {
      if (_sha(combined.toString()) != manifest['content_sha256']) {
        throw const FormatException('Combined content hash does not match the manifest');
      }
      if (ayahs.length != manifest['ayah_count']) throw const FormatException('Ayah count does not match the manifest');
      for (final s in surahs) {
        if (ayahs.where((a) => a.surah == s.number).length != s.ayahCount) {
          throw FormatException('Surah ${s.number} Ayah count mismatch');
        }
      }
    }
    return QuranRepository._(List.unmodifiable(ayahs), List.unmodifiable(surahs), Map.unmodifiable(manifest));
  }
}
