import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/quran_repository.dart';
import '../../core/widgets/widgets.dart';
import '../onboarding/onboarding_store.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final result = ref.watch(quranLoadProvider);

    ref.listen(quranLoadProvider, (_, next) {
      final r = next.valueOrNull;
      final canContinue = r is QuranReady || (r is QuranMissing && kDebugMode);
      if (canContinue) {
        final onboarded = ref.read(onboardingProvider) != null;
        Future.delayed(HMotion.slow, () {
          if (context.mounted) context.go(onboarded ? '/today' : '/onboarding');
        });
      }
    });

    final Widget status = switch (result.valueOrNull) {
      QuranCorrupt() => _Blocked(title: l.quranCorruptTitle, body: l.quranCorruptBody),
      QuranMissing() when !kDebugMode => _Blocked(title: l.quranMissingTitle, body: l.quranMissingBody),
      QuranMissing() => _DevNotice(text: '${l.devBuild}: ${l.quranMissingTitle}'),
      _ => const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(HSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandMark(size: 84),
              const SizedBox(height: HSpace.l),
              Text(l.appTitle, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: HSpace.s),
              Text(l.tagline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              const SizedBox(height: HSpace.xl),
              status,
            ]),
          ),
        ),
      ),
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(Icons.gpp_bad_outlined, color: Theme.of(context).colorScheme.error, size: 36),
        const SizedBox(height: HSpace.s),
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: HSpace.xs),
        Text(body, textAlign: TextAlign.center),
      ]);
}

class _DevNotice extends StatelessWidget {
  const _DevNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: HSpace.m, vertical: HSpace.s),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: const BorderRadius.all(HRadius.pill),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      );
}
