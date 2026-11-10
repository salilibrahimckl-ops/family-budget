import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/memorisation/engine/srs.dart';
import '../../features/memorisation/progress_controller.dart';
import '../../features/onboarding/learning_plan.dart';
import '../../features/onboarding/onboarding_store.dart';
import '../data/local_db.dart';
import 'backend.dart';

/// Offline-first sync. The phone is the source of truth for its own events; the server
/// merges events from all devices:
/// - attempts, mistakes, XP, streak days: append-only, inserted with ignore-duplicates,
///   so retrying a batch or syncing from two phones never double-counts;
/// - memorisation records: per Ayah, the most recently reviewed version wins;
/// - preferences: last write wins.
class SyncService {
  SyncService(this.ref);
  final Ref ref;

  SupabaseClient? get _c => ref.read(supabaseProvider);

  Future<SyncResult> syncNow() async {
    final c = _c;
    final user = c?.auth.currentUser;
    if (c == null || user == null) return const SyncResult.skipped();
    final ldb = await ref.read(localDbProvider.future);
    final uid = user.id;
    var pushed = 0;
    var pulled = 0;

    await c.from('profiles').upsert({'user_id': uid});
    final a = ref.read(onboardingProvider);
    if (a != null) {
      final plan = buildPlan(a);
      await c.from('learning_preferences').upsert({
        'user_id': uid,
        'goal': _goalDb(a.goal),
        'level': plan.level.name,
        'ui_language': a.uiLanguage,
        'daily_minutes': a.dailyMinutes,
        'new_ayahs_per_day': plan.newAyahsPerDay,
        'arabic_reading': a.reading.index,
        'tajweed_knowledge': a.tajweed.index,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    // ---- push ----
    final db = ldb.db;
    final attempts = await db.query('attempts', where: 'synced = 0', limit: 500);
    if (attempts.isNotEmpty) {
      await c.from('recitation_attempts').upsert([
        for (final r in attempts)
          {
            'id': r['id'],
            'user_id': uid,
            'ayah_from': r['ayah_from'],
            'ayah_to': r['ayah_to'],
            'mode': r['mode'],
            'method': r['method'],
            'passed': r['passed'] == 1,
            'accuracy': r['accuracy'],
            'recall_ms': r['recall_ms'],
            'hints_used': r['hints_used'],
            'device_id': await _deviceId(ldb),
            'occurred_at': r['occurred_at'],
          }
      ], onConflict: 'id', ignoreDuplicates: true);
      final ids = [for (final r in attempts) r['id'] as String];
      final mistakes = await db.query('mistakes', where: 'attempt_id in (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
      if (mistakes.isNotEmpty) {
        // Mistakes have a server-side serial id, so replays are prevented by syncing them
        // in the same pass as their attempt and only once (attempt marked synced below).
        await c.from('detected_mistakes').insert([
          for (final m in mistakes)
            {'attempt_id': m['attempt_id'], 'user_id': uid, 'word_id': m['word_id'], 'kind': m['kind'], 'confidence': 1.0}
        ]);
      }
      await db.update('attempts', {'synced': 1}, where: 'id in (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
      pushed += attempts.length;
    }

    final xp = await db.query('xp', where: 'synced = 0', limit: 500);
    if (xp.isNotEmpty) {
      await c.from('xp_transactions').upsert([
        for (final r in xp)
          {
            'id': r['id'],
            'user_id': uid,
            'amount': r['amount'],
            'reason': r['reason'],
            'ref_attempt': r['ref_attempt'],
            'ref_ayah': r['ref_ayah'],
            'occurred_at': r['occurred_at'],
          }
      ], onConflict: 'id', ignoreDuplicates: true);
      await db.update('xp', {'synced': 1}, where: 'synced = 0 and id in (${List.filled(xp.length, '?').join(',')})',
          whereArgs: [for (final r in xp) r['id']]);
      pushed += xp.length;
    }

    final days = await db.query('streak_days', where: 'synced = 0');
    if (days.isNotEmpty) {
      await c.from('streak_days').upsert([
        for (final d in days) {'user_id': uid, 'day': (d['day'] as String).substring(0, 10), 'kind': d['kind']}
      ], onConflict: 'user_id,day', ignoreDuplicates: true);
      await db.update('streak_days', {'synced': 1}, where: 'synced = 0');
    }

    final memos = await db.query('memo_records', where: 'synced = 0');
    if (memos.isNotEmpty) {
      await c.from('memorisation_records').upsert([
        for (final m in memos) _memoToServer(uid, MemoRecord.fromMap(m), m['updated_at'] as String)
      ], onConflict: 'user_id,ayah_id');
      await db.update('memo_records', {'synced': 1}, where: 'synced = 0');
      pushed += memos.length;
    }

    // ---- pull (other devices) ----
    final remote = await c.from('memorisation_records').select().eq('user_id', uid);
    for (final r in remote) {
      final local = await db.query('memo_records', where: 'ayah_id = ?', whereArgs: [r['ayah_id']]);
      final remoteReviewed = r['last_reviewed_at'] as String?;
      final localReviewed = local.isEmpty ? null : local.first['last_reviewed_at'] as String?;
      final remoteNewer = localReviewed == null ||
          (remoteReviewed != null && DateTime.parse(remoteReviewed).isAfter(DateTime.parse(localReviewed)));
      if (remoteNewer && remoteReviewed != null) {
        await db.insert('memo_records', {..._memoFromServer(r).toMap(), 'updated_at': r['updated_at'], 'synced': 1},
            conflictAlgorithm: ConflictAlgorithm.replace);
        pulled++;
      }
    }
    final remoteXp = await c.from('xp_transactions').select().eq('user_id', uid);
    for (final r in remoteXp) {
      final n = await db.insert('xp', {
        'id': r['id'], 'amount': r['amount'], 'reason': r['reason'], 'ref_attempt': r['ref_attempt'],
        'ref_ayah': r['ref_ayah'], 'occurred_at': r['occurred_at'], 'synced': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (n > 0) pulled++;
    }
    final remoteDays = await c.from('streak_days').select().eq('user_id', uid);
    for (final d in remoteDays) {
      await db.insert('streak_days', {'day': DateTime.parse(d['day'] as String).toIso8601String(), 'kind': d['kind'], 'synced': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    ref.invalidate(progressProvider);
    return SyncResult(pushed: pushed, pulled: pulled);
  }

  /// Deletes the account on the server (Edge Function `delete-account`), then all local data.
  Future<void> deleteAccount() async {
    final c = _c;
    if (c != null && c.auth.currentUser != null) {
      await c.functions.invoke('delete-account');
      await c.auth.signOut();
    }
    final ldb = await ref.read(localDbProvider.future);
    await ldb.wipe();
    await ref.read(onboardingProvider.notifier).clear();
    ref.invalidate(progressProvider);
  }

  static Future<String> _deviceId(LocalDb ldb) async {
    final existing = await ldb.getKv('device_id');
    if (existing != null) return existing;
    final id = 'device-${DateTime.now().microsecondsSinceEpoch}';
    await ldb.setKv('device_id', id);
    return id;
  }

  static String _goalDb(LearningGoal g) => switch (g) {
        LearningGoal.fromBeginning => 'from_beginning',
        LearningGoal.selectedSurahs => 'selected_surahs',
        LearningGoal.completeQuran => 'complete_quran',
        LearningGoal.strengthenHifz => 'strengthen_hifz',
        LearningGoal.tajweed => 'tajweed',
      };

  static Map<String, Object?> _memoToServer(String uid, MemoRecord r, String updatedAt) => {
        'user_id': uid,
        'ayah_id': r.ayahId,
        'status': r.status.dbName,
        'strength': double.parse(r.strengthAt(DateTime.now()).toStringAsFixed(3)),
        'ease': double.parse(r.ease.toStringAsFixed(2)),
        'interval_days': double.parse(r.intervalDays.toStringAsFixed(2)),
        'due_at': r.dueAt?.toUtc().toIso8601String(),
        'successes': r.successes,
        'failures': r.failures,
        'lapses': r.lapses,
        'consecutive_passes': r.consecutivePasses,
        'avg_recall_ms': r.avgRecallMs,
        'user_difficulty': r.userDifficulty,
        'first_mastered_at': r.firstMasteredAt?.toUtc().toIso8601String(),
        'last_reviewed_at': r.lastReviewedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt,
      };

  static MemoRecord _memoFromServer(Map<String, dynamic> m) {
    DateTime? t(Object? v) => v == null ? null : DateTime.parse(v as String);
    final status = MemoStatus.values.firstWhere((s) => s.dbName == m['status'], orElse: () => MemoStatus.learning);
    return MemoRecord(
      ayahId: m['ayah_id'] as int,
      status: status,
      ease: (m['ease'] as num).toDouble(),
      intervalDays: (m['interval_days'] as num).toDouble(),
      dueAt: t(m['due_at']),
      successes: m['successes'] as int,
      failures: m['failures'] as int,
      lapses: m['lapses'] as int,
      consecutivePasses: m['consecutive_passes'] as int,
      avgRecallMs: m['avg_recall_ms'] as int?,
      firstMasteredAt: t(m['first_mastered_at']),
      lastReviewedAt: t(m['last_reviewed_at']),
      userDifficulty: m['user_difficulty'] as int?,
    );
  }
}

class SyncResult {
  const SyncResult({required this.pushed, required this.pulled}) : skipped = false;
  const SyncResult.skipped()
      : pushed = 0,
        pulled = 0,
        skipped = true;
  final int pushed;
  final int pulled;
  final bool skipped;
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref));
