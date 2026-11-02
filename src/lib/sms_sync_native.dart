import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'repo.dart';
import 'sms_parser.dart';

/// Runs in a background isolate when an SMS arrives and the app is closed.
@pragma('vm:entry-point')
Future<void> onBackgroundSms(SmsMessage msg) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    if (!SmsParser.looksLikeBankSender(msg.address)) return;
    final s = await Session.load();
    if (s == null) return;
    await ensureFirebase(s.cfg);
    await Repo.signIn();
    final repo = Repo(s.familyId, s.myName);
    await repo.ingestSms(msg.body ?? '',
        receivedAt: DateTime.fromMillisecondsSinceEpoch(msg.date ?? DateTime.now().millisecondsSinceEpoch),
        member: s.myName,
        source: 'sms');
  } catch (_) {
    // Missed here? The catch-up scan picks it up next time the app opens.
  }
}

class SmsSync {
  SmsSync(this.repo);
  final Repo repo;
  final _telephony = Telephony.instance;

  static bool get supported => Platform.isAndroid;

  /// Ask for SMS permission, import anything missed since the last scan
  /// (first run: from the 1st of this month), then listen for new SMS.
  Future<int> start() async {
    if (!supported) return 0;
    final granted = await _telephony.requestSmsPermissions ?? false;
    if (!granted) return 0;
    final added = await scan();
    _telephony.listenIncomingSms(
      onNewMessage: (m) async {
        if (!SmsParser.looksLikeBankSender(m.address)) return;
        await repo.ingestSms(m.body ?? '',
            receivedAt: DateTime.fromMillisecondsSinceEpoch(m.date ?? DateTime.now().millisecondsSinceEpoch),
            member: repo.myName,
            source: 'sms');
      },
      onBackgroundMessage: onBackgroundSms,
      listenInBackground: true,
    );
    return added;
  }

  Future<int> scan({DateTime? from}) async {
    if (!supported) return 0;
    final now = DateTime.now();
    final last = await Session.lastScanMs();
    final sinceMs = from?.millisecondsSinceEpoch ??
        (last != null ? last - 10 * 60 * 1000 : DateTime(now.year, now.month, 1).millisecondsSinceEpoch);
    final msgs = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.DATE).greaterThan(sinceMs.toString()),
    );
    // Oldest first, so bank balances end at the latest SMS.
    final ordered = [...msgs]..sort((a, b) => (a.date ?? 0).compareTo(b.date ?? 0));
    var added = 0;
    for (final m in ordered) {
      if (!SmsParser.looksLikeBankSender(m.address)) continue;
      final ok = await repo.ingestSms(m.body ?? '',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(m.date ?? now.millisecondsSinceEpoch),
          member: repo.myName,
          source: 'sms');
      if (ok) added++;
    }
    await Session.setLastScanMs(now.millisecondsSinceEpoch);
    return added;
  }
}
