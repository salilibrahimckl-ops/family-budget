import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/quran_repository.dart';
import '../memorisation/progress_controller.dart';
import 'section_recite_screen.dart';

/// Madani Mushaf page starts: page n begins at (surah, ayah) = pages[n-1].
final mushafPagesProvider = FutureProvider<List<(int, int)>?>((ref) async {
  try {
    final raw = jsonDecode(await rootBundle.loadString('assets/quran/pages.json')) as List;
    return [for (final p in raw) ((p as List)[0] as int, p[1] as int)];
  } catch (_) {
    return null;
  }
});

/// The parts of a Mushaf page, one per Surah on it: (surah, first Ayah, last Ayah).
List<(int, int, int)> pageParts(QuranRepository q, List<(int, int)> pages, int page) {
  final (s0, a0) = pages[page - 1];
  final (s1, a1) = page < pages.length ? pages[page] : (115, 1);
  final parts = <(int, int, int)>[];
  for (var s = s0; s <= s1 && s <= 114; s++) {
    final from = s == s0 ? a0 : 1;
    final count = q.surahInfo(s).ayahCount;
    final to = s == s1 ? a1 - 1 : count;
    if (to >= from) parts.add((s, from, to));
  }
  return parts;
}

/// "Recite" tab: recite a whole Surah, a Mushaf page or any stretch of Ayahs without
/// stopping; the AI teacher listens to all of it and then shows every correction.
class ReciteHomeScreen extends ConsumerStatefulWidget {
  const ReciteHomeScreen({super.key});

  @override
  ConsumerState<ReciteHomeScreen> createState() => _ReciteHomeScreenState();
}

class _ReciteHomeScreenState extends ConsumerState<ReciteHomeScreen> {
  int _mode = 0; // 0 = Surah, 1 = page
  String _filter = '';
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quran = ref.watch(quranProvider);
    final p = ref.watch(progressProvider).valueOrNull;
    final pages = ref.watch(mushafPagesProvider).valueOrNull;
    if (quran == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final due = p == null ? <int>[] : ref.read(progressProvider.notifier).queue(p, DateTime.now()).revision;
    final sug = p == null || p.memorisedCount == 0 ? null : suggestedSection(quran, p, due);

    void open(int s, int from, int to) => context.push('/recite/$s?from=$from&to=$to');

    final surahs = quran.surahs.where((s) {
      if (_filter.isEmpty) return true;
      final f = _filter.toLowerCase();
      return s.nameTransliterated.toLowerCase().contains(f) || '${s.number}' == f || s.nameArabic.contains(_filter);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.reciteTabTitle)),
      body: ListView(padding: const EdgeInsets.all(HSpace.m), children: [
        Text(l.reciteTabIntro, style: t.bodyMedium),
        const SizedBox(height: HSpace.m),
        if (sug != null)
          Card(
            color: scheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.replay),
              title: Text(l.reciteContinue),
              subtitle: Text('${quran.surahInfo(sug.$1).nameTransliterated} ${sug.$2}–${sug.$3}'),
              trailing: const Icon(Icons.mic),
              onTap: () => open(sug.$1, sug.$2, sug.$3),
            ),
          ),
        const SizedBox(height: HSpace.s),
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, icon: const Icon(Icons.menu_book), label: Text(l.reciteBySurah)),
            ButtonSegment(value: 1, icon: const Icon(Icons.description), label: Text(l.reciteByPage)),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        const SizedBox(height: HSpace.m),
        if (_mode == 0) ...[
          TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l.searchSurah, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => _filter = v.trim()),
          ),
          const SizedBox(height: HSpace.s),
          for (final s in surahs)
            Builder(builder: (context) {
              final ids = quran.surah(s.number).map((a) => a.id);
              final done = p == null ? 0 : ids.where((id) => p.records[id]?.isMemorised ?? false).length;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${s.number}')),
                title: Text(s.nameTransliterated),
                subtitle: Text(l.reciteSurahSub(s.ayahCount, done)),
                trailing: Text(s.nameArabic, style: const TextStyle(fontFamily: HFonts.quran, fontSize: 20)),
                onTap: () => open(s.number, 1, s.ayahCount),
              );
            }),
        ] else if (pages == null) ...[
          Text(l.pagesMissing, style: t.bodySmall),
        ] else ...[
          Row(children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.chevron_left),
              onPressed: _page > 1 ? () => setState(() => _page--) : null,
            ),
            Expanded(
              child: Slider(
                value: _page.toDouble(),
                min: 1,
                max: 604,
                divisions: 603,
                label: '$_page',
                onChanged: (v) => setState(() => _page = v.round()),
              ),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.chevron_right),
              onPressed: _page < 604 ? () => setState(() => _page++) : null,
            ),
          ]),
          Text(l.pageN(_page), style: t.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: HSpace.s),
          for (final (s, from, to) in pageParts(quran, pages, _page))
            Card(
              child: ListTile(
                leading: const Icon(Icons.mic),
                title: Text('${quran.surahInfo(s).nameTransliterated} $from–$to'),
                subtitle: Text(l.ayahCount(to - from + 1)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(s, from, to),
              ),
            ),
          if (pageParts(quran, pages, _page).length > 1)
            Padding(
              padding: const EdgeInsets.only(top: HSpace.s),
              child: Text(l.pageTwoSurahs, style: t.bodySmall),
            ),
        ],
      ]),
    );
  }
}
