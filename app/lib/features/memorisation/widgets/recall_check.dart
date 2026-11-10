import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/design/quran_text.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/quran/quran_repository.dart';
import '../../../core/quran/tafsir.dart';
import '../../recite/matcher.dart';
import '../../recite/recite_service.dart';

class RecallResult {
  const RecallResult({
    required this.missed,
    required this.accuracy,
    required this.recallMs,
    required this.hintsUsed,
    this.method = 'self_report',
    this.confidence,
  });
  final Set<int> missed; // 1-based word positions
  final double accuracy;
  final int recallMs;
  final int hintsUsed;
  final String method; // 'self_report' | 'asr_word'
  final double? confidence;
}

/// Active-recall check used by lessons, revision and challenges.
///
/// Two ways to check:
/// - Recite into the microphone: the phone's speech recogniser listens, and every word
///   is compared with the verified Ayah. Missed or wrong words are marked automatically
///   (words only, not Tajweed). If too little was heard, it says so instead of guessing.
/// - Self-check: reveal the Ayah and tap the words you missed.
/// Either way the learner can correct the marks before continuing.
class RecallCheck extends ConsumerStatefulWidget {
  const RecallCheck({
    super.key,
    required this.ayah,
    required this.onDone,
    this.visibleWords = const {},
    this.prompt,
    this.allowHint = true,
  });

  final VerifiedAyah ayah;
  final ValueChanged<RecallResult> onDone;
  final Set<int> visibleWords;
  final String? prompt;
  final bool allowHint;

  @override
  ConsumerState<RecallCheck> createState() => _RecallCheckState();
}

class _RecallCheckState extends ConsumerState<RecallCheck> {
  final _sw = Stopwatch()..start();
  bool _revealed = false;
  int _hints = 0;
  final _missed = <int>{};
  int? _recallMs;

  // speech
  bool _listening = false;
  String _heard = '';
  String _method = 'self_report';
  double? _confidence;
  String? _speechNote; // shown after an automatic check
  bool _unsure = false;

  late final ReciteService _recite = ref.read(reciteServiceProvider);

  Set<int> get _allWords => {for (var i = 1; i <= widget.ayah.wordCount; i++) i};

  Set<int> get _hidden {
    if (_revealed) return const {};
    final shown = {...widget.visibleWords, for (var i = 1; i <= _hints; i++) i};
    return _allWords.difference(shown);
  }

  @override
  void dispose() {
    if (_listening) _recite.stop();
    super.dispose();
  }

  void _reveal() => setState(() {
        _revealed = true;
        _recallMs ??= _sw.elapsedMilliseconds;
      });

  Future<void> _startListening() async {
    final l = context.l10n;
    if (!await ensureSpeechConsent(context, ref)) return;
    final svc = _recite;
    if (!await svc.init()) {
      if (mounted) setState(() => _speechNote = l.micUnavailable);
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
      _speechNote = null;
      _unsure = false;
    });
    await svc.listen(
      onPartial: (w) {
        if (mounted) setState(() => _heard = w);
      },
      onDone: (w, conf) => _finish(w, conf),
    );
  }

  Future<void> _stopListening() async {
    await _recite.stop();
    // onDone fires with the final result; if nothing was heard, finish here.
    if (mounted && _listening && _heard.isEmpty) _finish('', -1);
  }

  Future<void> _finish(String words, double conf) async {
    if (!mounted || !_listening) return;
    final l = context.l10n;
    setState(() => _listening = false);
    final simple = await ref.read(simpleCleanProvider.future);
    if (!mounted) return;
    if (simple == null) {
      setState(() => _speechNote = l.micUnavailable);
      return;
    }
    final expected = normalizedWords(simple[widget.ayah.id - 1]);
    final r = checkRecitation(expected, normalizedWords(words), recognizerConfidence: conf);
    _reveal();
    setState(() {
      if (!r.confident) {
        _unsure = true;
        _speechNote = l.unableToAssess;
        return;
      }
      _method = 'asr_word';
      _confidence = conf < 0 ? r.coverage : conf;
      _missed.clear();
      for (var i = 0; i < r.verdicts.length; i++) {
        if (r.verdicts[i] != WordVerdict.correct) {
          _missed.add(mapPosition(i + 1, expected.length, widget.ayah.wordCount));
        }
      }
      _speechNote = _missed.isEmpty ? l.speechPerfect : l.speechFoundMistakes(_missed.length);
    });
    if (_missed.isEmpty) {
      ref.read(sfxProvider).success();
    } else {
      ref.read(sfxProvider).oops();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = widget.ayah.wordCount;
    final accuracy = total == 0 ? 1.0 : (total - _missed.length) / total;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.prompt ?? (_revealed ? l.recallMarkMissed : l.recallInstruction), style: t.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.m),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(HSpace.m),
          child: QuranText(widget.ayah, hiddenWords: _hidden, highlightWords: _revealed ? _missed : const {}),
        ),
      ),
      const SizedBox(height: HSpace.m),
      if (_listening) ...[
        _ListeningPanel(heard: _heard),
        const SizedBox(height: HSpace.s),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          icon: const Icon(Icons.stop_rounded),
          label: Text(l.micDone),
          onPressed: _stopListening,
        ),
      ] else if (!_revealed) ...[
        FilledButton.icon(icon: const Icon(Icons.mic), label: Text(l.micRecite), onPressed: _startListening),
        const SizedBox(height: HSpace.s),
        OutlinedButton(onPressed: _reveal, child: Text(l.recallCheck)),
        if (widget.allowHint && _hints < total - 1)
          TextButton(onPressed: () => setState(() => _hints++), child: Text(l.recallHint)),
        if (_speechNote != null) Text(_speechNote!, textAlign: TextAlign.center, style: t.bodySmall),
      ] else ...[
        if (_speechNote != null)
          Container(
            margin: const EdgeInsets.only(bottom: HSpace.m),
            padding: const EdgeInsets.all(HSpace.m),
            decoration: BoxDecoration(
              color: _unsure ? scheme.errorContainer : scheme.primaryContainer,
              borderRadius: const BorderRadius.all(HRadius.m),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_speechNote!, style: t.bodyMedium),
              if (_method == 'asr_word') ...[
                const SizedBox(height: 4),
                Text(l.speechDisclaimer, style: t.bodySmall),
              ],
            ]),
          ),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: HSpace.s,
            runSpacing: HSpace.s,
            children: [
              for (var i = 1; i <= total; i++)
                FilterChip(
                  label: Text(widget.ayah.word(i), style: const TextStyle(fontFamily: HFonts.quran, fontSize: 20)),
                  selected: _missed.contains(i),
                  selectedColor: scheme.errorContainer,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => v ? _missed.add(i) : _missed.remove(i)),
                ),
            ],
          ),
        ),
        const SizedBox(height: HSpace.m),
        Text(_missed.isEmpty ? l.recallNoMistakes : l.recallAccuracy((accuracy * 100).round()),
            textAlign: TextAlign.center, style: t.titleMedium),
        const SizedBox(height: HSpace.s),
        FilledButton(
          onPressed: () => widget.onDone(RecallResult(
            missed: Set.of(_missed),
            accuracy: accuracy,
            recallMs: _recallMs ?? _sw.elapsedMilliseconds,
            hintsUsed: _hints,
            method: _method,
            confidence: _confidence,
          )),
          child: Text(l.continueLabel),
        ),
      ],
    ]);
  }
}

class _ListeningPanel extends StatefulWidget {
  const _ListeningPanel({required this.heard});
  final String heard;

  @override
  State<_ListeningPanel> createState() => _ListeningPanelState();
}

class _ListeningPanelState extends State<_ListeningPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.1).animate(_pulse),
        child: CircleAvatar(radius: 32, backgroundColor: scheme.errorContainer, child: Icon(Icons.mic, size: 32, color: scheme.error)),
      ),
      const SizedBox(height: HSpace.s),
      Text(context.l10n.micListening, style: Theme.of(context).textTheme.titleMedium),
      if (widget.heard.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: HSpace.s),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(widget.heard, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
    ]);
  }
}
