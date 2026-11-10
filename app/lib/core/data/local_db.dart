import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// On-device database: the source of truth for progress. Works fully offline;
/// rows with synced = 0 are pushed to Supabase by SyncService when online.
class LocalDb {
  LocalDb._(this.db);
  final Database db;

  static const _version = 1;

  static Future<LocalDb> open({String name = 'hifz.db'}) async {
    // Phones: native SQLite. Web (iPhone home-screen app): SQLite compiled to WebAssembly,
    // stored in the browser's IndexedDB, so progress stays on the device between visits.
    final factory = kIsWeb ? databaseFactoryFfiWeb : databaseFactory;
    final path = kIsWeb ? name : p.join(await getDatabasesPath(), name);
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: _version, onCreate: (db, v) async {
      final b = db.batch();
      b.execute('''create table memo_records(
        ayah_id integer primary key, status text not null, ease real not null, interval_days real not null,
        due_at text, successes integer not null, failures integer not null, lapses integer not null,
        consecutive_passes integer not null, avg_recall_ms integer, first_mastered_at text,
        last_reviewed_at text, user_difficulty integer, updated_at text not null, synced integer not null default 0)''');
      b.execute('create index memo_due on memo_records(due_at)');
      b.execute('''create table attempts(
        id text primary key, ayah_from integer not null, ayah_to integer not null, mode text not null,
        method text not null, passed integer not null, accuracy real, recall_ms integer, hints_used integer not null default 0,
        occurred_at text not null, synced integer not null default 0)''');
      b.execute('create index attempts_time on attempts(occurred_at)');
      b.execute('''create table mistakes(
        attempt_id text not null, word_id integer not null, kind text not null, primary key(attempt_id, word_id))''');
      b.execute('''create table xp(
        id text primary key, amount integer not null, reason text not null, ref_attempt text, ref_ayah integer,
        occurred_at text not null, synced integer not null default 0)''');
      b.execute('create table streak_days(day text primary key, kind text not null, synced integer not null default 0)');
      b.execute('create table kv(key text primary key, value text not null)');
      await b.commit(noResult: true);
    }));
    return LocalDb._(db);
  }

  Future<String?> getKv(String key) async {
    final r = await db.query('kv', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setKv(String key, String value) =>
      db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Removes all learning data on this device (used by account deletion and "reset progress").
  Future<void> wipe() async {
    for (final t in ['memo_records', 'attempts', 'mistakes', 'xp', 'streak_days', 'kv']) {
      await db.delete(t);
    }
  }
}
