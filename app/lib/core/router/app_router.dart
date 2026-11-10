import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/challenges/challenges.dart';
import '../../features/common/upcoming_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/gamification/achievements_screens.dart';
import '../../features/gamification/sticker_book.dart';
import '../../features/demo/guide_screen.dart';
import '../../features/lesson/lesson_screen.dart';
import '../../features/onboarding/onboarding_flow.dart';
import '../../features/reader/reader_screens.dart';
import '../../features/revision/revision_screens.dart';
import '../../features/settings/profile_settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/updates/updates.dart';
import '../l10n/l10n.dart';

/// All 17 screens are routed. Those still marked UpcomingScreen state which phase builds them.
GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SplashScreen()),                 // 1 Splash
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingFlow()),     // 2 + 4 Assessment
        GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),               // 3 Authentication
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => _Shell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (_, __) => const DashboardScreen())]), // 5
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/quran',
                builder: (_, __) => const SurahListScreen(), // 6 Quran reader
                routes: [
                  GoRoute(path: ':surah', builder: (_, s) => SurahScreen(surah: int.parse(s.pathParameters['surah']!))),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/revise', builder: (_, __) => const RevisionQueueScreen())]), // 11
            StatefulShellBranch(routes: [GoRoute(path: '/challenges', builder: (_, __) => const ChallengesScreen())]), // 12
            StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (_, __) => const ProfileSettingsScreen())]), // 16
          ],
        ),
        GoRoute(path: '/lesson/:ayahId', builder: (_, s) => LessonScreen(ayahId: int.parse(s.pathParameters['ayahId']!))), // 7
        GoRoute(path: '/review', builder: (_, __) => const ReviewSessionScreen()),
        GoRoute(
          path: '/challenge/:kind',
          builder: (_, s) => ChallengeSessionScreen(kind: ChallengeKind.values.byName(s.pathParameters['kind']!)),
        ),
        GoRoute(path: '/audio', builder: (c, __) => UpcomingScreen(title: c.l10n.screenAudio, phase: 5)),               // 8
        GoRoute(path: '/record/:ayahId', builder: (c, __) => UpcomingScreen(title: c.l10n.screenRecord, phase: 9)),     // 9
        GoRoute(path: '/feedback/:attemptId', builder: (c, __) => UpcomingScreen(title: c.l10n.screenFeedback, phase: 9)), // 10
        GoRoute(path: '/tajweed', builder: (c, __) => UpcomingScreen(title: c.l10n.screenTajweed, phase: 11)),          // 13
        GoRoute(path: '/analytics', builder: (c, __) => UpcomingScreen(title: c.l10n.screenAnalytics, phase: 13)),      // 14
        GoRoute(path: '/journey', builder: (_, __) => const JourneyScreen()),                                          // 15
        GoRoute(path: '/achievements', builder: (_, __) => const AchievementsScreen()),
        GoRoute(path: '/guide', builder: (_, __) => const GuideScreen()),
        GoRoute(path: '/stickers', builder: (_, __) => const StickerBookScreen()),
        GoRoute(path: '/updates', builder: (_, __) => const UpdatesScreen()),
        GoRoute(path: '/premium', builder: (c, __) => UpcomingScreen(title: c.l10n.screenSubscription, phase: 13)),     // 17
      ],
    );

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const DemoBanner(),
        NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), selectedIcon: const Icon(Icons.wb_sunny), label: l.navToday),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: l.navQuran),
          NavigationDestination(icon: const Icon(Icons.replay_outlined), selectedIcon: const Icon(Icons.replay), label: l.navRevise),
          NavigationDestination(icon: const Icon(Icons.emoji_events_outlined), selectedIcon: const Icon(Icons.emoji_events), label: l.navChallenges),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: l.navMe),
        ],
      ),
      ]),
    );
  }
}
