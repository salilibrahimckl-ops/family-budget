// Replaces the sample test that `flutter create` generates (it referred to a demo app).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hifz_academy/core/design/theme.dart';

void main() {
  test('light and dark themes build for all three languages', () {
    for (final code in ['en', 'ml', 'ar']) {
      expect(HTheme.light(Locale(code)).brightness, Brightness.light);
      expect(HTheme.dark(Locale(code)).brightness, Brightness.dark);
    }
  });
}
