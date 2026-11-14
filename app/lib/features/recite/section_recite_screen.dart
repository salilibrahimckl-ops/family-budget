import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/audio.dart';
import '../../core/audio/sfx.dart';
import '../../core/design/quran_text.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/settings/settings_controller.dart';
import '../memorisation/progress_controller.dart';
import 'correction_panel.dart';
import 'teacher.dart';
import 'teacher_feedback.dart';

/// Recite a whole section (one or many Ayahs) to the AI teacher in one go. The teacher
/// listens while you recite, then reports Ayah by Ayah. One section is one check.
class SectionReciteScreen extends ConsumerStatefulWidget {
  const SectionReciteScreen({super.key, required this.surah, this.from, this.to});
  final int surah;
  final int? from;
  final int? to;

  @override
  ConsumerState<SectionReciteScreen> createState() => _SectionReciteScreenState();
}

enum _Phase { idle, recording, checking, result }

class _SectionReciteScreenState extends ConsumerState<SectionReciteScreen> {
  late int _from = widget.from ?? 1;
  late int _to = widget.to ?? (widget.from ?? 1);
  bool _showText = false;
  _Phase _phase = _Phase.idle;
  bool _waking = false;
  String? _note;
  TeacherClient? _client;
  TeacherResult? _result;
  final _items = <int, List<Correction>>{}; // Ayah number -> corrections
  Timer? _tick;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    ref.read(teacherUrlProvider.future).then((u) {
      if (u != null) warmUpTeacher(u);
    }).ignore();
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_phase == _Phase.recording) _client?.cancel();
    _client?.dispose();
    super.dispose();
  }

  List<VerifiedAyah> _ayahs(QuranRepository q) => q.surah(widget.surah).where((a) => a.ayah >= _from && a.ayah <= _to).toList();

  Future<void> _start() async {
    final l = context.l10n;
    final url = await ref.read(teacherUrlProvider.future);
    if (!mounted) return;
    if (url == null) {
      setState(() => _note = l.teacherNotSetUp);
      return;
    }
    if (!await ensureTeacherNotice(context, ref)) return;
    ref.read(audioProvider.notifier).stop();
    _client ??= TeacherClient(ref.read(sharedPrefsProvider));
    bool ok;
    try {
      ok = await _client!.start(
        baseUrl: url,
        sura: widget.surah,
        from: _from,
        to: _to,
        strict: ref.read(settingsProvider).strictTajweed,
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _note = l.micUnavailable);
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _phase = _Phase.recording;
      _note = null;
      _result = null;
      _saved = false;
    });
  }

  Future<void> _done() async {
    final l = context.l10n;
    _tick?.cancel();
    setState(() {
      _phase = _Phase.checking;
      _waking = false;
    });
    try {
      final r = await _client!.finish(onStatus: (w) {
        if (mounted) setState(() => _waking = w);
      });
      if (!mounted) return;
      final quran = ref.read(quranProvider)!;
      final scheme = Theme.of(context).colorScheme;
      _items.clear();
      for (final a in r.ayahs) {
        final va = quran.surah(widget.surah).firstWhere((x) => x.ayah == a.aya);
        _items[a.aya] = a.recited ? correctionsFor(l, a, va.wordCount, scheme) : [];
      }
      setState(() {
        _phase = _Phase.result;
        _result = r;
        _note = switch (r.status) {
          'different_ayah' => l.teacherDifferent,
          'too_little' || 'silent' => l.unableToAssess,
          'unclear' => l.teacherUnclear,
          _ => null,
        };
      });
      final anyMistake = r.ayahs.any((a) => a.recited && a.mistakes.isNotEmpty);
      if (r.assessed && !anyMistake) {
        ref.read(sfxProvider).success();
      } else if (r.assessed) {
        ref.read(sfxProvider).oops();
      }
    } on TeacherUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _note = switch (e.reason) {
          'daily_limit' => l.teacherDailyLimit,
          'shared_limit' => l.teacherSharedLimit,
          _ => l.teacherOffline,
        };
      });
    }
  }

  Future<void> _cancel() async {
    _tick?.cancel();
    await _client?.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  /// Word mistakes (what counts for memorisation) in an Ayah, as 1-based positions.
  Set<int> _missed(VerifiedAyah va) => {
        for (final c in _items[va.ayah] ?? const <Correction>[])
          if (!c.tip && c.type == TeacherErrorType.word) c.position,
      };

  Set<int> _flagged(VerifiedAyah va) => {for (final c in _items[va.ayah] ?? const <Correction>[]) if (!c.tip) c.position};

  /// Records each recited Ayah you've already memorised as a revision.
  Future<void> _save() async {
    final quran = ref.read(quranProvider)!;
    final ctrl = ref.read(progressProvider.notifier);
    final p = ref.read(progressProvider).valueOrNull;
    final r = _result!;
    var n = 0;
    for (final a in r.ayahs.where((a) => a.recited)) {
      final va = quran.surah(widget.surah).firstWhere((x) => x.ayah == a.aya);
      if (p?.records[va.id] == null) continue; // not started yet: just practice
      final missed = _missed(va);
      final tajweed = _flagged(va).difference(missed);
      await ctrl.record(
        ayah: va,
        mode: AttemptMode.revision,
        accuracy: va.wordCount == 0 ? 1 : (va.wordCount - missed.length) / va.wordCount,
        missedWordPositions: missed,
        tajweedWordPositions: tajweed,
        method: 'ai_phoneme',
        quran: quran,
      );
      n++;
    }
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.sectionSaved(n))));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quran = ref.watch(quranProvider);
    if (quran == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final info = quran.surahInfo(widget.surah);
    final ayahs = _ayahs(quran);
    final count = info.ayahCount;

    Widget picker() => Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _from,
              decoration: InputDecoration(labelText: l.fromAyah, border: const OutlineInputBorder()),
              items: [for (var i = 1; i <= count; i++) DropdownMenuItem(value: i, child: Text('$i'))],
              onChanged: (v) => setState(() {
                _from = v!;
                if (_to < _from) _to = _from;
              }),
            ),
          ),
          const SizedBox(width: HSpace.s),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('to$_from$_to'),
              initialValue: _to,
              decoration: InputDecoration(labelText: l.toAyah, border: const OutlineInputBorder()),
              items: [
                for (var i = _from; i <= count; i++) DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _to = v!),
            ),
          ),
        ]);

    final r = _result;
    final elapsed = _client?.elapsed ?? Duration.zero;
    String mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text(l.sectionTitle)),
      body: ListView(padding: const EdgeInsets.all(HSpace.l), children: [
        Text('${info.number}. ${info.nameTransliterated}', style: t.titleLarge),
        const SizedBox(height: HSpace.m),
        if (_phase == _Phase.idle || _phase == _Phase.result) ...[
          picker(),
          if (_from != 1 || _to != count)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.select_all),
                label: Text(l.wholeSurah),
                onPressed: () => setState(() {
                  _from = 1;
                  _to = count;
                }),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.showTextWhileReciting),
            value: _showText,
            onChanged: (v) => setState(() => _showText = v),
          ),
        ],
        if (_note != null)
          Container(
            margin: const EdgeInsets.only(bottom: HSpace.m),
            padding: const EdgeInsets.all(HSpace.m),
            decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: const BorderRadius.all(HRadius.m)),
            child: Text(_note!, style: t.bodyMedium),
          ),
        switch (_phase) {
          _Phase.idle => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.sectionHint, style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: HSpace.m),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.mic),
                label: Text(l.sectionStart(_to - _from + 1)),
                onPressed: _start,
              ),
            ]),
          _Phase.recording => Column(children: [
              const _Pulse(),
              const SizedBox(height: HSpace.s),
              Text(l.sectionListening, style: t.titleMedium, textAlign: TextAlign.center),
              Text(mmss(elapsed), style: t.headlineSmall),
              const SizedBox(height: HSpace.m),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: scheme.error, minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.stop_rounded),
                label: Text(l.micDone),
                onPressed: _done,
              ),
              TextButton(onPressed: _cancel, child: Text(l.cancel)),
            ]),
          _Phase.checking => Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: HSpace.s),
              Text(_waking ? l.teacherWaking : l.teacherChecking, textAlign: TextAlign.center),
            ]),
          _Phase.result => _summary(context, r!),
        },
        const SizedBox(height: HSpace.m),
        for (final va in ayahs)
          if (_showText || (_phase == _Phase.result && ((_items[va.ayah]?.isNotEmpty ?? false) || ayahs.length <= 10)))
            _ayahCard(context, va, r),
        if (_phase == _Phase.result && r != null && r.assessed) ...[
          const SizedBox(height: HSpace.m),
          FilledButton.icon(
            icon: Icon(_saved ? Icons.check : Icons.save_alt),
            label: Text(_saved ? l.sectionSavedShort : l.sectionSave),
            onPressed: _saved ? null : _save,
          ),
          const SizedBox(height: HSpace.s),
          OutlinedButton.icon(icon: const Icon(Icons.replay), label: Text(l.tryAgain), onPressed: _start),
          const SizedBox(height: HSpace.s),
          Text(l.teacherShortNotice, style: t.bodySmall, textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _summary(BuildContext context, TeacherResult r) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final recited = r.ayahs.where((a) => a.recited).toList();
    final perfect = recited.where((a) => (_items[a.aya] ?? const []).every((c) => c.tip)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        recited.isEmpty ? l.unableToAssess : l.sectionSummary(perfect, recited.length),
        style: t.titleMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: HSpace.s),
      if (recited.isNotEmpty) TeacherReport(result: r, errors: [for (final a in recited) ...a.errors]),
    ]);
  }

  Widget _ayahCard(BuildContext context, VerifiedAyah va, TeacherResult? r) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final report = r?.ayahs.where((a) => a.aya == va.ayah).firstOrNull;
    final items = _items[va.ayah] ?? const <Correction>[];
    final mistakes = items.where((c) => !c.tip).length;
    final status = report == null
        ? null
        : !report.recited
            ? (l.notRecited, scheme.outline, Icons.remove_circle_outline)
            : mistakes == 0
                ? (l.ayahPerfect, Colors.green, Icons.check_circle)
                : (l.ayahMistakes(mistakes), scheme.error, Icons.error_outline);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(HSpace.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(l.ayahN(va.ayah), style: t.labelLarge),
            const Spacer(),
            if (status != null) ...[
              Icon(status.$3, color: status.$2, size: 18),
              const SizedBox(width: 4),
              Text(status.$1, style: t.labelLarge?.copyWith(color: status.$2)),
            ],
          ]),
          const SizedBox(height: HSpace.s),
          QuranText(va, highlightWords: report == null ? const {} : _flagged(va)),
          if (items.isNotEmpty) ...[
            const SizedBox(height: HSpace.s),
            CorrectionPanel(
              ayah: va,
              items: items,
              onDismiss: _saved ? null : (c) => setState(() => _items[va.ayah] = [...items]..remove(c)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: Tween(begin: 0.9, end: 1.1).animate(_c),
      child: CircleAvatar(radius: 40, backgroundColor: scheme.errorContainer, child: Icon(Icons.mic, size: 40, color: scheme.error)),
    );
  }
}

/// Picks a sensible section to recite: the Surah with the most Ayahs due for revision
/// (from its first to its last due Ayah), else the Surah memorised most recently.
(int surah, int from, int to) suggestedSection(QuranRepository quran, ProgressState p, List<int> due) {
  if (due.isNotEmpty) {
    final bySurah = <int, List<int>>{};
    for (final id in due) {
      final a = quran.byId(id);
      bySurah.putIfAbsent(a.surah, () => []).add(a.ayah);
    }
    final best = bySurah.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
    final lo = best.value.reduce((a, b) => a < b ? a : b);
    var hi = best.value.reduce((a, b) => a > b ? a : b);
    if (hi - lo >= 60) hi = lo + 59;
    return (best.key, lo, hi);
  }
  final mem = p.memorised.toList()
    ..sort((a, b) => (b.firstMasteredAt ?? DateTime(2000)).compareTo(a.firstMasteredAt ?? DateTime(2000)));
  if (mem.isNotEmpty) {
    final a = quran.byId(mem.first.ayahId);
    final ids = p.memorised.map((r) => quran.byId(r.ayahId)).where((x) => x.surah == a.surah).map((x) => x.ayah).toList()..sort();
    final lo = ids.first;
    final hi = ids.last - ids.first >= 60 ? ids.first + 59 : ids.last;
    return (a.surah, lo, hi);
  }
  return (1, 1, 7);
}

void openSection(BuildContext context, int surah, int from, int to) => context.push('/recite/$surah?from=$from&to=$to');
