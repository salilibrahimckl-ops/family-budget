import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'teacher.dart';

/// Name of a Tajweed rule in the learner's language (Arabic name always shown too).
String ruleName(AppLocalizations l, TeacherRule r) => switch (r.kind) {
      'NormalMaddRule' => l.ruleNormalMadd,
      'MonfaselMaddRule' => l.ruleMonfasel,
      'MottaselMaddRule' || 'MottaselMaddPauseRule' => l.ruleMottasel,
      'LazemMaddRule' => l.ruleLazem,
      'AaredMaddRule' => l.ruleAared,
      'LeenMaddRule' => l.ruleLeen,
      'Qalqalah' => l.ruleQalqalah,
      'IdghamKamel' => l.ruleIdgham,
      'Ghonnah' || 'MoshaddadOrModghamNoonRule' => l.ruleGhunnah,
      _ => r.en.isNotEmpty ? r.en : r.kind,
    };

/// One-line reminder of what the rule asks for.
String ruleHow(AppLocalizations l, TeacherRule r) => switch (r.kind) {
      'NormalMaddRule' => l.howNormalMadd,
      'MonfaselMaddRule' => l.howMonfasel,
      'MottaselMaddRule' || 'MottaselMaddPauseRule' => l.howMottasel,
      'LazemMaddRule' => l.howLazem,
      'AaredMaddRule' => l.howAared,
      'LeenMaddRule' => l.howLeen,
      'Qalqalah' => l.howQalqalah,
      'IdghamKamel' => l.howIdgham,
      'Ghonnah' || 'MoshaddadOrModghamNoonRule' => l.howGhunnah,
      _ => '',
    };

class FeedbackLine {
  const FeedbackLine(this.title, this.detail, this.how, this.arabicRule);
  final String title;
  final String detail;
  final String how;
  final String arabicRule;
}

FeedbackLine describe(AppLocalizations l, TeacherError e) {
  final rule = e.rules.firstOrNull ?? e.missingRules.firstOrNull ?? e.extraRules.firstOrNull;
  switch (e.type) {
    case TeacherErrorType.tajweed:
      final name = rule == null ? l.tajweedGeneric : ruleName(l, rule);
      final String detail;
      if (e.expectedLen != null && e.heardLen != null && e.expectedLen != e.heardLen) {
        detail = e.heardLen! < e.expectedLen! ? l.heldTooShort(e.expectedLen!, e.heardLen!) : l.heldTooLong(e.expectedLen!, e.heardLen!);
      } else if (e.missingRules.isNotEmpty) {
        detail = l.ruleMissing;
      } else if (e.extraRules.isNotEmpty) {
        detail = l.ruleExtra;
      } else {
        detail = l.ruleNotApplied;
      }
      return FeedbackLine(name, detail, rule == null ? '' : ruleHow(l, rule), rule?.ar ?? '');
    case TeacherErrorType.harakah:
      return FeedbackLine(l.harakahTitle, l.saidInstead(e.heard.isEmpty ? '—' : e.heard, e.expected), l.harakahHow, '');
    case TeacherErrorType.word:
      final detail = switch (e.speech) {
        'delete' => l.leftOut(e.expected),
        'insert' => l.addedExtra(e.heard),
        _ => l.saidInstead(e.heard, e.expected),
      };
      return FeedbackLine(e.speech == 'delete' ? l.missedTitle : l.letterTitle, detail, '', '');
  }
}

Color colorFor(TeacherErrorType t, ColorScheme s) => switch (t) {
      TeacherErrorType.word => s.error,
      TeacherErrorType.harakah => const Color(0xFF7E57C2),
      TeacherErrorType.tajweed => const Color(0xFFEF8C00),
    };

/// The teacher's summary: how many word, harakah and Tajweed mistakes it found.
class TeacherReport extends StatelessWidget {
  const TeacherReport({super.key, required this.result, this.errors});
  final TeacherResult result;

  /// The findings to count (defaults to the first Ayah's).
  final Iterable<TeacherError>? errors;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final all = (errors ?? result.first.errors).where((e) => e.mistake);
    final words = all.where((e) => e.type == TeacherErrorType.word).length;
    final harakat = all.where((e) => e.type == TeacherErrorType.harakah).length;
    final tajweed = all.where((e) => e.type == TeacherErrorType.tajweed).length;

    Widget pill(String text, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: t.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (result.status == 'unclear')
        Padding(padding: const EdgeInsets.only(bottom: HSpace.s), child: Text(l.teacherUnclear, style: t.bodySmall)),
      Wrap(spacing: HSpace.s, runSpacing: HSpace.s, alignment: WrapAlignment.center, children: [
        pill(l.countWords(words), colorFor(TeacherErrorType.word, s)),
        pill(l.countHarakat(harakat), colorFor(TeacherErrorType.harakah, s)),
        pill(l.countTajweed(tajweed), colorFor(TeacherErrorType.tajweed, s)),
      ]),
      const SizedBox(height: HSpace.s),
      Text(l.teacherShortNotice, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant), textAlign: TextAlign.center),
    ]);
  }
}
