import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/local_db.dart';
import '../../core/quran/quran_repository.dart';
import '../gamification/gamification.dart';
import '../onboarding/onboarding_store.dart';
import 'engine/daily_queue.dart';
import 'engine/srs.dart';

final localDbProvider = FutureProvider<LocalDb>((ref) => LocalDb.open());

/// Default share of words that must be recalled correctly to pass a mastery test.
const defaultMasteryThreshold = 0.9;

enum AttemptMode {
  lessonMaster('lesson_master'),
  revision('revision'),
  missingWords('challenge_missing_words'),
  completeAyah('challenge_complete_ayah'),
  randomSurah('challenge_random_surah'),
  connect('challenge_connect'),
  recovery('challenge_recovery');

  const AttemptMode(this.db);
  final String db;
}

class ProgressState {
  const ProgressState({
    required this.records,
    required this.xpTotal,
    required this.learnedDays,
    required this.freezeDays,
    required this.newDoneToday,
    required this.revisedToday,
    required this.recallTestsToday,
    required this.xpAyahsToday,
    required this.forgottenWordCounts,
    required this.focusSurahs,
  });

  final Map<int, MemoRecord> records;
  final int xpTotal;
  final Set<DateTime> learnedDays;
  final Set<DateTime> freezeDays;
  final int newDoneToday;
  final int revisedToday;
  final int recallTestsToday;
  final Set<int> xpAyahsToday; // Ayahs that already earned revision XP today
  final Map<int, int> forgottenWordCounts; // ayahId -> words missed in the last 30 days
  final List<int> focusSurahs;

  Iterable<MemoRecord> get memorised => records.values.where((r) => r.isMemorised);
  int get memorisedCount => memorised.length;

  int retainedCount(DateTime now) =>
      memorised.where((r) => const {MemoStatus.stable, MemoStatus.strong}.contains(deriveStatus(r, now))).length;

  int streak(DateTime now) => currentStreak(learnedDays, freezeDays, now);

  List<int> weakest(DateTime now, {int limit = 5}) {
    final list = memorised.toList()..sort((a, b) => a.strengthAt(now).compareTo(b.strengthAt(now)));
    return [for (final r in list.take(limit)) if (r.strengthAt(now) < 0.5) r.ayahId];
  }
}

class ProgressController extends AsyncNotifier<ProgressState> {
  final _uuid = const Uuid();

  Future<LocalDb> get _db => ref.read(localDbProvider.future);

  @override
  Future<ProgressState> build() async {
    final db = await ref.watch(localDbProvider.future);
    await _autoFreeze(db);
    return _load(db);
  }

  Future<ProgressState> _load(LocalDb ldb) async {
    final db = ldb.db;
    final now = DateTime.now();
    final today = dayOf(now).toIso8601String();
    final recs = {for (final m in await db.query('memo_records')) m['ayah_id'] as int: MemoRecord.fromMap(m)};
    final xp = Sqflite.firstIntValue(await db.rawQuery('select coalesce(sum(amount),0) from xp')) ?? 0;
    final days = await db.query('streak_days');
    final learned = {for (final d in days) if (d['kind'] == 'learned') DateTime.parse(d['day'] as String)};
    final frozen = {for (final d in days) if (d['kind'] == 'freeze_used') DateTime.parse(d['day'] as String)};
    final newToday = Sqflite.firstIntValue(await db.rawQuery(
            "select count(*) from xp where reason = 'new_ayah' and occurred_at >= ?", [today])) ??
        0;
    final revisedToday = Sqflite.firstIntValue(await db.rawQuery(
            "select count(*) from attempts where mode = 'revision' and occurred_at >= ?", [today])) ??
        0;
    final recallToday = Sqflite.firstIntValue(await db.rawQuery(
            "select count(*) from attempts where mode like 'challenge_%' and occurred_at >= ?", [today])) ??
        0;
    final xpAyahs = {
      for (final r in await db.rawQuery(
          "select ref_ayah from xp where reason = 'revision_pass' and occurred_at >= ? and ref_ayah is not null", [today]))
        r['ref_ayah'] as int
    };
    final since = now.subtract(const Duration(days: 30)).toUtc().toIso8601String();
    final forgotten = {
      for (final r in await db.rawQuery(
          'select word_id / 1000 as ayah, count(*) as n from mistakes m join attempts a on a.id = m.attempt_id '
          'where a.occurred_at >= ? group by word_id / 1000',
          [since]))
        r['ayah'] as int: r['n'] as int
    };
    final focusRaw = await ldb.getKv('focus_surahs');
    final focus = focusRaw == null || focusRaw.isEmpty ? <int>[] : focusRaw.split(',').map(int.parse).toList();

    return ProgressState(
      records: recs,
      xpTotal: xp,
      learnedDays: learned,
      freezeDays: frozen,
      newDoneToday: newToday,
      revisedToday: revisedToday,
      recallTestsToday: recallToday,
      xpAyahsToday: xpAyahs,
      forgottenWordCounts: forgotten,
      focusSurahs: focus,
    );
  }

  /// Covers yesterday's gap with a freeze token if one is available (compassionate streaks).
  Future<void> _autoFreeze(LocalDb ldb) async {
    final days = await ldb.db.query('streak_days');
    final learned = {for (final d in days) if (d['kind'] == 'learned') DateTime.parse(d['day'] as String)};
    final frozen = {for (final d in days) if (d['kind'] == 'freeze_used') DateTime.parse(d['day'] as String)};
    final avail = freezesAvailable(learned.length, frozen.length);
    for (final d in daysToFreeze(learned, frozen, DateTime.now(), avail)) {
      await ldb.db.insert('streak_days', {'day': d.toIso8601String(), 'kind': 'freeze_used'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  DailyQueue queue(ProgressState s, DateTime now) {
    final plan = ref.read(learningPlanProvider);
    return buildDailyQueue(
      s.records.values,
      now,
      newPerDay: plan?.newAyahsPerDay ?? 0,
      dailyMinutes: plan?.dailyMinutes ?? 20,
      revisionShare: plan?.revisionShare ?? 0.5,
      newDoneToday: s.newDoneToday,
      forgottenWordCounts: s.forgottenWordCounts,
    );
  }

  /// Next Ayah to memorise, following the learning order and skipping started Ayahs.
  VerifiedAyah? nextNewAyah(ProgressState s, QuranRepository quran) {
    for (final surah in learningSurahOrder(focusSurahs: s.focusSurahs)) {
      for (final a in quran.surah(surah)) {
        final r = s.records[a.id];
        if (r == null || !r.isMemorised) return a;
      }
    }
    return null;
  }

  Future<void> setFocusSurah(int surah) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final list = [surah, ...s.focusSurahs.where((x) => x != surah)];
    await (await _db).setKv('focus_surahs', list.join(','));
    ref.invalidateSelf();
  }

  /// Saves one attempt with its missed words, updates the schedule, awards XP, marks the day.
  /// Returns the XP earned (0 when nothing was earned).
  Future<int> record({
    required VerifiedAyah ayah,
    required AttemptMode mode,
    required double accuracy,
    required Set<int> missedWordPositions,
    required QuranRepository quran,
    int? recallMs,
    int hintsUsed = 0,
    double masteryThreshold = defaultMasteryThreshold,
    VerifiedAyah? rangeStart,
  }) async {
    final ldb = await _db;
    final db = ldb.db;
    final now = DateTime.now();
    final s = state.valueOrNull ?? await _load(ldb);
    final before = s.records[ayah.id] ?? MemoRecord(ayahId: ayah.id);
    final grade = gradeFromAccuracy(accuracy, masteryThreshold: masteryThreshold, hesitated: hintsUsed > 0);
    final passed = grade != Grade.again;
    final wasDue = before.dueAt == null || !before.dueAt!.isAfter(now.add(const Duration(hours: 12)));

    final isMasteryTest = mode == AttemptMode.lessonMaster;
    final after = applyReview(before, grade, now, recallMs: recallMs, mastered: isMasteryTest && passed);
    final attemptId = _uuid.v4();
    var xpEarned = 0;

    await db.transaction((txn) async {
      await txn.insert('attempts', {
        'id': attemptId,
        'ayah_from': (rangeStart ?? ayah).id,
        'ayah_to': ayah.id,
        'mode': mode.db,
        'method': 'self_report',
        'passed': passed ? 1 : 0,
        'accuracy': accuracy,
        'recall_ms': recallMs,
        'hints_used': hintsUsed,
        'occurred_at': now.toUtc().toIso8601String(),
      });
      for (final pos in missedWordPositions) {
        await txn.insert('mistakes', {'attempt_id': attemptId, 'word_id': ayah.wordId(pos), 'kind': 'missing'});
      }
      // Challenges on Ayahs not yet memorised don't change the schedule; nor does multiple
      // choice, which tests recognition rather than recall.
      if (isMasteryTest || (before.isMemorised && mode != AttemptMode.missingWords)) {
        await txn.insert('memo_records', {...after.toMap(), 'updated_at': now.toUtc().toIso8601String(), 'synced': 0},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      Future<void> award(XpReason reason, int amount, {int? ayahId}) async {
        if (amount <= 0) return;
        xpEarned += amount;
        await txn.insert('xp', {
          'id': _uuid.v4(),
          'amount': amount,
          'reason': reason.dbName,
          'ref_attempt': attemptId,
          'ref_ayah': ayahId,
          'occurred_at': now.toUtc().toIso8601String(),
        });
      }

      if (isMasteryTest && passed && !before.isMemorised) {
        await award(XpReason.newAyah, XpRules.newAyah, ayahId: ayah.id);
        final surahAyahs = quran.surah(ayah.surah);
        final allDone = surahAyahs.every((a) => a.id == ayah.id || (s.records[a.id]?.isMemorised ?? false));
        if (allDone) await award(XpReason.surahComplete, XpRules.surahComplete, ayahId: ayah.id);
      } else if (mode == AttemptMode.revision && passed) {
        await award(
          XpReason.revisionPass,
          revisionXp(
            wasDue: wasDue,
            alreadyRewardedToday: s.xpAyahsToday.contains(ayah.id),
            wasStrong: before.status == MemoStatus.strong,
          ),
          ayahId: ayah.id,
        );
      } else if (mode != AttemptMode.lessonMaster && mode != AttemptMode.revision) {
        await award(XpReason.challenge, XpRules.challenge(accuracy), ayahId: ayah.id);
      }

      final today = dayOf(now).toIso8601String();
      final firstToday = Sqflite.firstIntValue(
              await txn.rawQuery("select count(*) from streak_days where day = ? and kind = 'learned'", [today])) ==
          0;
      if (firstToday) {
        await txn.insert('streak_days', {'day': today, 'kind': 'learned'}, conflictAlgorithm: ConflictAlgorithm.replace);
        await award(XpReason.dailySession, XpRules.dailySession);
      }
    });

    state = AsyncData(await _load(ldb));
    return xpEarned;
  }

  /// User-reported difficulty (1–5) for an Ayah; feeds the queue ordering through ease.
  Future<void> setDifficulty(int ayahId, int difficulty) async {
    final ldb = await _db;
    final s = state.valueOrNull;
    final r = s?.records[ayahId];
    if (r == null) return;
    final adjusted = r.copyWith(userDifficulty: difficulty, ease: (r.ease - (difficulty - 3) * 0.05).clamp(1.3, 3.5).toDouble());
    await ldb.db.insert('memo_records', {...adjusted.toMap(), 'updated_at': DateTime.now().toUtc().toIso8601String(), 'synced': 0},
        conflictAlgorithm: ConflictAlgorithm.replace);
    state = AsyncData(await _load(ldb));
  }
}

final progressProvider = AsyncNotifierProvider<ProgressController, ProgressState>(ProgressController.new);
