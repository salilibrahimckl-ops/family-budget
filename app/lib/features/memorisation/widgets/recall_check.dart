import 'package:flutter/material.dart';

import '../../../core/design/quran_text.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/quran/quran_repository.dart';

class RecallResult {
  const RecallResult({required this.missed, required this.accuracy, required this.recallMs, required this.hintsUsed});
  final Set<int> missed; // 1-based word positions
  final double accuracy;
  final int recallMs;
  final int hintsUsed;
}

/// Active-recall check used by lessons, revision and challenges.
///
/// 1. Text hidden (or partly shown via [visibleWords]); learner recites aloud from memory.
/// 2. "Check" reveals the verified text.
/// 3. Learner taps each word they missed or got wrong; accuracy = correct / total words.
/// This is a self-check: it is stored as method 'self_report'. Automatic checking by
/// speech recognition is added in Phase 9.
class RecallCheck extends StatefulWidget {
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
  final Set<int> visibleWords; // words shown as a prompt (e.g. first half for "Complete the Ayah")
  final String? prompt;
  final bool allowHint;

  @override
  State<RecallCheck> createState() => _RecallCheckState();
}

class _RecallCheckState extends State<RecallCheck> {
  final _sw = Stopwatch()..start();
  bool _revealed = false;
  int _hints = 0;
  final _missed = <int>{};
  int? _recallMs;

  Set<int> get _allWords => {for (var i = 1; i <= widget.ayah.wordCount; i++) i};

  Set<int> get _hidden {
    if (_revealed) return const {};
    final shown = {...widget.visibleWords, for (var i = 1; i <= _hints; i++) i};
    return _allWords.difference(shown);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = widget.ayah.wordCount;
    final accuracy = total == 0 ? 1.0 : (total - _missed.length) / total;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.prompt ?? (_revealed ? l.recallMarkMissed : l.recallInstruction),
          style: t.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.m),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(HSpace.m),
          child: QuranText(widget.ayah, hiddenWords: _hidden, highlightWords: _revealed ? _missed : const {}),
        ),
      ),
      const SizedBox(height: HSpace.m),
      if (!_revealed) ...[
        FilledButton(
          onPressed: () => setState(() {
            _revealed = true;
            _recallMs = _sw.elapsedMilliseconds;
          }),
          child: Text(l.recallCheck),
        ),
        if (widget.allowHint && _hints < total - 1)
          TextButton(onPressed: () => setState(() => _hints++), child: Text(l.recallHint)),
      ] else ...[
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
        Text(
          _missed.isEmpty ? l.recallNoMistakes : l.recallAccuracy((accuracy * 100).round()),
          textAlign: TextAlign.center,
          style: t.titleMedium,
        ),
        const SizedBox(height: HSpace.s),
        FilledButton(
          onPressed: () => widget.onDone(RecallResult(
            missed: Set.of(_missed),
            accuracy: accuracy,
            recallMs: _recallMs ?? _sw.elapsedMilliseconds,
            hintsUsed: _hints,
          )),
          child: Text(l.continueLabel),
        ),
      ],
    ]);
  }
}
