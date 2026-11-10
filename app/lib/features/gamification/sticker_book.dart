import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/widgets/noor.dart';
import '../memorisation/progress_controller.dart';

/// One sticker for every memorised Ayah, in the order they were first mastered,
/// with the next few shown as locked shapes to aim for.
class StickerBookScreen extends ConsumerWidget {
  const StickerBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = ref.watch(progressProvider).valueOrNull;
    final quran = ref.watch(quranProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (p == null || quran == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final earned = p.memorised.toList()
      ..sort((a, b) => (a.firstMasteredAt ?? DateTime(2000)).compareTo(b.firstMasteredAt ?? DateTime(2000)));
    const locked = 6;

    return Scaffold(
      appBar: AppBar(title: Text(l.stickerBook)),
      body: ListView(padding: const EdgeInsets.all(HSpace.l), children: [
        NoorSays(earned.isEmpty ? l.stickersEmpty : l.stickersCount(earned.length)),
        const SizedBox(height: HSpace.l),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: HSpace.s,
          crossAxisSpacing: HSpace.s,
          children: [
            for (final (i, r) in earned.indexed)
              _Sticker(
                index: i,
                icon: stickerFor(r.ayahId).$1,
                color: stickerFor(r.ayahId).$2,
                label: () {
                  final a = quran.byId(r.ayahId);
                  return '${a.surah}:${a.ayah}';
                }(),
              ),
            for (var i = 0; i < locked; i++)
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: const BorderRadius.all(HRadius.m),
                ),
                child: Icon(Icons.lock_outline, color: scheme.outline),
              ),
          ],
        ),
        const SizedBox(height: HSpace.m),
        Text(l.stickersHint, textAlign: TextAlign.center, style: t.bodySmall),
      ]),
    );
  }
}

class _Sticker extends StatelessWidget {
  const _Sticker({required this.index, required this.icon, required this.color, required this.label});
  final int index;
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + 40 * (index % 12)),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.all(HRadius.m),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 34),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}
