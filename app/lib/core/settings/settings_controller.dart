import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the real instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

const supportedLocales = [Locale('en'), Locale('ml'), Locale('ar')];

@immutable
class AppSettings {
  const AppSettings({
    required this.locale,
    required this.themeMode,
    required this.reciterId,
    required this.translationIds,
    required this.speed,
    required this.repeatCount,
  });

  final Locale locale;
  final ThemeMode themeMode;

  /// One Qari for every session, so memorisation always uses the same recitation.
  final String reciterId;

  /// Translations shown under each Ayah, in this order. Can be several.
  final List<String> translationIds;
  final double speed; // 0.5 – 1.5
  final int repeatCount; // how many times each Ayah plays in Listen

  AppSettings copyWith({
    Locale? locale,
    ThemeMode? themeMode,
    String? reciterId,
    List<String>? translationIds,
    double? speed,
    int? repeatCount,
  }) =>
      AppSettings(
        locale: locale ?? this.locale,
        themeMode: themeMode ?? this.themeMode,
        reciterId: reciterId ?? this.reciterId,
        translationIds: translationIds ?? this.translationIds,
        speed: speed ?? this.speed,
        repeatCount: repeatCount ?? this.repeatCount,
      );
}

const defaultReciterId = 'Husary_Muallim_128kbps';

class SettingsController extends Notifier<AppSettings> {
  static const _kLocale = 'ui_locale';
  static const _kTheme = 'theme_mode';
  static const _kReciter = 'reciter_id';
  static const _kTranslations = 'translation_ids';
  static const _kSpeed = 'audio_speed';
  static const _kRepeat = 'audio_repeat';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final code = _prefs.getString(_kLocale) ?? 'en';
    final theme = ThemeMode.values.asNameMap()[_prefs.getString(_kTheme)] ?? ThemeMode.system;
    final defaultTranslations = code == 'ml' ? ['ml.abdulhameed'] : ['en.sahih'];
    return AppSettings(
      locale: Locale(code),
      themeMode: theme,
      reciterId: _prefs.getString(_kReciter) ?? defaultReciterId,
      translationIds: _prefs.getStringList(_kTranslations) ?? defaultTranslations,
      speed: _prefs.getDouble(_kSpeed) ?? 1.0,
      repeatCount: _prefs.getInt(_kRepeat) ?? 3,
    );
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

  Future<void> setReciter(String id) async {
    await _prefs.setString(_kReciter, id);
    state = state.copyWith(reciterId: id);
  }

  Future<void> setTranslations(List<String> ids) async {
    await _prefs.setStringList(_kTranslations, ids);
    state = state.copyWith(translationIds: ids);
  }

  Future<void> toggleTranslation(String id) async {
    final list = [...state.translationIds];
    list.contains(id) ? list.remove(id) : list.add(id);
    await setTranslations(list);
  }

  Future<void> setSpeed(double s) async {
    await _prefs.setDouble(_kSpeed, s);
    state = state.copyWith(speed: s);
  }

  Future<void> setRepeat(int n) async {
    await _prefs.setInt(_kRepeat, n);
    state = state.copyWith(repeatCount: n);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
