import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/widgets/break_reminder.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/widgets/widgets.dart';
import '../memorisation/engine/srs.dart';
import '../memorisation/progress_controller.dart';
import '../memorisation/widgets/recall_check.dart';
import '../recite/section_recite_screen.dart';

/// Revision queue: what is due today, most urgent first.
class RevisionQueueScreen extends ConsumerWidget {
  const RevisionQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final async = ref.watch(progressProvider);
    final p = async.valueOrNull;
    if (quran == null || p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final now = DateTime.now();
    final q = ref.read(progressProvider.notifier).queue(p, now);
    final t = Theme.of(context).textTheme;

    final sec = suggestedSection(quran, p, q.revision);
    final sectionCard = Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.record_voice_over),
        title: Text(l.sectionCardTitle),
        subtitle: Text(l.sectionCardSub('${quran.surahInfo(sec.$1).nameTransliterated} ${sec.$2}–${sec.$3}')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openSection(context, sec.$1, sec.$2, sec.$3),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.screenRevision)),
      body: q.revision.isEmpty
          ? ListView(padding: const EdgeInsets.all(HSpace.m), children: [
              if (p.memorisedCount > 0) sectionCard,
              Center(
              child: Padding(
                padding: const EdgeInsets.all(HSpace.xl),
                child: Text(p.memorisedCount == 0 ? l.revisionNothingYet : l.revisionAllDone,
                    textAlign: TextAlign.center, style: t.bodyLarge),
              ),
            ),
            ])
          : ListView(padding: const EdgeInsets.all(HSpace.m), children: [
              sectionCard,
              const SizedBox(height: HSpace.m),
              Text(l.revisionDueCount(q.dueCount), style: t.titleMedium),
              if (q.throttled) ...[
                const SizedBox(height: HSpace.s),
                Text(l.revisionThrottled, style: t.bodySmall),
              ],
              const SizedBox(height: HSpace.m),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(l.revisionStart),
                onPressed: () => context.push('/review'),
              ),
              const SizedBox(height: HSpace.m),
              for (final id in q.revision)
                Builder(builder: (_) {
                  final a = quran.byId(id);
                  final s = quran.surahInfo(a.surah);
                  final rec = p.records[id]!;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${s.nameTransliterated} ${a.surah}:${a.ayah}'),
                    subtitle: LinearProgressIndicator(value: rec.strengthAt(now)),
                    trailing: StatusChip(deriveStatus(rec, now)),
                  );
                }),
            ]),
    );
  }
}

/// Goes through today's queue one Ayah at a time.
class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> with BreakReminder {
  List<int>? _items;
  int _i = 0;
  int _xp = 0;
  int _passed = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final p = ref.watch(progressProvider).valueOrNull;
    if (quran == null || p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    _items ??= ref.read(progressProvider.notifier).queue(p, DateTime.now()).revision;
    final items = _items!;
    final t = Theme.of(context).textTheme;

    if (_i >= items.length) {
      return Scaffold(
        appBar: AppBar(title: Text(l.screenRevision)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(HSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandMark(size: 56),
              const SizedBox(height: HSpace.m),
              Text(l.revisionSummary(_passed, items.length), style: t.titleLarge, textAlign: TextAlign.center),
              Text(l.xpEarned(_xp), style: t.bodyLarge),
              const SizedBox(height: HSpace.l),
              FilledButton(onPressed: () => context.go('/today'), child: Text(l.backToToday)),
            ]),
          ),
        ),
      );
    }

    final a = quran.byId(items[_i]);
    final s = quran.surahInfo(a.surah);
    final prev = quran.previousInSurah(a);
    return Scaffold(
      appBar: AppBar(
        title: Text('${_i + 1} / ${items.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: _i / items.length),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(HSpace.l), children: [
        Text('${s.nameTransliterated} ${a.surah}:${a.ayah}', style: t.headlineSmall, textAlign: TextAlign.center),
        if (prev != null)
          Text(l.reviewAfter(prev.ayah), style: t.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: HSpace.m),
        RecallCheck(
          key: ValueKey(a.id),
          ayah: a,
          onDone: (r) async {
            final xp = await ref.read(progressProvider.notifier).record(
                  ayah: a,
                  mode: AttemptMode.revision,
                  accuracy: r.accuracy,
                  missedWordPositions: r.missed,
                  recallMs: r.recallMs,
                  hintsUsed: r.hintsUsed,
                  method: r.method,
                  tajweedWordPositions: r.tajweedWords,
                  quran: quran,
                );
            if (!mounted) return;
            setState(() {
              _xp += xp;
              if (r.accuracy >= defaultMasteryThreshold) _passed++;
              _i++;
            });
          },
        ),
      ]),
    );
  }
}
