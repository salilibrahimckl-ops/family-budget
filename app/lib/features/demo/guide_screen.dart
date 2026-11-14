import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/widgets/noor.dart';
import 'demo_data.dart';

const guideSeenKey = 'guide_seen_v1';

class _Page {
  const _Page(this.icon, this.title, this.body, this.points, {this.tryRoute, this.push = false});
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
  final String? tryRoute; // where "Try it" goes
  final bool push; // true for full-screen routes; tabs are opened with go
}

/// "How to use Hifz Academy": a short swipeable tour of every feature, each with a
/// "Try it" button, ending with demo mode (sample progress) or starting for real.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key});

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  final _pc = PageController();
  int _i = 0;

  @override
  void initState() {
    super.initState();
    ref.read(sharedPrefsProvider).setBool(guideSeenKey, true);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  List<_Page> _pages(AppLocalizations l) => [
        _Page(Icons.wb_sunny_rounded, l.g1Title, l.g1Body, [l.g1p1, l.g1p2, l.g1p3], tryRoute: '/today'),
        _Page(Icons.auto_stories, l.g2Title, l.g2Body, [l.g2p1, l.g2p2, l.g2p3, l.g2p4], tryRoute: '/lesson/1', push: true),
        _Page(Icons.mic, l.g3Title, l.g3Body, [l.g3p1, l.g3p2, l.g3p3]),
        _Page(Icons.replay_circle_filled, l.g4Title, l.g4Body, [l.g4p1, l.g4p2, l.g4p3], tryRoute: '/revise'),
        _Page(Icons.emoji_events, l.g5Title, l.g5Body, [l.g5p1, l.g5p2], tryRoute: '/challenges', push: true),
        _Page(Icons.menu_book, l.g6Title, l.g6Body, [l.g6p1, l.g6p2, l.g6p3], tryRoute: '/quran'),
        _Page(Icons.military_tech, l.g7Title, l.g7Body, [l.g7p1, l.g7p2, l.g7p3], tryRoute: '/achievements', push: true),
        _Page(Icons.tune, l.g8Title, l.g8Body, [l.g8p1, l.g8p2, l.g8p3], tryRoute: '/me'),
      ];

  void _try(_Page p) {
    final r = p.tryRoute;
    if (r == null) return;
    if (p.push) {
      context.push(r);
    } else {
      context.go(r);
    }
  }

  void _startDemo() {
    ref.read(demoModeProvider.notifier).state = true;
    context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pages = _pages(l);
    final total = pages.length + 1;
    final last = _i == total - 1;

    Widget pageView(_Page p) => ListView(padding: const EdgeInsets.all(HSpace.l), children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(HSpace.l),
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(p.icon, size: 56, color: scheme.primary),
            ),
          ),
          const SizedBox(height: HSpace.l),
          Text(p.title, style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: HSpace.s),
          Text(p.body, style: t.bodyLarge, textAlign: TextAlign.center),
          const SizedBox(height: HSpace.l),
          for (final pt in p.points)
            Padding(
              padding: const EdgeInsets.only(bottom: HSpace.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle, size: 20, color: scheme.secondary),
                const SizedBox(width: HSpace.s),
                Expanded(child: Text(pt, style: t.bodyMedium)),
              ]),
            ),
          if (p.tryRoute != null) ...[
            const SizedBox(height: HSpace.m),
            OutlinedButton.icon(icon: const Icon(Icons.touch_app), label: Text(l.guideTryIt), onPressed: () => _try(p)),
          ],
        ]);

    final finale = ListView(padding: const EdgeInsets.all(HSpace.l), children: [
      const Center(child: Noor(size: 110)),
      const SizedBox(height: HSpace.l),
      Text(l.gEndTitle, style: t.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.s),
      Text(l.gEndBody, style: t.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.l),
      FilledButton.icon(icon: const Icon(Icons.play_circle), label: Text(l.demoStart), onPressed: _startDemo),
      const SizedBox(height: HSpace.s),
      Text(l.demoExplain, style: t.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: HSpace.l),
      OutlinedButton(onPressed: () => context.go('/today'), child: Text(l.gEndStart)),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.guideTitle),
        actions: [if (!last) TextButton(onPressed: () => _pc.jumpToPage(total - 1), child: Text(l.guideSkip))],
      ),
      body: Column(children: [
        Expanded(
          child: PageView(
            controller: _pc,
            onPageChanged: (i) => setState(() => _i = i),
            children: [for (final p in pages) pageView(p), finale],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: HSpace.s),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < total; k++)
              AnimatedContainer(
                duration: HMotion.normal,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: k == _i ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: k == _i ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
        ),
      ]),
      bottomNavigationBar: last
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(HSpace.l),
              child: FilledButton(
                onPressed: () => _pc.nextPage(duration: HMotion.normal, curve: Curves.easeOut),
                child: Text(l.guideNext),
              ),
            ),
    );
  }
}

/// Thin strip shown at the top of every tab while demo mode is on.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoModeProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    return Material(
      color: const Color(0xFFFFE8C2),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(HSpace.m, 4, 4, 4),
          child: Row(children: [
            const Icon(Icons.science, size: 18, color: Color(0xFF7A4A00)),
            const SizedBox(width: HSpace.s),
            Expanded(child: Text(l.demoBanner, style: const TextStyle(color: Color(0xFF3A2E17), fontSize: 13))),
            TextButton(
              onPressed: () => ref.read(demoModeProvider.notifier).state = false,
              child: Text(l.demoExit, style: const TextStyle(color: Color(0xFF7A4A00), fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
