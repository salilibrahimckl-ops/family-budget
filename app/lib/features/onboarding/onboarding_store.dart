import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';
import 'learning_plan.dart';

/// Persists onboarding answers on the device (moves to Supabase `learning_preferences` in Phase 3).
class OnboardingStore extends Notifier<OnboardingAnswers?> {
  static const _key = 'onboarding_answers_v1';

  @override
  OnboardingAnswers? build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return null;
    try {
      return OnboardingAnswers.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // older/invalid format: ask again rather than guess
    }
  }

  Future<void> save(OnboardingAnswers a) async {
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(a.toJson()));
    state = a;
  }

  Future<void> clear() async {
    await ref.read(sharedPrefsProvider).remove(_key);
    state = null;
  }
}

final onboardingProvider = NotifierProvider<OnboardingStore, OnboardingAnswers?>(OnboardingStore.new);

final learningPlanProvider = Provider<LearningPlan?>((ref) {
  final a = ref.watch(onboardingProvider);
  return a == null ? null : buildPlan(a);
});
