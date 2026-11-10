import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/widgets/widgets.dart';
import '../gamification/gamification.dart';
import '../memorisation/progress_controller.dart';
import '../onboarding/onboarding_store.dart';

/// Today tab: what to do now, and honest progress numbers from the device database.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final plan = ref.watch(learningPlanProvider);
    final quran = ref.watch(quranProvider);
    final async = ref.watch(progressProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = async.valueOrNull;

    if (p == null || quran == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final ctrl = ref.read(progressProvider.notifier);
    final q = ctrl.queue(p, now);
    final next = q.newAllowance > 0 && !(plan?.startsWithReading ?? false) ? ctrl.nextNewAyah(p, quran) : null;
    final level = levelFor(p.memorisedCount);
    final missions = todaysMissions(
      newAllowance: q.newAllowance,
      newDoneToday: p.newDoneToday,
      dueCount: q.dueCount,
      revisedToday: p.revisedToday,
      recallTestsToday: p.recallTestsToday,
      hasMemorised: p.memorisedCount > 0,
    );
    final weak = p.weakest(now);

    String missionText(Mission m) => switch (m.kind) {
          MissionKind.memoriseNew => l.missionNew(m.target),
          MissionKind.revise => l.missionRevise(m.target),
          MissionKind.recallTest => l.missionRecall,
        };

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(progressProvider),
          child: ListView(
            padding: const EdgeInsets.all(HSpace.l),
            children: [
              Row(children: [
                Expanded(child: Text(l.dashGreeting, style: t.headlineMedium)),
                Chip(avatar: const Icon(Icons.local_fire_department, size: 18), label: Text(l.dashDays(p.streak(now)))),
              ]),
              Text(l.levelLabel(level.index), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: HSpace.l),

              // What to do now
              if (q.revision.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: HSpace.s),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.replay),
                    label: Text(l.ctaRevise(q.revision.length)),
                    onPressed: () => context.push('/review'),
                  ),
                ),
              if (next != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: HSpace.s),
                  child: q.revision.isEmpty
                      ? FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(l.ctaLearn('${quran.surahInfo(next.surah).nameTransliterated} ${next.surah}:${next.ayah}')),
                          onPressed: () => context.push('/lesson/${next.id}'),
                        )
                      : OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(l.ctaLearn('${quran.surahInfo(next.surah).nameTransliterated} ${next.surah}:${next.ayah}')),
                          onPressed: () => context.push('/lesson/${next.id}'),
                        ),
                ),
              if (plan?.startsWithReading ?? false) _Note(l.planReadingFirst),
              if (q.throttled) _Note(l.revisionThrottled),
              if (q.revision.isEmpty && next == null && p.memorisedCount > 0) _Note(l.dashAllDoneToday),
              const SizedBox(height: HSpace.m),

              Row(children: [
                Expanded(child: StatTile(label: l.dashMemorised, value: '${p.memorisedCount}', icon: Icons.menu_book)),
                const SizedBox(width: HSpace.s),
                Expanded(child: StatTile(label: l.dashRetained, value: '${p.retainedCount(now)}', icon: Icons.verified_outlined)),
                const SizedBox(width: HSpace.s),
                Expanded(child: StatTile(label: l.xpLabel, value: '${p.xpTotal}', icon: Icons.star_outline)),
              ]),
              const SizedBox(height: HSpace.m),

              if (missions.isNotEmpty)
                LearningCard(
                  title: l.missionsTitle,
                  child: Column(children: [
                    for (final m in missions)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: m.complete,
                        onChanged: null,
                        title: Text(missionText(m)),
                        subtitle: Text('${m.done.clamp(0, m.target)} / ${m.target}'),
                      ),
                  ]),
                ),
              const SizedBox(height: HSpace.m),

              if (weak.isNotEmpty)
                LearningCard(
                  title: l.dashWeak,
                  child: Wrap(spacing: HSpace.s, children: [
                    for (final id in weak)
                      ActionChip(
                        label: Text(quran.byId(id).key),
                        onPressed: () => context.push('/challenge/recovery'),
                      ),
                  ]),
                ),
              if (p.memorisedCount == 0) _Note(l.dashNoProgress),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: HSpace.s),
      padding: const EdgeInsets.all(HSpace.m),
      decoration: BoxDecoration(color: s.primaryContainer, borderRadius: const BorderRadius.all(HRadius.m)),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: s.onPrimaryContainer)),
    );
  }
}
