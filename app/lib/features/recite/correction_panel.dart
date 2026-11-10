import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/settings/settings_controller.dart';
import '../audio/audio_widgets.dart';

/// One word to correct: its position in the Ayah and what went wrong.
class Correction {
  const Correction(this.position, this.problem, {this.color, this.how = '', this.arabicRule = ''});
  final int position; // 1-based word position in the verified Ayah
  final String problem;
  final Color? color;
  final String how;
  final String arabicRule;
}

/// "Correct it with the reciter": every word that went wrong, what exactly was wrong,
/// a button to hear that word recited correctly, the whole Ayah from your Qari, and
/// Try again.
class CorrectionPanel extends ConsumerWidget {
  const CorrectionPanel({super.key, required this.ayah, required this.items, this.onRetry, this.footer});
  final VerifiedAyah ayah;
  final List<Correction> items;
  final VoidCallback? onRetry;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final repeat = ref.watch(settingsProvider).repeatCount;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (items.isNotEmpty) ...[
        Text(l.correctTitle, style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: HSpace.s),
      ],
      for (final c in items)
        Card(
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
