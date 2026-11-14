import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/settings/settings_controller.dart';
import '../audio/audio_widgets.dart';
import 'matcher.dart';
import 'teacher.dart';
import 'teacher_feedback.dart';

/// One word to correct: its position in the Ayah and what went wrong.
class Correction {
  const Correction(this.position, this.problem,
      {this.color, this.how = '', this.arabicRule = '', this.tip = false, this.type});
  final int position; // 1-based word position in the verified Ayah
  final String problem;
  final Color? color;
  final String how;
  final String arabicRule;

  /// A tip: worth listening to, but not counted as a mistake.
  final bool tip;
  final TeacherErrorType? type;
}

/// Turns the teacher's findings for one Ayah into correction cards.
List<Correction> correctionsFor(AppLocalizations l, AyahReport a, int wordCount, ColorScheme scheme) {
  int pos(int i) => mapPosition(i + 1, a.words.length, wordCount);
  return [
    for (final e in [...a.mistakes, ...a.tips])
      () {
        final f = describe(l, e);
        return Correction(
          pos(e.wordStart),
          '${f.title}: ${f.detail}',
          color: e.mistake ? colorFor(e.type, scheme) : scheme.outline,
          how: f.how,
          arabicRule: f.arabicRule,
          tip: !e.mistake,
          type: e.type,
        );
      }(),
  ];
}

/// "Correct it with the reciter": every word that went wrong, what exactly was wrong,
/// a button to hear that word recited correctly, the whole Ayah from your Qari, and
/// Try again.
class CorrectionPanel extends ConsumerWidget {
  const CorrectionPanel({super.key, required this.ayah, required this.items, this.onRetry, this.onDismiss, this.footer});
  final VerifiedAyah ayah;
  final List<Correction> items;
  final VoidCallback? onRetry;

  /// "Not a mistake": the learner disagrees with a finding; it's removed and not counted.
  final ValueChanged<Correction>? onDismiss;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final repeat = ref.watch(settingsProvider).repeatCount;

    Widget card(Correction c) => Card(
          margin: const EdgeInsets.only(bottom: HSpace.s),
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(HRadius.m),
            side: BorderSide(color: (c.color ?? s.error).withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HSpace.m, HSpace.s, HSpace.s, HSpace.s),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(c.problem, style: t.bodyMedium?.copyWith(color: c.color ?? s.error, fontWeight: FontWeight.w600))),
                    if (c.arabicRule.isNotEmpty) Text(c.arabicRule, textDirection: TextDirection.rtl, style: t.bodySmall),
                  ]),
                  Text(ayah.word(c.position),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: HFonts.quran, fontSize: 24)),
                  if (c.how.isNotEmpty) Text(c.how, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                  if (onDismiss != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                        icon: const Icon(Icons.close, size: 16),
                        label: Text(l.notAMistake),
                        onPressed: () => onDismiss!(c),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: HSpace.s),
              IconButton.filledTonal(
                tooltip: l.hearWord,
                icon: const Icon(Icons.volume_up),
                onPressed: () => ref.read(audioProvider.notifier).playWord(ayah.surah, ayah.ayah, c.position),
              ),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (items.any((c) => !c.tip)) ...[
        Text(l.correctTitle, style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: HSpace.s),
      ],
      for (final c in items.where((c) => !c.tip)) card(c),
      if (items.any((c) => c.tip))
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(l.tipsTitle(items.where((c) => c.tip).length), style: t.titleSmall),
            subtitle: Text(l.tipsSub, style: t.bodySmall),
            children: [for (final c in items.where((c) => c.tip)) card(c)],
          ),
        ),
      const SizedBox(height: HSpace.s),
      Text(l.correctHint, style: t.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.s),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        PlayAyahButton(ayahs: [ayah], repeat: repeat),
        const SizedBox(width: HSpace.s),
        Flexible(child: Text(l.hearAyah, style: t.bodyMedium)),
      ]),
      if (onRetry != null) ...[
        const SizedBox(height: HSpace.s),
        OutlinedButton.icon(icon: const Icon(Icons.replay), label: Text(l.tryAgain), onPressed: onRetry),
      ],
      if (footer != null) ...[const SizedBox(height: HSpace.s), footer!],
    ]);
  }
}
