import 'package:flutter/material.dart';

/// Design tokens. Every colour, size and duration in the app comes from here.
abstract final class HColors {
  // Brand: deep emerald with warm neutrals and a restrained gold accent.
  static const emerald900 = Color(0xFF06302A);
  static const emerald800 = Color(0xFF0A4A3F);
  static const emerald700 = Color(0xFF0F5E50);
  static const emerald600 = Color(0xFF147A68);
  static const emerald500 = Color(0xFF1C9781);
  static const emerald100 = Color(0xFFD7EFE9);
  static const emerald50 = Color(0xFFEEF8F5);
  static const gold500 = Color(0xFFB8893B);
  static const gold100 = Color(0xFFF4E9D3);

  static const sand50 = Color(0xFFFBF9F4);   // light background (paper)
  static const sand100 = Color(0xFFF3EFE6);
  static const stone300 = Color(0xFFD6D1C6);
  static const stone500 = Color(0xFF8A8478);
  static const stone700 = Color(0xFF4A463F);
  static const ink900 = Color(0xFF1B1A17);

  static const night900 = Color(0xFF0B1412);  // dark background
  static const night800 = Color(0xFF121E1B);
  static const night700 = Color(0xFF1A2925);
  static const night500 = Color(0xFF2C3E39);

  // Memorisation status — used consistently in chips, the journey map and charts.
  static const statusNew = Color(0xFF8A8478);
  static const statusLearning = Color(0xFF2F7FB8);
  static const statusRecent = Color(0xFF7B5EA7);
  static const statusStable = Color(0xFF1C9781);
  static const statusStrong = Color(0xFF0A4A3F);
  static const statusNeedsRevision = Color(0xFFC0563A);
}

abstract final class HSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class HRadius {
  static const s = Radius.circular(8);
  static const m = Radius.circular(14);
  static const l = Radius.circular(22);
  static const pill = Radius.circular(999);
}

abstract final class HMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const curve = Curves.easeOutCubic;
}

/// Font families. The Quran face is used only by [QuranText].
abstract final class HFonts {
  static const quran = 'UthmanicHafs';
  static const malayalam = 'NotoSansMalayalam';
}

/// Minimum Quran text size; users can scale up from here in settings (never below).
abstract final class HQuranSize {
  static const min = 24.0;
  static const normal = 30.0;
  static const large = 38.0;
  static const lineHeight = 2.1; // room for harakat and waqf marks
}
