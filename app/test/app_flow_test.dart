import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hifz_academy/core/l10n/l10n.dart';
import 'package:hifz_academy/core/settings/settings_controller.dart';
import 'package:hifz_academy/features/onboarding/onboarding_flow.dart';
import 'package:hifz_academy/features/onboarding/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps the assessment on its own, with a stub "Today" page as the destination.
Future<ProviderContainer> pump(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
  final router = GoRouter(initialLocation: '/onboarding', routes: [
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingFlow()),
    GoRoute(path: '/today', builder: (_, __) => const Scaffold(body: Text('TODAY'))),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (context, ref, _) {
      final s = ref.watch(settingsProvider);
      return MaterialApp.router(
        routerConfig: router,
        locale: s.locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      );
    }),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('assessment builds a plan and saves it', (tester) async {
    final c = await pump(tester);
    expect(find.text('Step 1 of 7'), findsOneWidget);

    Future<void> pick(String label) async {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Continue')); // English already selected
    await tester.pumpAndSettle();
    await pick('I read fluently');
    await pick('The basics (Noon Sakinah, Madd)');
    await pick('A few short Surahs');
    await pick('Memorise selected Surahs');
    await pick('30 minutes');
    await pick('Steady — about 3 new Ayahs a day');

    expect(find.text('3 new Ayahs a day'), findsOneWidget);
    await tester.tap(find.text('Start learning'));
    await tester.pumpAndSettle();

    expect(find.text('TODAY'), findsOneWidget);
    expect(c.read(onboardingProvider)?.dailyMinutes, 30);
  });

  testWidgets('Arabic interface lays out right-to-left', (tester) async {
    await pump(tester, prefs: {'ui_locale': 'ar'});
    final dir = Directionality.of(tester.element(find.byType(Scaffold).first));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('Malayalam interface loads its strings', (tester) async {
    await pump(tester, prefs: {'ui_locale': 'ml'});
    expect(find.text('ആപ്പ് ഏത് ഭാഷയിൽ വേണം?'), findsOneWidget);
  });
}
