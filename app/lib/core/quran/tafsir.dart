import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'translations.dart';

/// Explanations (tafsir) bundled at build time: Al-Mukhtasar from QuranEnc.com.
/// Scholar-written; shown with credit and never edited or generated.
final tafsirIndexProvider = FutureProvider<List<TranslationInfo>>((ref) async {
  try {
    final raw = await rootBundle.loadString('assets/tafsir/index.json');
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        TranslationInfo(id: m['id'] as String, lang: m['lang'] as String, name: m['name'] as String, author: m['author'] as String),
    ];
  } catch (_) {
    return const [];
  }
});

final tafsirProvider = FutureProvider.family<List<String>?, String>((ref, id) async {
  try {
    final raw = await rootBundle.loadString('assets/tafsir/$id.json', cache: false);
    final rows = ((jsonDecode(raw) as Map<String, dynamic>)['rows'] as List).cast<String>();
    return rows.length == 6236 ? rows : null;
  } catch (_) {
    return null;
  }
});

/// Ordinary-spelling Quran text (Tanzil simple-clean), used only to compare against
/// speech recognition. Never displayed.
final simpleCleanProvider = FutureProvider<List<String>?>((ref) async {
  try {
    final rows = (jsonDecode(await rootBundle.loadString('assets/quran/simple_clean.json', cache: false)) as List).cast<String>();
    return rows.length == 6236 ? rows : null;
  } catch (_) {
    return null;
  }
});
