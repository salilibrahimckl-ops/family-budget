import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/quran_repository.dart';
import '../memorisation/progress_controller.dart';
import 'gamification.dart';

/// Badge state for the learner, from their real progress.
List<BadgeStatus> badgesFor(ProgressState p, QuranRepository q) {
  bool surahDone(int s) => q.surah(s).every((a) => p.records[a.id]?.isMemorised ?? false);
  var completed = 0;
  for (final s in q.surahs) {
    if (surahDone(s.number)) completed++;
  }
  var juzAmma = 0;
  for (var s = 78; s <= 114; s++) {
    juzAmma += q.surah(s).where((a) => p.records[a.id]?.isMemorised ?? false).length;
  }
  return evaluateBadges(BadgeInputs(
    memorised: p.memorisedCount,
    fatihaDone: surahDone(1),
    surahsCompleted: completed,
    juzAmmaAyahsMemorised: juzAmma,
    bestStreak: p.bestStreakDays,
    revisions: p.totalRevisions,
    perfectRecalls: p.perfectRecalls,
  ));
}

IconData badgeIcon(BadgeKind k) => switch (k) {
      BadgeKind.firstAyah => Icons.spa,
      BadgeKind.fatiha => Icons.auto_awesome,
      BadgeKind.firstSurah => Icons.menu_book,
      BadgeKind.ayahs10 || BadgeKind.ayahs50 || BadgeKind.ayahs100 || BadgeKind.ayahs500 => Icons.workspace_premium,
      BadgeKind.juzAmma => Icons.emoji_events,
      BadgeKind.fullHifz => Icons.diamond,
      BadgeKind.streak3 || BadgeKind.streak7 || BadgeKind.streak30 => Icons.local_fire_department,
      BadgeKind.revisions25 || BadgeKind.revisions100 => Icons.replay_circle_filled,
      BadgeKind.perfect10 => Icons.verified,
    };

String badgeName(BuildContext context, BadgeKind k) {
  final l = context.l10n;
  return switch (k) {
    BadgeKind.firstAyah => l.badgeFirstAyah,
    BadgeKind.fatiha => l.badgeFatiha,
    BadgeKind.firstSurah => l.badgeFirstSurah,
    BadgeKind.ayahs10 => l.badgeAyahs(10),
    BadgeKind.ayahs50 => l.badgeAyahs(50),
    BadgeKind.ayahs100 => l.badgeAyahs(100),
    BadgeKind.ayahs500 => l.badgeAyahs(500),
    BadgeKind.juzAmma => l.badgeJuzAmma,
    BadgeKind.fullHifz => l.badgeFullHifz,
    BadgeKind.streak3 => l.badgeStreak(3),
    BadgeKind.streak7 => l.badgeStreak(7),
    BadgeKind.streak30 => l.badgeStreak(30),
    BadgeKind.revisions25 => l.badgeRevisions(25),
    BadgeKind.revisions100 => l.badgeRevisions(100),
    BadgeKind.perfect10 => l.badgePerfect(10),
  };
}

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final q = ref.watch(quranProvider);
    final p = ref.watch(progressProvider).valueOrNull;
    if (q == null || p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final badges = badgesFor(p, q);
    final unlocked = badges.where((b) => b.unlocked).length;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.achievements)),
      body: ListView(padding: const EdgeInsets.all(HSpace.m), children: [
        Text(l.badgesUnlocked(unlocked, badges.length), style: t.titleMedium),
        const SizedBox(height: HSpace.m),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: HSpace.m,
          crossAxisSpacing: HSpace.m,
          childAspectRatio: 0.78,
          children: [
            for (final b in badges)
              Column(children: [
                Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: b.fraction,
                      strokeWidth: 5,
                      backgroundColor: scheme.surfaceContainerHigh,
                      color: b.unlocked ? HColors.gold500 : scheme.primary,
                    ),
                  ),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: b.unlocked ? HColors.gold100 : scheme.surfaceContainer,
                    child: Icon(badgeIcon(b.kind), size: 28, color: b.unlocked ? HColors.gold500 : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                ]),
                const SizedBox(height: HSpace.s),
                Text(badgeName(context, b.kind), textAlign: TextAlign.center, maxLines: 2, style: t.labelMedium),
                if (!b.unlocked) Text('${b.progress}/${b.target}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
          ],
        ),
      ]),
    );
  }
}

/// The Quran journey: 30 Juz as a path. Each step fills as its Ayahs are memorised.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final q = ref.watch(quranProvider);
    final p = ref.watch(progressProvider).valueOrNull;
    if (q == null || p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final total = List.filled(31, 0), done = List.filled(31, 0);
    // Per Juz: each Surah in it with (Ayahs in this Juz, memorised of those).
    final parts = List.generate(31, (_) => <int, List<int>>{});
    for (var id = 1; id <= q.ayahCount; id++) {
      final a = q.byId(id);
      final j = (a.juz ?? 1).clamp(1, 30);
      final m = p.records[id]?.isMemorised ?? false;
      total[j]++;
      if (m) done[j]++;
      final e = parts[j].putIfAbsent(a.surah, () => [0, 0]);
      e[0]++;
      if (m) e[1]++;
    }

    void openJuz(int j) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (_, scroll) => ListView(controller: scroll, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(HSpace.l, 0, HSpace.l, HSpace.s),
              child: Text('${l.juzLabel(j)} · ${done[j]}/${total[j]}', style: Theme.of(sheet).textTheme.titleLarge),
            ),
            for (final MapEntry(key: s, value: v) in parts[j].entries)
              ListTile(
                leading: CircleAvatar(child: Text('$s')),
                title: Text(q.surahInfo(s).nameTransliterated),
                subtitle: LinearProgressIndicator(value: v[0] == 0 ? 0 : v[1] / v[0]),
                trailing: Text('${v[1]}/${v[0]}'),
                onTap: () {
                  Navigator.pop(sheet);
                  // The reader lives in the Quran tab, so switch tabs rather than push.
                  context.go('/quran/$s');
                },
              ),
          ]),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    // Juz 30 first: most learners begin with Juz 'Amma.
    final order = [30, for (var j = 1; j <= 29; j++) j];
    return Scaffold(
      appBar: AppBar(title: Text(l.screenJourney)),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: HSpace.l),
        itemCount: order.length,
        itemBuilder: (context, i) {
          final j = order[i];
          final frac = total[j] == 0 ? 0.0 : done[j] / total[j];
          final left = i.isEven;
          final node = GestureDetector(
            onTap: () => openJuz(j),
            child: Column(children: [
              Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    value: frac,
                    strokeWidth: 6,
                    backgroundColor: scheme.surfaceContainerHigh,
                    color: frac >= 1 ? HColors.gold500 : scheme.primary,
                  ),
                ),
                CircleAvatar(
                  radius: 30,
                  backgroundColor: frac >= 1 ? HColors.gold100 : frac > 0 ? scheme.primaryContainer : scheme.surfaceContainer,
                  child: frac >= 1
                      ? const Icon(Icons.star_rounded, color: HColors.gold500, size: 32)
                      : Text('$j', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(l.juzLabel(j), style: t.labelMedium),
              Text('${done[j]}/${total[j]}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: HSpace.s),
            child: Row(
              mainAxisAlignment: left ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [Padding(padding: const EdgeInsets.symmetric(horizontal: 56), child: node)],
            ),
          );
        },
      ),
    );
  }
}
