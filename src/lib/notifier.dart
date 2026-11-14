import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'categories.dart';
import 'config.dart';
import 'insights.dart';
import 'repo.dart';

/// Android: a phone notification the first time a budget gets close (80% or
/// running fast) or goes over, once per budget per month.
class BudgetNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  static Future<void> requestPermission() async {
    try {
      await _init();
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> check(Repo repo) async {
    try {
      await _init();
      final now = DateTime.now();
      final mk = monthKey(now);
      final budget = await repo.budgetStream(mk).first;
      final txns = (await repo.monthTxns(mk).first).where((t) => t.category != kIgnored).toList();
      final alerts = budgetAlerts(budget, txns, DateTime(now.year, now.month), now: now);
      final prefs = await SharedPreferences.getInstance();
      for (final a in alerts) {
        // Someone else's personal limit is theirs to hear about.
        if (a.key.startsWith('member:') && a.key != 'member:${repo.myName}') continue;
        final k = 'alert_${mk}_${a.key}_${a.level}';
        if (prefs.getBool(k) == true) continue;
        await prefs.setBool(k, true);
        await _plugin.show(
          k.hashCode & 0x7fffffff,
          a.title,
          a.body,
          NotificationDetails(
            android: AndroidNotificationDetails('budget_alerts', 'Budget alerts',
                channelDescription: 'When a budget is nearly used up or over',
                importance: Importance.high,
                priority: Priority.high,
                styleInformation: BigTextStyleInformation(a.body)),
          ),
        );
      }
    } catch (_) {}
  }
}
