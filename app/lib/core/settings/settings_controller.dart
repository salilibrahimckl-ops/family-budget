import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the real instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

const supportedLocales = [Locale('en'), Locale('ml'), Locale('ar')];

@immutable
class AppSettings {
  const AppSettings({required this.locale, required this.themeMode});
  final Locale locale;
  final ThemeMode themeMode;

  AppSettings copyWith({Locale? locale, ThemeMode? themeMode}) =>
      AppSettings(locale: locale ?? this.locale, themeMode: themeMode ?? this.themeMode);
}

class SettingsController extends Notifier<AppSettings> {
  static const _kLocale = 'ui_locale';
  static const _kTheme = 'theme_mode';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final code = _prefs.getString(_kLocale) ?? 'en';
    final theme = ThemeMode.values.asNameMap()[_prefs.getString(_kTheme)] ?? ThemeMode.system;
    return AppSettings(locale: Locale(code), themeMode: theme);
  }

  /// Changing language never touches learning data; progress is keyed by Ayah id.
  Future<void> setLocale(Locale l) async {
    await _prefs.setString(_kLocale, l.languageCode);
    state = state.copyWith(locale: l);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    await _prefs.setString(_kTheme, m.name);
    state = state.copyWith(themeMode: m);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
