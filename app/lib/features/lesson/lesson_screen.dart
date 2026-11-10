import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/audio.dart';
import '../../core/design/quran_text.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/widgets/break_reminder.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/widgets/fun.dart';
import '../audio/audio_widgets.dart';
import '../memorisation/progress_controller.dart';
import '../memorisation/widgets/recall_check.dart';

enum LessonStep { listen, understand, repeat, visual, recall, connect, master }

/// The 7-step memorisation lesson for one Ayah.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.ayahId});
  final int ayahId;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> with BreakReminder {
  LessonStep _step = LessonStep.listen;
  int _reads = 0;
  int _round = 1; // visual memory rounds 1..4
  bool _peek = false;
  int _attemptKey = 0; // forces a fresh RecallCheck
  String? _note; // feedback after a failed recall
  int? _xp; // set when mastered
  bool _failedMastery = false;

  static const _targetReads = 5;
  static const _minReads = 3;

  void _go(LessonStep s) => setState(() {
        ref.read(audioProvider.notifier).stop();
        _step = s;
        _attemptKey++;
        _peek = false;
      });

  void _backToPractice(String note) => setState(() {
        _note = note;
        _step = LessonStep.visual;
        _round = 1;
        _attemptKey++;
      });

  /// Words hidden in a visual-memory round: about a quarter more each round, all in round 4.
  Set<int> _hiddenFor(VerifiedAyah a, int round) {
    if (round >= 4) return {for (var i = 1; i <= a.wordCount; i++) i};
    return {
      for (var i = 1; i <= a.wordCount; i++)
        if (((i * 7919 + a.id * 104729) % 4) < round) i,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    if (quran == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final ayah = quran.byId(widget.ayahId);
    final surah = quran.surahInfo(ayah.surah);
    const steps = LessonStep.values;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    switch (_step) {
      case LessonStep.listen:
        final settings = ref.watch(settingsProvider);
        body = _Section(
          title: l.stepListen,
          children: [
            if (ayah.ayah == 1) BasmalaText(surah, size: HQuranSize.min),
            _AyahCard(ayah),
            Text(l.listenHint(reciterById(settings.reciterId).nameEn), textAlign: TextAlign.center, style: t.bodyMedium),
            const SizedBox(height: HSpace.s),
            PlayAyahButton(ayahs: [ayah], repeat: settings.repeatCount, big: true),
            const SizedBox(height: HSpace.s),
            const AudioOptions(),
            const SizedBox(height: HSpace.m),
            FilledButton.tonal(onPressed: () => _go(LessonStep.understand), child: Text(l.continueLabel)),
          ],
        );
      case LessonStep.understand:
        body = _Section(
          title: l.stepUnderstand,
          children: [
            _AyahCard(ayah),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(HSpace.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TranslationsBlock(ayah: ayah),
                  if (ref.watch(settingsProvider).translationIds.isEmpty) Text(l.understandNoTranslation),
                  const SizedBox(height: HSpace.s),
                  ExplanationBlock(ayah: ayah, initiallyExpanded: true),
                ]),
              ),
            ),
            const SizedBox(height: HSpace.s),
            Text(l.ayahFacts(ayah.wordCount, ayah.juz ?? 0, ayah.page ?? 0), textAlign: TextAlign.center, style: t.bodyMedium),
            const SizedBox(height: HSpace.m),
            FilledButton(onPressed: () => _go(LessonStep.repeat), child: Text(l.continueLabel)),
          ],
        );
      case LessonStep.repeat:
        body = _Section(
          title: l.stepRepeat,
          children: [
            _AyahCard(ayah),
            Text(l.repeatCount(_reads, _targetReads), textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: HSpace.s),
            OutlinedButton(onPressed: () => setState(() => _reads++), child: Text(l.repeatReadOnce)),
            const SizedBox(height: HSpace.s),
            FilledButton(onPressed: _reads >= _minReads ? () => _go(LessonStep.visual) : null, child: Text(l.continueLabel)),
          ],
        );
      case LessonStep.visual:
        body = _Section(
          title: l.stepVisual,
          children: [
            if (_note != null) _Info(_note!, warn: true),
            Text(l.visualRound(_round, 4), textAlign: TextAlign.center, style: t.titleSmall),
            _AyahCard(ayah, hidden: _peek ? const {} : _hiddenFor(ayah, _round)),
            OutlinedButton(onPressed: () => setState(() => _peek = !_peek), child: Text(_peek ? l.visualHide : l.visualPeek)),
            const SizedBox(height: HSpace.s),
            FilledButton(
              onPressed: () => _round < 4
                  ? setState(() {
                      _round++;
                      _peek = false;
                    })
                  : _go(LessonStep.recall),
              child: Text(l.continueLabel),
            ),
          ],
        );
      case LessonStep.recall:
        body = _Section(title: l.stepRecall, children: [
          RecallCheck(
            key: ValueKey('recall$_attemptKey'),
            ayah: ayah,
            onDone: (r) => r.accuracy >= defaultMasteryThreshold
                ? _go(LessonStep.connect)
                : _backToPractice(l.recallTryAgain),
          ),
        ]);
      case LessonStep.connect:
        final prev = quran.previousInSurah(ayah);
        body = _Section(title: l.stepConnect, children: [
          if (prev == null) ...[
            _Info(l.connectFirstAyah),
            FilledButton(onPressed: () => _go(LessonStep.master), child: Text(l.continueLabel)),
          ] else ...[
            Text(l.connectPrevious, textAlign: TextAlign.center, style: t.bodyLarge),
            const SizedBox(height: HSpace.s),
            Opacity(opacity: 0.7, child: _AyahCard(prev, size: HQuranSize.min)),
            RecallCheck(
              key: ValueKey('connect$_attemptKey'),
              ayah: ayah,
              prompt: l.connectNow,
              onDone: (r) => r.accuracy >= defaultMasteryThreshold
                  ? _go(LessonStep.master)
                  : _backToPractice(l.recallTryAgain),
            ),
          ],
        ]);
      case LessonStep.master:
        if (_xp != null) {
          body = _Section(title: l.stepMaster, children: [
            Icon(Icons.verified, size: 56, color: scheme.primary),
            Text(l.masteredTitle, textAlign: TextAlign.center, style: t.headlineSmall),
            const SizedBox(height: HSpace.s),
            Text(l.masteredBody(_xp!), textAlign: TextAlign.center),
            const SizedBox(height: HSpace.l),
            FilledButton(onPressed: () => context.go('/today'), child: Text(l.backToToday)),
          ]);
        } else {
          body = _Section(title: l.stepMaster, children: [
            if (_failedMastery) _Info(l.masterNotYet, warn: true),
            RecallCheck(
              key: ValueKey('master$_attemptKey'),
              ayah: ayah,
              allowHint: false,
              prompt: l.masterPrompt,
              onDone: (r) async {
                final xp = await ref.read(progressProvider.notifier).record(
                      ayah: ayah,
                      mode: AttemptMode.lessonMaster,
                      accuracy: r.accuracy,
                      missedWordPositions: r.missed,
                      recallMs: r.recallMs,
                      method: r.method,
                      quran: quran,
                    );
                if (!mounted) return;
                if (r.accuracy >= defaultMasteryThreshold) {
                  setState(() => _xp = xp);
                  await showCelebration(context, title: l.masteredTitle, body: l.masteredCheer, xp: xp);
                } else {
                  _failedMastery = true;
                  _backToPractice(l.masterNotYet);
                }
              },
            ),
          ]);
        }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${surah.nameTransliterated} ${ayah.surah}:${ayah.ayah}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (steps.indexOf(_step) + 1) / steps.length),
        ),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(HSpace.l), children: [
          Text(l.stepOf(steps.indexOf(_step) + 1, steps.length),
              style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: HSpace.s),
          AnimatedSwitcher(duration: HMotion.normal, child: KeyedSubtree(key: ValueKey('$_step$_round$_attemptKey'), child: body)),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: HSpace.m),
        ...children,
      ]);
}

class _AyahCard extends StatelessWidget {
  const _AyahCard(this.ayah, {this.hidden = const {}, this.size = HQuranSize.normal});
  final VerifiedAyah ayah;
  final Set<int> hidden;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: HSpace.m),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(HSpace.m),
            child: QuranText(ayah, hiddenWords: hidden, size: size, showNumber: true),
          ),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info(this.text, {this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: HSpace.m),
      padding: const EdgeInsets.all(HSpace.m),
      decoration: BoxDecoration(
        color: warn ? s.errorContainer : s.surfaceContainer,
        borderRadius: const BorderRadius.all(HRadius.m),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
