import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/audio.dart';
import '../../core/design/tokens.dart';
import '../../core/quran/quran_providers.dart';
import '../../core/quran/translations.dart';
import '../../core/l10n/l10n.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/widgets/widgets.dart';
import '../audio/audio_widgets.dart';
import 'learning_plan.dart';
import 'onboarding_store.dart';

/// Learning assessment: 9 short steps (several answers allowed where it makes sense),
/// then the generated plan.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  static const _questions = 10;
  int _step = 0;

  ReadingAbility? _reading;
  TajweedKnowledge? _tajweed;
  MemorisedAmount? _memorised;
  final Set<LearningGoal> _goals = {};
  int? _minutes;
  Pace? _pace;

  bool get _answered => switch (_step) {
        0 => true, // language always has a value
        1 => _reading != null,
        2 => _tajweed != null,
        3 => _memorised != null,
        4 => _goals.isNotEmpty,
        5 => _minutes != null,
        6 => _pace != null || !_wantsNew,
        _ => true,
      };

  OnboardingAnswers _answers() => OnboardingAnswers(
        reading: _reading!,
        tajweed: _tajweed!,
        memorised: _memorised!,
        goals: Set.of(_goals),
        dailyMinutes: _minutes!,
        pace: _pace ?? Pace.gentle,
        uiLanguage: ref.read(settingsProvider).locale.languageCode,
      );

  bool get _wantsNew =>
      _goals.contains(LearningGoal.fromBeginning) ||
      _goals.contains(LearningGoal.selectedSurahs) ||
      _goals.contains(LearningGoal.completeQuran);

  void _next() {
    ref.read(audioProvider.notifier).stop();
    setState(() => _step++);
  }
  void _back() {
    ref.read(audioProvider.notifier).stop();
    setState(() => _step--);
  }

  Future<void> _finish() async {
    await ref.read(onboardingProvider.notifier).save(_answers());
    if (mounted) context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final onPlan = _step >= _questions;

    return Scaffold(
      appBar: AppBar(
        leading: _step > 0 ? BackButton(onPressed: _back) : null,
        title: onPlan ? Text(l.planTitle) : Text(l.stepOf(_step + 1, _questions)),
        bottom: onPlan
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: (_step + 1) / _questions),
              ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: HMotion.normal,
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: ListView(
              padding: const EdgeInsets.all(HSpace.l),
              children: onPlan ? _planView(context) : _questionView(context),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(HSpace.l),
        child: FilledButton(
          onPressed: _answered ? (onPlan ? _finish : _next) : null,
          child: Text(onPlan ? l.startLearning : l.continueLabel),
        ),
      ),
    );
  }

  List<Widget> _question(String q, List<Widget> options) =>
      [Text(q, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: HSpace.l), ...options];

  List<Widget> _questionView(BuildContext context) {
    final l = context.l10n;
    OptionTile opt<T>(String label, T value, T? current, void Function(T) set) =>
        OptionTile(label: label, selected: value == current, onTap: () => setState(() => set(value)));

    switch (_step) {
      case 0:
        final current = ref.watch(settingsProvider).locale.languageCode;
        // Language names are written in their own script so anyone can find theirs.
        return _question(l.qLanguage, [
          for (final (code, name) in const [('en', 'English'), ('ml', 'മലയാളം'), ('ar', 'العربية')])
            OptionTile(
              label: name,
              selected: current == code,
              onTap: () => ref.read(settingsProvider.notifier).setLocale(Locale(code)),
            ),
        ]);
      case 1:
        return _question(l.qReading, [
          opt(l.readingNone, ReadingAbility.none, _reading, (v) => _reading = v),
          opt(l.readingSlow, ReadingAbility.slow, _reading, (v) => _reading = v),
          opt(l.readingFluent, ReadingAbility.fluent, _reading, (v) => _reading = v),
        ]);
      case 2:
        return _question(l.qTajweed, [
          opt(l.tajweedNone, TajweedKnowledge.none, _tajweed, (v) => _tajweed = v),
          opt(l.tajweedBasic, TajweedKnowledge.basic, _tajweed, (v) => _tajweed = v),
          opt(l.tajweedGood, TajweedKnowledge.good, _tajweed, (v) => _tajweed = v),
        ]);
      case 3:
        return _question(l.qMemorised, [
          opt(l.memNone, MemorisedAmount.none, _memorised, (v) => _memorised = v),
          opt(l.memFew, MemorisedAmount.few, _memorised, (v) => _memorised = v),
          opt(l.memJuzAmma, MemorisedAmount.juzAmma, _memorised, (v) => _memorised = v),
          opt(l.memSeveralJuz, MemorisedAmount.severalJuz, _memorised, (v) => _memorised = v),
          opt(l.memHafiz, MemorisedAmount.hafiz, _memorised, (v) => _memorised = v),
        ]);
      case 4:
        OptionTile goal(String label, LearningGoal g) => OptionTile(
              label: label,
              selected: _goals.contains(g),
              onTap: () => setState(() => _goals.contains(g) ? _goals.remove(g) : _goals.add(g)),
            );
        return _question(l.qGoal, [
          Text(l.chooseAnyNumber, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: HSpace.s),
          goal(l.goalFromBeginning, LearningGoal.fromBeginning),
          goal(l.goalSelected, LearningGoal.selectedSurahs),
          goal(l.goalComplete, LearningGoal.completeQuran),
          goal(l.goalStrengthen, LearningGoal.strengthenHifz),
          goal(l.goalTajweed, LearningGoal.tajweed),
        ]);
      case 5:
        return _question(l.qTime, [
          for (final m in allowedMinutes) opt(l.minutes(m), m, _minutes, (v) => _minutes = v),
        ]);
      case 6:
        if (!_wantsNew) {
          return _question(l.qPace, [Text(l.paceNotNeeded, style: Theme.of(context).textTheme.bodyLarge)]);
        }
        return _question(l.qPace, [
          opt(l.paceGentle, Pace.gentle, _pace, (v) => _pace = v),
          opt(l.paceSteady, Pace.steady, _pace, (v) => _pace = v),
          opt(l.paceIntensive, Pace.intensive, _pace, (v) => _pace = v),
        ]);
      case 7:
        final s = ref.watch(settingsProvider);
        final index = ref.watch(translationIndexProvider).valueOrNull ?? const <TranslationInfo>[];
        return _question(l.qTranslations, [
          Text(l.chooseAnyNumber, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: HSpace.s),
          if (index.isEmpty) Text(l.translationsMissing),
          for (final t in index)
            OptionTile(
              label: '${t.lang == 'ml' ? 'മലയാളം' : 'English'} · ${t.name}',
              selected: s.translationIds.contains(t.id),
              onTap: () => ref.read(settingsProvider.notifier).toggleTranslation(t.id),
            ),
        ]);
      case 9:
        final kids = ref.watch(settingsProvider).kidsMode;
        return _question(l.qWho, [
          OptionTile(label: l.whoAdult, selected: !kids, onTap: () => ref.read(settingsProvider.notifier).setKidsMode(false)),
          OptionTile(label: l.whoChild, selected: kids, onTap: () => ref.read(settingsProvider.notifier).setKidsMode(true)),
          const SizedBox(height: HSpace.s),
          Text(l.whoHint, style: Theme.of(context).textTheme.bodyMedium),
        ]);
      default:
        final s = ref.watch(settingsProvider);
        final fatiha = ref.watch(quranProvider)?.byKey(1, 1);
        final isAr = Localizations.localeOf(context).languageCode == 'ar';
        return _question(l.qReciter, [
          Text(l.reciterHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: HSpace.s),
          for (final r in reciters)
            Padding(
              padding: const EdgeInsets.only(bottom: HSpace.s),
              child: Row(children: [
                Expanded(
                  child: OptionTile(
                    label: '${isAr ? r.nameAr : r.nameEn}${r.style == 'muallim' ? '  ★ ${l.teachingStyle}' : ''}',
                    selected: s.reciterId == r.id,
                    onTap: () => ref.read(settingsProvider.notifier).setReciter(r.id),
                  ),
                ),
                if (fatiha != null) ...[
                  const SizedBox(width: HSpace.s),
                  Padding(
                    padding: const EdgeInsets.only(bottom: HSpace.s),
                    child: PlayAyahButton(ayahs: [fatiha], reciterId: r.id),
                  ),
                ],
              ]),
            ),
        ]);
    }
  }

  List<Widget> _planView(BuildContext context) {
    final l = context.l10n;
    final plan = buildPlan(_answers());
    final level = switch (plan.level) {
      LearnerLevel.beginner => l.levelBeginner,
      LearnerLevel.intermediate => l.levelIntermediate,
      LearnerLevel.hafiz => l.levelHafiz,
    };
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: HSpace.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: HSpace.m),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ]),
        );
    return [
      const Center(child: BrandMark(size: 56)),
      const SizedBox(height: HSpace.l),
      LearningCard(
        title: l.planLevel(level),
        child: Column(children: [
          line(Icons.schedule, l.planDaily(plan.dailyMinutes)),
          line(Icons.add_circle_outline, l.planNewPerDay(plan.newAyahsPerDay)),
          line(Icons.replay, l.planRevisionShare((plan.revisionShare * 100).round())),
          if (plan.startsWithReading) line(Icons.menu_book_outlined, l.planReadingFirst),
          if (plan.cappedByTime) line(Icons.info_outline, l.planCapped),
        ]),
      ),
      const SizedBox(height: HSpace.m),
      Text(l.planSavedLocally,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
    ];
  }
}
