import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/quran_text.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/widgets/widgets.dart';
import '../audio/audio_widgets.dart';
import '../memorisation/engine/srs.dart';
import '../memorisation/progress_controller.dart';

/// Surah index with memorisation progress per Surah.
class SurahListScreen extends ConsumerWidget {
  const SurahListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final progress = ref.watch(progressProvider).valueOrNull;
    if (quran == null) return Scaffold(body: Center(child: Text(l.quranMissingTitle)));
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.navQuran)),
      body: ListView.separated(
        itemCount: quran.surahs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = quran.surahs[i];
          final done = progress == null
              ? 0
              : quran.surah(s.number).where((a) => progress.records[a.id]?.isMemorised ?? false).length;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Text('${s.number}', style: t.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
            ),
            title: Text(s.nameTransliterated),
            subtitle: Text(done == 0
                ? l.surahMeta(s.ayahCount, s.revelation == 'makkah' ? l.makki : l.madani)
                : l.surahProgress(done, s.ayahCount)),
            trailing: Text(s.nameArabic,
                textDirection: TextDirection.rtl, style: const TextStyle(fontFamily: HFonts.quran, fontSize: 22)),
            onTap: () => context.push('/quran/${s.number}'),
          );
        },
      ),
    );
  }
}

/// One Surah, Ayah by Ayah, with memorisation status and a "memorise this Surah" action.
class SurahScreen extends ConsumerWidget {
  const SurahScreen({super.key, required this.surah});
  final int surah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final progress = ref.watch(progressProvider).valueOrNull;
    if (quran == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final info = quran.surahInfo(surah);
    final ayahs = quran.surah(surah);
    final now = DateTime.now();
    final firstNotMemorised = ayahs.where((a) => !(progress?.records[a.id]?.isMemorised ?? false)).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text('${info.number}. ${info.nameTransliterated}'),
        actions: [
          IconButton(
            tooltip: l.sectionTitle,
            icon: const Icon(Icons.record_voice_over),
            onPressed: () => context.push('/recite/${info.number}?from=1&to=${info.ayahCount < 10 ? info.ayahCount : 10}'),
          ),
          Padding(padding: const EdgeInsets.only(right: HSpace.s), child: PlayAyahButton(ayahs: ayahs)),
        ],
      ),
      floatingActionButton: firstNotMemorised == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.psychology_alt_outlined),
              label: Text(l.memoriseThisSurah),
              onPressed: () async {
                await ref.read(progressProvider.notifier).setFocusSurah(surah);
                if (context.mounted) context.push('/lesson/${firstNotMemorised.id}');
              },
            ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(HSpace.m, HSpace.m, HSpace.m, 96),
        itemCount: ayahs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: HSpace.m),
              child: Column(children: [
                Text(info.nameArabic,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontFamily: HFonts.quran, fontSize: 34)),
                Text(info.nameEnglish, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: HSpace.s),
                BasmalaText(info),
              ]),
            );
          }
          final a = ayahs[i - 1];
          final rec = progress?.records[a.id];
          final status = rec == null ? MemoStatus.newAyah : deriveStatus(rec, now);
          return Padding(
            padding: const EdgeInsets.only(bottom: HSpace.s),
            child: LearningCard(
              onTap: () => context.push('/lesson/${a.id}'),
              title: '${a.surah}:${a.ayah}',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (status != MemoStatus.newAyah) StatusChip(status),
                const SizedBox(width: HSpace.s),
                PlayAyahButton(ayahs: [a]),
              ]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                QuranText(a, showNumber: true, textAlign: TextAlign.right),
                TranslationsBlock(ayah: a, compact: true),
                ExplanationBlock(ayah: a),
              ]),
            ),
          );
        },
      ),
    );
  }
}
