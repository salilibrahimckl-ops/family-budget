import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/widgets/fun.dart';
import '../../core/widgets/noor.dart';
import '../../core/widgets/widgets.dart';
import '../demo/demo_data.dart';
import '../demo/guide_screen.dart';
import '../gamification/achievements_screens.dart';
import '../gamification/gamification.dart';
import '../memorisation/progress_controller.dart';
import '../onboarding/onboarding_store.dart';
import '../share/share_app.dart';
import '../updates/updates.dart';

/// Today tab: one big "what to do now", the daily goal ring, streak week, level,
/// badges and the journey. Every number comes from the device database.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _tourDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWhatsNew(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plan = ref.watch(learningPlanProvider);
    final quran = ref.watch(quranProvider);
    final p = ref.watch(progressProvider).valueOrNull;
    final update = ref.watch(availableUpdateProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (p == null || quran == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final ctrl = ref.read(progressProvider.notifier);
    final q = ctrl.queue(p, now);
    final next = q.newAllowance > 0 && !(plan?.startsWithReading ?? false) ? ctrl.nextNewAyah(p, quran) : null;
    final level = levelFor(p.memorisedCount);
    final nextLevel = hifzLevels.where((x) => x.minAyahs > p.memorisedCount).firstOrNull;
    final newTarget = q.newAllowance + p.newDoneToday;
    final reviseTarget = q.revision.length + p.revisedToday;
    final ring = dailyProgress(newTarget: newTarget, newDone: p.newDoneToday, reviseTarget: reviseTarget, revisedDone: p.revisedToday);
    final badges = badgesFor(p, quran);
    final streak = p.streak(now);
    final kids = ref.watch(settingsProvider).kidsMode;
    final demo = ref.watch(demoModeProvider);
    final showTourCard = !demo && !_tourDismissed && !(ref.read(sharedPrefsProvider).getBool(guideSeenKey) ?? false);
    final noorLine = ring >= 1
        ? l.noorDone
        : ring > 0
            ? l.noorKeepGoing
            : (p.memorisedCount == 0 ? l.noorHello : l.noorWelcomeBack(streak));

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(progressProvider),
          child: ListView(
            padding: const EdgeInsets.all(HSpace.l),
            children: [
              if (update != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: HSpace.m),
                  child: Material(
                    color: HColors.gold100,
                    borderRadius: const BorderRadius.all(HRadius.m),
                    child: ListTile(
                      leading: const Icon(Icons.system_update, color: HColors.gold500),
                      title: Text(l.updateAvailable(update.version), style: const TextStyle(color: Color(0xFF3A2E17))),
                      trailing: FilledButton(onPressed: () => context.push('/updates'), child: Text(l.update)),
                    ),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.dashGreeting, style: t.headlineMedium),
                    Text(l.levelLabel(level.index), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                const ShareAppButton(),
                _StreakFlame(streak: streak),
              ]),
              const SizedBox(height: HSpace.l),
              if (showTourCard) ...[
                Card(
                  color: scheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(HSpace.m),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Icon(Icons.explore),
                        const SizedBox(width: HSpace.s),
                        Expanded(child: Text(l.tourCardTitle, style: t.titleMedium)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            ref.read(sharedPrefsProvider).setBool(guideSeenKey, true);
                            setState(() => _tourDismissed = true);
                          },
                        ),
                      ]),
                      Text(l.tourCardBody, style: t.bodyMedium),
                      const SizedBox(height: HSpace.s),
                      Row(children: [
                        Expanded(child: FilledButton(onPressed: () => context.push('/guide'), child: Text(l.tourCardTour))),
                        const SizedBox(width: HSpace.s),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => ref.read(demoModeProvider.notifier).state = true,
                            child: Text(l.tourCardDemo),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: HSpace.m),
              ],
              if (kids) ...[
                NoorSays(noorLine),
                const SizedBox(height: HSpace.m),
              ],

              // Daily goal ring + the next action.
              LearningCard(
                child: Column(children: [
                  Row(children: [
                    ProgressRing(
                      value: ring,
                      size: 104,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${(ring * 100).round()}%', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(l.todayGoal, style: t.labelSmall),
                      ]),
                    ),
                    const SizedBox(width: HSpace.m),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _GoalLine(icon: Icons.add_circle, label: l.dashNewAyahs, done: p.newDoneToday, target: newTarget),
                        _GoalLine(icon: Icons.replay_circle_filled, label: l.dashRevision, done: p.revisedToday, target: reviseTarget),
                        if (ring >= 1) Text(l.goalReached, style: t.bodyMedium?.copyWith(color: HColors.gold500, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: HSpace.m),
                  if (q.revision.isNotEmpty)
                    FilledButton.icon(
                      icon: const Icon(Icons.replay),
                      label: Text(l.ctaRevise(q.revision.length)),
                      onPressed: () => context.push('/review'),
                    ),
                  if (next != null) ...[
                    if (q.revision.isNotEmpty) const SizedBox(height: HSpace.s),
                    (q.revision.isEmpty
                        ? FilledButton.icon(
                            icon: const Icon(Icons.auto_stories),
                            label: Text(l.ctaLearn('${quran.surahInfo(next.surah).nameTransliterated} ${next.surah}:${next.ayah}')),
                            onPressed: () => context.push('/lesson/${next.id}'),
                          )
                        : OutlinedButton.icon(
                            icon: const Icon(Icons.auto_stories),
                            label: Text(l.ctaLearn('${quran.surahInfo(next.surah).nameTransliterated} ${next.surah}:${next.ayah}')),
                            onPressed: () => context.push('/lesson/${next.id}'),
                          )),
                  ],
                  if (q.revision.isEmpty && next == null && p.memorisedCount > 0)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.emoji_events),
                      label: Text(l.chDaily),
                      onPressed: () => context.push('/challenge/daily'),
                    ),
                ]),
              ),
              if (plan?.startsWithReading ?? false) _Note(l.planReadingFirst),
              if (q.throttled) _Note(l.revisionThrottled),
              const SizedBox(height: HSpace.m),

              // This week
              LearningCard(
                title: l.thisWeek,
                trailing: Text(l.dashDays(streak), style: t.labelLarge),
                child: WeekDots(learnedDays: p.learnedDays, freezeDays: p.freezeDays),
              ),
              const SizedBox(height: HSpace.m),

              Row(children: [
                Expanded(child: StatTile(label: l.dashMemorised, value: '${p.memorisedCount}', icon: Icons.menu_book)),
                const SizedBox(width: HSpace.s),
                Expanded(child: StatTile(label: l.dashRetained, value: '${p.retainedCount(now)}', icon: Icons.verified_outlined)),
                const SizedBox(width: HSpace.s),
                Expanded(child: StatTile(label: l.xpLabel, value: '${p.xpTotal}', icon: Icons.star_rounded)),
              ]),
              const SizedBox(height: HSpace.m),

              // Level progress
              if (nextLevel != null)
                LearningCard(
                  title: l.nextLevel(nextLevel.index),
                  trailing: Text('${p.memorisedCount}/${nextLevel.minAyahs}', style: t.labelLarge),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(HRadius.pill),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: ((p.memorisedCount - level.minAyahs) / (nextLevel.minAyahs - level.minAyahs)).clamp(0.0, 1.0).toDouble(),
                    ),
                  ),
                ),
              const SizedBox(height: HSpace.m),

              // Badges + journey
              Row(children: [
                Expanded(
                  child: _Tile(
                    icon: Icons.military_tech,
                    title: l.achievements,
                    subtitle: l.badgesUnlocked(badges.where((b) => b.unlocked).length, badges.length),
                    onTap: () => context.push('/achievements'),
                  ),
                ),
                const SizedBox(width: HSpace.s),
                Expanded(
                  child: _Tile(
                    icon: Icons.route,
                    title: l.screenJourney,
                    subtitle: l.journeySub,
                    onTap: () => context.push('/journey'),
                  ),
                ),
              ]),
              const SizedBox(height: HSpace.s),
              Row(children: [
                Expanded(
                  child: _Tile(
                    icon: Icons.auto_awesome,
                    title: l.stickerBook,
                    subtitle: l.stickersCount(p.memorisedCount),
                    onTap: () => context.push('/stickers'),
                  ),
                ),
                const SizedBox(width: HSpace.s),
                Expanded(
                  child: _Tile(
                    icon: Icons.explore,
                    title: l.guideTitle,
                    subtitle: l.guideSub,
                    onTap: () => context.push('/guide'),
                  ),
                ),
              ]),
              if (p.memorisedCount == 0) ...[
                const SizedBox(height: HSpace.m),
                _Note(l.dashNoProgress),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakFlame extends StatelessWidget {
  const _StreakFlame({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (_, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: streak > 0 ? HColors.gold100 : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: const BorderRadius.all(HRadius.pill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.local_fire_department, color: streak > 0 ? HColors.gold500 : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('$streak', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
        ),
      );
}

class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.icon, required this.label, required this.done, required this.target});
  final IconData icon;
  final String label;
  final int done;
  final int target;

  @override
  Widget build(BuildContext context) {
    final complete = target > 0 && done >= target;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(complete ? Icons.check_circle : icon, size: 20, color: complete ? HColors.gold500 : Theme.of(context).colorScheme.primary),
        const SizedBox(width: HSpace.s),
        Expanded(child: Text(label)),
        Text('${done.clamp(0, target)}/$target', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LearningCard(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 32, color: HColors.gold500),
          const SizedBox(height: HSpace.s),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: HSpace.s),
      padding: const EdgeInsets.all(HSpace.m),
      decoration: BoxDecoration(color: s.primaryContainer, borderRadius: const BorderRadius.all(HRadius.m)),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: s.onPrimaryContainer)),
    );
  }
}
