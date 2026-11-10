import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/quran/translations.dart';
import '../../core/settings/settings_controller.dart';

/// Play / stop button for one Ayah (or a run of Ayahs).
class PlayAyahButton extends ConsumerWidget {
  const PlayAyahButton({super.key, required this.ayahs, this.repeat = 1, this.reciterId, this.big = false});
  final List<VerifiedAyah> ayahs;
  final int repeat;
  final String? reciterId;
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(audioProvider);
    final mine = ayahs.any((a) => a.id == st.ayahId) && (st.playing || st.loading);
    final ctrl = ref.read(audioProvider.notifier);
    final icon = st.error && ayahs.any((a) => a.id == st.ayahId)
        ? Icons.wifi_off
        : mine
            ? Icons.stop_rounded
            : Icons.play_arrow_rounded;
    final onTap = mine ? ctrl.stop : () => ctrl.play(ayahs, repeatEach: repeat, reciterId: reciterId);
    if (big) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: mine && st.loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon),
        label: Text(mine
            ? (st.rounds > 1 ? context.l10n.playingRound(st.round, st.rounds) : context.l10n.stop)
            : context.l10n.listen),
      );
    }
    return IconButton.filledTonal(
      tooltip: mine ? context.l10n.stop : context.l10n.listen,
      onPressed: onTap,
      icon: mine && st.loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
    );
  }
}

/// Speed and repeat controls used in the Listen step and the reader.
class AudioOptions extends ConsumerWidget {
  const AudioOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final l = context.l10n;
    return Wrap(spacing: HSpace.s, runSpacing: HSpace.s, alignment: WrapAlignment.center, children: [
      for (final sp in const [0.75, 1.0, 1.25])
        ChoiceChip(
          label: Text('${sp}x'),
          selected: s.speed == sp,
          onSelected: (_) {
            c.setSpeed(sp);
            ref.read(audioProvider.notifier).setSpeed(sp);
          },
        ),
      for (final n in const [1, 3, 5, 10])
        ChoiceChip(label: Text(l.repeatTimes(n)), selected: s.repeatCount == n, onSelected: (_) => c.setRepeat(n)),
    ]);
  }
}

/// The learner's chosen translations under an Ayah, each credited.
class TranslationsBlock extends ConsumerWidget {
  const TranslationsBlock({super.key, required this.ayah, this.ids, this.compact = false});
  final VerifiedAyah ayah;
  final List<String>? ids; // default: the user's chosen translations
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ids ?? ref.watch(settingsProvider).translationIds;
    final index = ref.watch(translationIndexProvider).valueOrNull ?? const [];
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (final id in chosen) {
      final info = index.where((i) => i.id == id).firstOrNull;
      final rows = ref.watch(translationProvider(id)).valueOrNull;
      if (info == null || rows == null) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: HSpace.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            rows[ayah.id - 1],
            style: (compact ? t.bodyMedium : t.bodyLarge)?.copyWith(
              fontStyle: info.isTransliteration ? FontStyle.italic : null,
              fontFamily: info.lang == 'ml' ? HFonts.malayalam : null,
            ),
          ),
          if (!compact) Text('— ${info.name}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ));
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widgets);
  }
}
