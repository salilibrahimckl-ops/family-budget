import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/quran_text.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/widgets/widgets.dart';
import '../memorisation/progress_controller.dart';
import '../memorisation/widgets/recall_check.dart';

enum ChallengeKind { missingWords, completeAyah, continueReciting, randomSurah, connect, fullSurah, daily, recovery }

/// Challenge hub. Every challenge is personal: no public ranking.
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = ref.watch(progressProvider).valueOrNull;
    final quran = ref.watch(quranProvider);
    final t = Theme.of(context).textTheme;
    final hasMemorised = (p?.memorisedCount ?? 0) > 0;
    final hasFullSurah = p != null &&
        quran != null &&
        quran.surahs.any((s) => quran.surah(s.number).every((a) => p.records[a.id]?.isMemorised ?? false));

    final items = <(ChallengeKind, String, String, IconData, String?)>[
      (ChallengeKind.daily, l.chDaily, l.chDailyDesc, Icons.today, null),
      (ChallengeKind.missingWords, l.chMissing, l.chMissingDesc, Icons.short_text, null),
      (ChallengeKind.completeAyah, l.chComplete, l.chCompleteDesc, Icons.read_more, null),
      (ChallengeKind.randomSurah, l.chRandom, l.chRandomDesc, Icons.shuffle, null),
      (ChallengeKind.connect, l.chConnect, l.chConnectDesc, Icons.link, null),
      (ChallengeKind.recovery, l.chRecovery, l.chRecoveryDesc, Icons.healing, null),
      (ChallengeKind.fullSurah, l.chFullSurah, l.chFullSurahDesc, Icons.menu_book, hasFullSurah ? null : l.chNeedsFullSurah),
      (ChallengeKind.continueReciting, l.chContinue, l.chContinueDesc, Icons.graphic_eq, l.chNeedsAudio),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.screenChallenges)),
      body: ListView(padding: const EdgeInsets.all(HSpace.m), children: [
        if (!hasMemorised)
          Padding(
            padding: const EdgeInsets.only(bottom: HSpace.m),
            child: Text(l.chLocked, style: t.bodyLarge),
          ),
        for (final (kind, title, desc, icon, blocked) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: HSpace.s),
            child: LearningCard(
              onTap: (!hasMemorised || blocked != null) ? null : () => context.push('/challenge/${kind.name}'),
              child: Row(children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: HSpace.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.titleMedium),
                    Text(blocked ?? desc, style: t.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// A round inside a challenge session.
sealed class _Round {
  const _Round(this.ayah);
  final VerifiedAyah ayah;
}

class _RecallRound extends _Round {
  const _RecallRound(super.ayah, {this.visible = const {}, this.anchor, this.prompt});
  final Set<int> visible;
  final VerifiedAyah? anchor; // shown above (connect challenge)
  final String? prompt;
}

class _ChoiceRound extends _Round {
  const _ChoiceRound(super.ayah, {required this.hiddenPos, required this.options});
  final int hiddenPos;
  final List<String> options;
}

class _SurahGuessRound extends _Round {
  const _SurahGuessRound(super.ayah, {required this.options});
  final List<int> options; // surah numbers
}

class ChallengeSessionScreen extends ConsumerStatefulWidget {
  const ChallengeSessionScreen({super.key, required this.kind});
  final ChallengeKind kind;

  @override
  ConsumerState<ChallengeSessionScreen> createState() => _ChallengeSessionScreenState();
}

class _ChallengeSessionScreenState extends ConsumerState<ChallengeSessionScreen> {
  final _rng = Random();
  List<_Round>? _rounds;
  int _i = 0;
  final _scores = <double>[];
  int _xp = 0;
  String? _choiceFeedback;
  bool? _surahCorrect;

  AttemptMode get _mode => switch (widget.kind) {
        ChallengeKind.missingWords => AttemptMode.missingWords,
        ChallengeKind.completeAyah => AttemptMode.completeAyah,
        ChallengeKind.randomSurah => AttemptMode.randomSurah,
        ChallengeKind.connect => AttemptMode.connect,
        ChallengeKind.recovery => AttemptMode.recovery,
        _ => AttemptMode.completeAyah,
      };

  List<_Round> _build(QuranRepository q, ProgressState p) {
    final mem = [for (final r in p.memorised) q.byId(r.ayahId)];
    if (mem.isEmpty) return const [];
    VerifiedAyah pick() => mem[_rng.nextInt(mem.length)];
    final l = context.l10n;

    _Round missing() {
      final candidates = mem.where((a) => a.wordCount >= 3).toList();
      final a = candidates.isEmpty ? pick() : candidates[_rng.nextInt(candidates.length)];
      final pos = 1 + _rng.nextInt(a.wordCount);
      final correct = a.word(pos);
      final pool = <String>{for (final b in mem) for (var i = 1; i <= b.wordCount; i++) b.word(i)}..remove(correct);
      final others = pool.toList()..shuffle(_rng);
      return _ChoiceRound(a, hiddenPos: pos, options: ([correct, ...others.take(3)]..shuffle(_rng)));
    }

    _Round complete() {
      final a = pick();
      final shown = max(1, (a.wordCount * 0.4).floor());
      return _RecallRound(a, visible: {for (var i = 1; i <= shown; i++) i}, prompt: l.chCompletePrompt);
    }

    _Round random() {
      final a = pick();
      final surahs = {a.surah};
      final memSurahs = {for (final b in mem) b.surah}.toList()..shuffle(_rng);
      surahs.addAll(memSurahs.take(3));
      while (surahs.length < 4) {
        surahs.add(1 + _rng.nextInt(114));
      }
      return _SurahGuessRound(a, options: surahs.toList()..shuffle(_rng));
    }

    _Round? connect() {
      final pairs = mem.where((a) => a.ayah < q.surahInfo(a.surah).ayahCount && (p.records[a.id + 1]?.isMemorised ?? false)).toList();
      if (pairs.isEmpty) return null;
      final a = pairs[_rng.nextInt(pairs.length)];
      return _RecallRound(q.byId(a.id + 1), anchor: a, prompt: l.chConnectPrompt);
    }

    switch (widget.kind) {
      case ChallengeKind.missingWords:
        return List.generate(5, (_) => missing());
      case ChallengeKind.completeAyah:
        return List.generate(5, (_) => complete());
      case ChallengeKind.randomSurah:
        return List.generate(3, (_) => random());
      case ChallengeKind.connect:
        return [for (var k = 0; k < 4; k++) connect()].whereType<_Round>().toList();
      case ChallengeKind.recovery:
        final weak = p.weakest(DateTime.now(), limit: 3);
        final ids = weak.isNotEmpty ? weak : [pick().id];
        return [for (final id in ids) _RecallRound(q.byId(id), prompt: l.chRecoveryPrompt)];
      case ChallengeKind.fullSurah:
        final full = q.surahs.where((s) => q.surah(s.number).every((a) => p.records[a.id]?.isMemorised ?? false)).toList();
        final s = full[_rng.nextInt(full.length)];
        return [for (final a in q.surah(s.number)) _RecallRound(a)];
      case ChallengeKind.daily:
        return [missing(), complete(), random(), connect() ?? complete(), missing()];
      case ChallengeKind.continueReciting:
        return const [];
    }
  }

  Future<void> _finishRound(VerifiedAyah a, double accuracy, Set<int> missed, {int? recallMs, int hints = 0}) async {
    final quran = ref.read(quranProvider)!;
    final xp = await ref.read(progressProvider.notifier).record(
          ayah: a,
          mode: _mode,
          accuracy: accuracy,
          missedWordPositions: missed,
          recallMs: recallMs,
          hintsUsed: hints,
          quran: quran,
        );
    if (!mounted) return;
    setState(() {
      _xp += xp;
      _scores.add(accuracy);
      _i++;
      _choiceFeedback = null;
      _surahCorrect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final p = ref.watch(progressProvider).valueOrNull;
    if (quran == null || p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    _rounds ??= _build(quran, p);
    final rounds = _rounds!;
    final t = Theme.of(context).textTheme;

    if (rounds.isEmpty || _i >= rounds.length) {
      final score = _scores.isEmpty ? 0 : (_scores.reduce((a, b) => a + b) / _scores.length * 100).round();
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(HSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (rounds.isEmpty) Text(l.chNothingToTest, textAlign: TextAlign.center, style: t.bodyLarge)
              else ...[
                Text(l.chScore(score), style: t.headlineMedium),
                Text(l.xpEarned(_xp), style: t.bodyLarge),
              ],
              const SizedBox(height: HSpace.l),
              FilledButton(onPressed: () => context.pop(), child: Text(l.continueLabel)),
            ]),
          ),
        ),
      );
    }

    final round = rounds[_i];
    final a = round.ayah;
    final s = quran.surahInfo(a.surah);
    Widget body;
    switch (round) {
      case _ChoiceRound(:final hiddenPos, :final options):
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${s.nameTransliterated} ${a.surah}:${a.ayah}', textAlign: TextAlign.center, style: t.titleMedium),
          const SizedBox(height: HSpace.s),
          Card(child: Padding(padding: const EdgeInsets.all(HSpace.m), child: QuranText(a, hiddenWords: _choiceFeedback == null ? {hiddenPos} : const {}, highlightWords: _choiceFeedback == null ? const {} : {hiddenPos}))),
          const SizedBox(height: HSpace.m),
          Text(l.chChooseWord, textAlign: TextAlign.center),
          const SizedBox(height: HSpace.s),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: HSpace.s),
              child: OutlinedButton(
                onPressed: _choiceFeedback != null
                    ? null
                    : () {
                        final ok = o == a.word(hiddenPos);
                        setState(() => _choiceFeedback = ok ? l.chCorrect : l.chWrong);
                        Future.delayed(const Duration(milliseconds: 1200),
                            () => _finishRound(a, ok ? 1 : 0, ok ? <int>{} : {hiddenPos}));
                      },
                child: Text(o, textDirection: TextDirection.rtl, style: const TextStyle(fontFamily: HFonts.quran, fontSize: 24)),
              ),
            ),
          if (_choiceFeedback != null) Text(_choiceFeedback!, textAlign: TextAlign.center, style: t.titleMedium),
        ]);
      case _SurahGuessRound(:final options):
        if (_surahCorrect == null) {
          body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.chWhichSurah, textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: HSpace.s),
            Card(child: Padding(padding: const EdgeInsets.all(HSpace.m), child: QuranText(a, hiddenWords: {for (var i = 3; i <= a.wordCount; i++) i}))),
            const SizedBox(height: HSpace.m),
            for (final n in options)
              Padding(
                padding: const EdgeInsets.only(bottom: HSpace.s),
                child: OutlinedButton(
                  onPressed: () => setState(() => _surahCorrect = n == a.surah),
                  child: Text('$n. ${quran.surahInfo(n).nameTransliterated}'),
                ),
              ),
          ]);
        } else {
          body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_surahCorrect! ? l.chCorrect : l.chItWas(s.nameTransliterated), textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: HSpace.m),
            RecallCheck(
              key: ValueKey('g$_i'),
              ayah: a,
              visibleWords: const {1, 2},
              onDone: (r) => _finishRound(a, _surahCorrect! ? r.accuracy : r.accuracy * 0.5, r.missed, recallMs: r.recallMs, hints: r.hintsUsed),
            ),
          ]);
        }
      case _RecallRound(:final visible, :final anchor, :final prompt):
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${s.nameTransliterated} ${a.surah}:${a.ayah}', textAlign: TextAlign.center, style: t.titleMedium),
          if (anchor != null)
            Card(child: Padding(padding: const EdgeInsets.all(HSpace.m), child: QuranText(anchor, size: HQuranSize.min, showNumber: true))),
          const SizedBox(height: HSpace.s),
          RecallCheck(
            key: ValueKey('r$_i'),
            ayah: a,
            visibleWords: visible,
            prompt: prompt,
            onDone: (r) => _finishRound(a, r.accuracy, r.missed, recallMs: r.recallMs, hints: r.hintsUsed),
          ),
        ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_i + 1} / ${rounds.length}'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: LinearProgressIndicator(value: _i / rounds.length)),
      ),
      body: ListView(padding: const EdgeInsets.all(HSpace.l), children: [body]),
    );
  }
}
