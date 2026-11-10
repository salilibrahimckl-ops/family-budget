import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quran_repository.dart';

final quranLoadProvider = FutureProvider<QuranLoadResult>((ref) => QuranRepository.load(rootBundle));

/// The verified repository, or null while loading / when unavailable.
final quranProvider = Provider<QuranRepository?>((ref) {
  final r = ref.watch(quranLoadProvider).valueOrNull;
  return r is QuranReady ? r.repository : null;
});
