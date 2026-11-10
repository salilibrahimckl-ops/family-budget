import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hifz_academy/core/l10n/l10n.dart';
import 'package:hifz_academy/core/settings/settings_controller.dart';
import 'package:hifz_academy/features/demo/demo_data.dart';
import 'package:hifz_academy/features/demo/guide_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the tour walks through every page and can start demo mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    final router = GoRouter(initialLocation: '/guide', routes: [
      GoRoute(path: '/guide', builder: (_, __) => const GuideScreen()),
      GoRoute(path: '/today', builder: (_, __) => const Scaffold(body: Text('TODAY'))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your plan for today'), findsOneWidget);
    expect(prefs.getBool(guideSeenKey), isTrue);

    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Next'));
    // The last page has Noor, who bobs forever, so pump a fixed time instead of settling.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('See it in action'), findsOneWidget);
    await tester.tap(find.text('Try demo mode'));
    await tester.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);
    expect(c.read(demoModeProvider), isTrue);
  });
}
