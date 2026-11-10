import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio.dart';
import '../../../core/audio/sfx.dart';
import '../../../core/design/quran_text.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/quran/quran_repository.dart';
import '../../../core/quran/tafsir.dart';
import '../../recite/matcher.dart';
import '../../recite/recite_service.dart';
import '../../recite/teacher.dart';
import '../../recite/teacher_feedback.dart';
import '../../recite/correction_panel.dart';

class RecallResult {
  const RecallResult({
    required this.missed,
    required this.accuracy,
    required this.recallMs,
    required this.hintsUsed,
    this.method = 'self_report',
    this.confidence,
    this.tajweedWords = const {},
  });
  final Set<int> missed; // 1-based word positions
  final double accuracy;
  final int recallMs;
  final int hintsUsed;
  final String method; // 'self_report' | 'asr_word' | 'ai_phoneme'
  final double? confidence;

  /// Words with a Tajweed mistake found by the AI teacher (1-based). Recorded and shown,
  /// but not counted against memorisation: the words themselves were right.
  final Set<int> tajweedWords;
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

  // AI teacher
  TeacherClient? _client;
  bool _recording = false;
  bool _checking = false;
  bool _waking = false;
  TeacherResult? _teacher;
  final _tajweed = <int>{};
  final _wordColor = <int, TeacherErrorType>{};

  /// What exactly went wrong, word by word, for the correction panel.
  final _corrections = <Correction>[];
  bool _usedPhoneCheck = false;

  void _retry() {
    ref.read(audioProvider.notifier).stop();
    setState(() {
      _revealed = false;
      _missed.clear();
      _tajweed.clear();
      _wordColor.clear();
      _corrections.clear();
      _teacher = null;
      _speechNote = null;
      _unsure = false;
      _method = 'self_report';
      _confidence = null;
      _heard = '';
    });
  }

  @override
  void initState() {
    super.initState();
    // Wake the free server early so it's ready by the time the learner recites.
    ref.read(teacherUrlProvider.future).then((u) {
      if (u != null) warmUpTeacher(u);
    }).ignore();
  }

  Set<int> get _allWords => {for (var i = 1; i <= widget.ayah.wordCount; i++) i};

  Set<int> get _hidden {
    if (_revealed) return const {};
    final shown = {...widget.visibleWords, for (var i = 1; i <= _hints; i++) i};
    return _allWords.difference(shown);
  }

  @override
  void dispose() {
    if (_listening) _recite.stop();
    if (_recording) _client?.cancel();
    _client?.dispose();
    super.dispose();
  }

  void _reveal() => setState(() {
        _revealed = true;
        _recallMs ??= _sw.elapsedMilliseconds;
      });

  Future<void> _startListening() async {
    final url = await ref.read(teacherUrlProvider.future);
    if (!mounted) return;
    if (url != null) return _startTeacher(url);
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

  String? _teacherUrl;

  Future<void> _startTeacher(String url) async {
    final l = context.l10n;
    if (!await ensureTeacherNotice(context, ref)) return;
    _client ??= TeacherClient();
    bool started;
    try {
      started = await _client!.start();
    } catch (_) {
      started = false;
    }
    if (!mounted) return;
    if (!started) {
      setState(() => _speechNote = l.micUnavailable);
      return;
    }
    _teacherUrl = url;
    setState(() {
      _recording = true;
      _speechNote = null;
      _unsure = false;
    });
  }

  Future<void> _finishTeacher() async {
    final l = context.l10n;
    setState(() {
      _recording = false;
      _checking = true;
      _waking = false;
    });
    try {
      final audio = await _client!.stop();
      if (audio == null || audio.isEmpty) throw const TeacherUnavailable('no audio');
      final r = await _client!.check(
        baseUrl: _teacherUrl!,
        audio: audio,
        sura: widget.ayah.surah,
        aya: widget.ayah.ayah,
        onStatus: (w) {
          if (mounted) setState(() => _waking = w);
        },
      );
      if (!mounted) return;
      _reveal();
      setState(() {
        _checking = false;
        _teacher = r;
        if (!r.assessed) {
          _unsure = true;
          _speechNote = switch (r.status) { 'different_ayah' => l.teacherDifferent, _ => l.unableToAssess };
          return;
        }
        _method = 'ai_phoneme';
        _confidence = r.confidence;
        _missed.clear();
        _tajweed.clear();
        _wordColor.clear();
        int pos(int i) => mapPosition(i + 1, r.words.length, widget.ayah.wordCount);
        for (final e in r.errors) {
          for (var i = e.wordStart; i <= e.wordEnd; i++) {
            final p = pos(i);
            if (e.type == TeacherErrorType.tajweed) {
              _tajweed.add(p);
            } else {
              _missed.add(p);
            }
            final prev = _wordColor[p];
            if (prev == null || e.type.index < prev.index) _wordColor[p] = e.type;
          }
        }
        _corrections.clear();
        final sch = Theme.of(context).colorScheme;
        for (final e in r.errors) {
          final f = describe(l, e);
          final p = pos(e.wordStart);
          _corrections.add(Correction(p, '${f.title}: ${f.detail}', color: colorFor(e.type, sch), how: f.how, arabicRule: f.arabicRule));
        }
        _speechNote = r.errors.isEmpty ? l.teacherPerfect : null;
      });
      if (r.errors.isEmpty) {
        ref.read(sfxProvider).success();
      } else {
        ref.read(sfxProvider).oops();
      }
    } on TeacherUnavailable {
      if (!mounted) return;
      _reveal();
      setState(() {
        _checking = false;
        _unsure = true;
        _speechNote = l.teacherOffline;
      });
    }
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
        _usedPhoneCheck = true;
        _speechNote = words.trim().isEmpty ? l.unableToAssess : '${l.unableToAssess}\n${l.iHeard(words.trim())}';
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
      _usedPhoneCheck = true;
      _corrections.clear();
      for (var i = 0; i < r.verdicts.length; i++) {
        if (r.verdicts[i] == WordVerdict.correct) continue;
        final p = mapPosition(i + 1, expected.length, widget.ayah.wordCount);
        final heard = r.heardFor[i];
        _corrections.add(Correction(p, r.verdicts[i] == WordVerdict.missing || heard == null ? l.youMissed : l.youSaid(heard)));
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
      if (_recording) ...[
        _ListeningPanel(heard: '', label: l.teacherListening),
        const SizedBox(height: HSpace.s),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          icon: const Icon(Icons.stop_rounded),
          label: Text(l.micDone),
          onPressed: _finishTeacher,
        ),
      ] else if (_checking) ...[
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: HSpace.s),
        Text(_waking ? l.teacherWaking : l.teacherChecking, textAlign: TextAlign.center, style: t.bodyMedium),
      ] else if (_listening) ...[
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
              if (_method == 'ai_phoneme') ...[
                const SizedBox(height: 4),
                Text(l.teacherShortNotice, style: t.bodySmall),
              ],
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
                  selectedColor: _wordColor[i] == TeacherErrorType.harakah
                      ? colorFor(TeacherErrorType.harakah, scheme).withValues(alpha: 0.25)
                      : scheme.errorContainer,
                  side: _tajweed.contains(i) && !_missed.contains(i)
                      ? BorderSide(color: colorFor(TeacherErrorType.tajweed, scheme), width: 2)
                      : null,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => v ? _missed.add(i) : _missed.remove(i)),
                ),
            ],
          ),
        ),
        if (_teacher != null && _teacher!.assessed && _teacher!.errors.isNotEmpty) ...[
          const SizedBox(height: HSpace.m),
          TeacherReport(result: _teacher!),
        ],
        if (_corrections.isNotEmpty || _unsure) ...[
          const SizedBox(height: HSpace.m),
          CorrectionPanel(
            ayah: widget.ayah,
            items: _corrections,
            onRetry: _retry,
            footer: _usedPhoneCheck && _teacher == null
                ? Text(l.tajweedNotOnYet, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center)
                : null,
          ),
        ],
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
            tajweedWords: Set.of(_tajweed),
          )),
          child: Text(l.continueLabel),
        ),
      ],
    ]);
  }
}

class _ListeningPanel extends StatefulWidget {
  const _ListeningPanel({required this.heard, this.label});
  final String heard;
  final String? label;

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
      Text(widget.label ?? context.l10n.micListening, style: Theme.of(context).textTheme.titleMedium),
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
