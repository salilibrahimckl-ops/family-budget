import 'package:flutter/material.dart';

import '../quran/quran_repository.dart';
import 'tokens.dart';

/// The only widget allowed to render Quranic text.
///
/// - Accepts a [VerifiedAyah], never a String, so unverified text cannot reach the screen.
/// - Always right-to-left, whatever the interface language.
/// - Never truncates. Memory exercises hide whole words with [hiddenWords] (1-based word
///   positions); the hidden word keeps its exact width, so the text itself is untouched.
/// - Pause marks are never hidden.
class QuranText extends StatelessWidget {
  const QuranText(
    this.ayah, {
    super.key,
    this.size = HQuranSize.normal,
    this.hiddenWords = const {},
    this.highlightWords = const {},
    this.textAlign = TextAlign.center,
    this.showNumber = false,
  }) : assert(size >= HQuranSize.min);

  final VerifiedAyah ayah;
  final double size;
  final Set<int> hiddenWords;
  final Set<int> highlightWords; // e.g. words the learner missed
  final TextAlign textAlign;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontFamily: HFonts.quran, fontSize: size, height: HQuranSize.lineHeight, color: scheme.onSurface);

    final spans = <InlineSpan>[];
    var wordPos = 0;
    for (var i = 0; i < ayah.tokens.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final tok = ayah.tokens[i];
      final isWord = QuranWords.isWord(tok);
      if (isWord) wordPos++;
      TextStyle? s;
      if (isWord && hiddenWords.contains(wordPos)) {
        s = style.copyWith(color: Colors.transparent, backgroundColor: scheme.surfaceContainerHigh);
      } else if (isWord && highlightWords.contains(wordPos)) {
        s = style.copyWith(color: scheme.error, decoration: TextDecoration.underline, decorationColor: scheme.error);
      }
      spans.add(TextSpan(text: tok, style: s));
    }
    if (showNumber) {
      spans.add(TextSpan(
        text: ' ۝${_arabicDigits(ayah.ayah)}',
        style: style.copyWith(color: scheme.primary),
      ));
    }

    return Semantics(
      label: 'Quran ${ayah.surah}:${ayah.ayah}',
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Text.rich(TextSpan(children: spans), style: style, textAlign: textAlign),
      ),
    );
  }
}

/// Renders the Surah's Basmala exactly as supplied by the verified source.
class BasmalaText extends StatelessWidget {
  const BasmalaText(this.surah, {super.key, this.size = HQuranSize.normal});
  final VerifiedSurah surah;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = surah.bismillah;
    if (b == null) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(b,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: HFonts.quran, fontSize: size, height: HQuranSize.lineHeight,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}

String _arabicDigits(int n) =>
    n.toString().split('').map((d) => String.fromCharCode(0x0660 + int.parse(d))).join();
