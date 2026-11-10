import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/local_db.dart';
import '../gamification/gamification.dart';

/// Demo mode: the app runs on a separate sample database, so every screen shows what
/// it looks like after a few weeks of use. The learner's own database is never touched,
/// nothing is synced, and leaving demo mode brings their own progress straight back.
final demoModeProvider = StateProvider<bool>((ref) => false);

/// First Ayah id and Ayah count of the Surahs used in the sample (checked against
/// assets/quran/surahs.json).
const _surahs = <int, (int, int)>{
  1: (1, 7),
  105: (6189, 5),
  106: (6194, 4),
  107: (6198, 7),
  108: (6205, 3),
  109: (6208, 6),
  110: (6214, 3),
  111: (6217, 5),
  112: (6222, 4),
  113: (6226, 5),
  114: (6231, 6),
};

Future<LocalDb> openDemoDb() async {
  final ldb = await LocalDb.open(name: 'hifz_demo.db');
  await ldb.wipe(); // fresh sample every time, so dates stay relative to today
  await _seed(ldb);
  return ldb;
}

Future<void> _seed(LocalDb ldb) async {
  final db = ldb.db;
  final now = DateTime.now();
  final today = dayOf(now);
  String iso(DateTime t) => t.toUtc().toIso8601String();
  var n = 0;
  String nextId() => 'demo-${n++}';
  final b = db.batch();

  void memo(int ayahId,
      {required int masteredDaysAgo,
      required double interval,
      required int passes,
      required int successes,
      required Duration dueIn,
      int lapses = 0}) {
    final mastered = now.subtract(Duration(days: masteredDaysAgo, hours: 2));
    b.insert('memo_records', {
      'ayah_id': ayahId,
      'status': 'stable',
      'ease': 2.5,
      'interval_days': interval,
      'due_at': iso(now.add(dueIn)),
      'successes': successes,
      'failures': lapses,
      'lapses': lapses,
      'consecutive_passes': passes,
      'avg_recall_ms': 6000,
      'first_mastered_at': iso(mastered),
      'last_reviewed_at': iso(now.subtract(Duration(days: interval.round().clamp(0, masteredDaysAgo)))),
      'user_difficulty': null,
      'updated_at': iso(now),
      'synced': 1,
    });
    b.insert('xp', {
      'id': nextId(),
      'amount': XpRules.newAyah,
      'reason': XpReason.newAyah.dbName,
      'ref_ayah': ayahId,
      'occurred_at': iso(mastered),
      'synced': 1,
    });
  }

  void surah(int s, {required int masteredDaysAgo, required double interval, required int passes, required int successes, required Duration dueIn, int lapses = 0, int? onlyFirst}) {
    final (first, count) = _surahs[s]!;
    for (var i = 0; i < (onlyFirst ?? count); i++) {
      memo(first + i,
          masteredDaysAgo: masteredDaysAgo, interval: interval, passes: passes, successes: successes, dueIn: dueIn, lapses: lapses);
    }
  }

  // Strong: Al-Fatiha and the last three Surahs.
  surah(1, masteredDaysAgo: 60, interval: 30, passes: 4, successes: 6, dueIn: const Duration(days: 12));
  for (final s in [112, 113, 114]) {
    surah(s, masteredDaysAgo: 45, interval: 24, passes: 3, successes: 5, dueIn: const Duration(days: 9));
  }
  // Stable.
  for (final s in [109, 110, 111]) {
    surah(s, masteredDaysAgo: 25, interval: 9, passes: 2, successes: 3, dueIn: const Duration(days: 3));
  }
  // Recently memorised and due today, so the revision queue has work in it.
  surah(108, masteredDaysAgo: 4, interval: 2, passes: 1, successes: 2, dueIn: const Duration(hours: -2));
  surah(107, masteredDaysAgo: 3, interval: 1, passes: 1, successes: 1, dueIn: const Duration(hours: -1));
  // Slipping: the last review failed.
  surah(106, masteredDaysAgo: 18, interval: 0, passes: 0, successes: 2, lapses: 1, dueIn: const Duration(hours: -6));
  // In progress: Al-Fil, two Ayahs so far (one today).
  surah(105, masteredDaysAgo: 1, interval: 1, passes: 1, successes: 1, dueIn: const Duration(days: 1), onlyFirst: 1);
  memo(6190, masteredDaysAgo: 0, interval: 1, passes: 1, successes: 1, dueIn: const Duration(days: 1));

  // A 12-day streak with one freeze day.
  for (var d = 1; d <= 12; d++) {
    b.insert('streak_days', {'day': today.subtract(Duration(days: d)).toIso8601String(), 'kind': d == 5 ? 'freeze_used' : 'learned', 'synced': 1});
  }
  b.insert('streak_days', {'day': today.toIso8601String(), 'kind': 'learned', 'synced': 1});

  // Past revisions, a few with missed words, plus daily-session XP.
  for (var d = 1; d <= 30; d++) {
    final when = now.subtract(Duration(days: d, hours: 3));
    final ayah = 6208 + (d % 20);
    final perfect = d % 4 != 0;
    final attemptId = nextId();
    b.insert('attempts', {
      'id': attemptId,
      'ayah_from': ayah,
      'ayah_to': ayah,
      'mode': 'revision',
      'method': d % 3 == 0 ? 'asr_word' : 'self_report',
      'passed': 1,
      'accuracy': perfect ? 1.0 : 0.8,
      'recall_ms': 5000,
      'hints_used': 0,
      'occurred_at': iso(when),
      'synced': 1,
    });
    if (!perfect) b.insert('mistakes', {'attempt_id': attemptId, 'word_id': 6195 * 1000 + 2, 'kind': 'missing'});
    b.insert('xp', {'id': nextId(), 'amount': XpRules.revisionPass, 'reason': XpReason.revisionPass.dbName, 'ref_ayah': ayah, 'occurred_at': iso(when), 'synced': 1});
    if (d <= 12 && d != 5) {
      b.insert('xp', {'id': nextId(), 'amount': XpRules.dailySession, 'reason': XpReason.dailySession.dbName, 'occurred_at': iso(when), 'synced': 1});
    }
  }
  b.insert('kv', {'key': 'focus_surahs', 'value': '105'});
  await b.commit(noResult: true);
}
