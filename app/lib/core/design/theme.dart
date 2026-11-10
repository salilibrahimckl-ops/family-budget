import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds light and dark themes. Malayalam gets its own font and extra line height,
/// because Malayalam conjuncts are taller than Latin text.
abstract final class HTheme {
  static ThemeData light(Locale locale) => _build(Brightness.light, locale);
  static ThemeData dark(Locale locale) => _build(Brightness.dark, locale);

  static ThemeData _build(Brightness b, Locale locale) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: isDark ? HColors.emerald500 : HColors.emerald700,
      onPrimary: Colors.white,
      primaryContainer: isDark ? HColors.emerald800 : HColors.emerald100,
      onPrimaryContainer: isDark ? HColors.emerald50 : HColors.emerald900,
      secondary: HColors.gold500,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? const Color(0xFF3A2E17) : HColors.gold100,
      onSecondaryContainer: isDark ? HColors.gold100 : const Color(0xFF3A2E17),
      error: HColors.statusNeedsRevision,
      onError: Colors.white,
      errorContainer: isDark ? const Color(0xFF4A2219) : const Color(0xFFF8DED6),
      onErrorContainer: isDark ? const Color(0xFFF8DED6) : const Color(0xFF4A2219),
      surface: isDark ? HColors.night900 : HColors.sand50,
      onSurface: isDark ? const Color(0xFFE9E6DF) : HColors.ink900,
      surfaceContainerLow: isDark ? HColors.night800 : Colors.white,
      surfaceContainer: isDark ? HColors.night700 : HColors.sand100,
      surfaceContainerHigh: isDark ? HColors.night500 : const Color(0xFFECE7DC),
      onSurfaceVariant: isDark ? const Color(0xFFB4AEA3) : HColors.stone700,
      outline: isDark ? HColors.night500 : HColors.stone300,
      outlineVariant: isDark ? HColors.night700 : const Color(0xFFE6E1D7),
    );

    final isMl = locale.languageCode == 'ml';
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    final text = base.textTheme
        .apply(
          fontFamily: isMl ? HFonts.malayalam : null,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, height: isMl ? 1.45 : 1.25),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: isMl ? 1.5 : 1.3),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: isMl ? 1.5 : 1.35),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: isMl ? 1.65 : 1.5),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: isMl ? 1.65 : 1.5),
        );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(HRadius.m),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(HRadius.m)),
          textStyle: text.titleMedium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(HRadius.m)),
          side: BorderSide(color: scheme.outline),
          textStyle: text.titleMedium,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
