import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Translations are not Quran text: they are human translations of its meaning, shown
/// separately below the verified Arabic and credited to their translators. They are
/// fetched from Tanzil.net by the build (tools/fetch_translations.py) and bundled.
class TranslationInfo {
  const TranslationInfo({required this.id, required this.lang, required this.name, required this.author});
  final String id; // e.g. 'ml.abdulhameed'
  final String lang; // 'en' | 'ml'
  final String name;
  final String author;

  bool get isTransliteration => id == 'en.transliteration';
}

final translationIndexProvider = FutureProvider<List<TranslationInfo>>((ref) async {
  try {
    final raw = await rootBundle.loadString('assets/translations/index.json');
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        TranslationInfo(id: m['id'] as String, lang: m['lang'] as String, name: m['name'] as String, author: m['author'] as String),
    ];
  } catch (_) {
    return const [];
  }
});

/// Rows by global Ayah id - 1. Null if that translation isn't bundled in this build.
final translationProvider = FutureProvider.family<List<String>?, String>((ref, id) async {
  try {
    final raw = await rootBundle.loadString('assets/translations/$id.json', cache: false);
    final rows = ((jsonDecode(raw) as Map<String, dynamic>)['rows'] as List).cast<String>();
    return rows.length == 6236 ? rows : null;
  } catch (_) {
    return null;
  }
});
