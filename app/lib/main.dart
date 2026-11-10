import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/backend/backend.dart';
import 'core/design/theme.dart';
import 'core/l10n/l10n.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await initBackend();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const HifzApp(),
  ));
}

class HifzApp extends ConsumerStatefulWidget {
  const HifzApp({super.key});

  @override
  ConsumerState<HifzApp> createState() => _HifzAppState();
}

class _HifzAppState extends ConsumerState<HifzApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return MaterialApp.router(
      onGenerateTitle: (c) => c.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      locale: s.locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: HTheme.light(s.locale, kids: s.kidsMode),
      darkTheme: HTheme.dark(s.locale, kids: s.kidsMode),
      themeMode: s.themeMode,
      // Kids mode: slightly bigger text everywhere.
      builder: (context, child) => s.kidsMode
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * 1.12),
              ),
              child: child!,
            )
          : child!,
    );
  }
}
